import AppKit

/// Owns the menu-bar status items, the polling timer, and the settings window.
final class StatusController: NSObject {

    // MARK: - Persistence keys
    static let prefsMonitoredKey = "MonitoredDisks"
    static let prefsDurationKey = "LEDDurationMs"
    static let prefsLEDColorsKey = "LEDColors"
    static let prefsDiskOrderKey = "DiskOrder"

    // MARK: - State
    private var statusItems: [String: NSStatusItem] = [:]
    private var placeholderStatusItem: NSStatusItem?
    private var pollTimer: Timer?
    private var offTimers: [String: Timer] = [:]
    private var statusItemOrder: [String] = []
    private var settingsWindowController: SettingsWindowController?

    private var disks: [DiskInfo] = []
    private var diskOrder: [String] = []
    private var monitored: Set<String> = []          // BSD names the user chose
    private var lastStats: [String: DiskStats] = [:] // last sample per BSD name
    private var hasInitializedDefaults = false

    private var litDisks: Set<String> = []
    private let pollIntervalSec: TimeInterval = 0.050
    private var ledDurationSec: TimeInterval = 0.010
    private var ledColors: [String: LEDRenderer.LEDColor] = [:]
    private let statusItemLength: CGFloat = 12

    // MARK: - Init

    override init() {
        super.init()

        loadPreferences()
        refreshDisks()
        updateStatusItems()
        startPolling()
    }

    // MARK: - Preferences

    private func loadPreferences() {
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: Self.prefsMonitoredKey) as? [String] {
            monitored = Set(saved)
            hasInitializedDefaults = true
        }
        if let saved = defaults.array(forKey: Self.prefsDiskOrderKey) as? [String] {
            diskOrder = saved
        }
        if let ms = defaults.object(forKey: Self.prefsDurationKey) as? Double, ms > 0 {
            ledDurationSec = ms / 1000.0
        }
        if let saved = defaults.dictionary(forKey: Self.prefsLEDColorsKey) as? [String: String] {
            ledColors = saved.compactMapValues { LEDRenderer.LEDColor(rawValue: $0) }
        }
    }

    private func saveMonitored() {
        UserDefaults.standard.set(Array(monitored), forKey: Self.prefsMonitoredKey)
    }

    private func saveDiskOrder() {
        UserDefaults.standard.set(diskOrder, forKey: Self.prefsDiskOrderKey)
    }

    private func saveLEDColors() {
        let rawColors = ledColors.mapValues(\.rawValue)
        UserDefaults.standard.set(rawColors, forKey: Self.prefsLEDColorsKey)
    }

    // MARK: - Settings

    @objc private func openSettings() {
        refreshDisks()

        let controller = settingsWindowController ?? SettingsWindowController()
        settingsWindowController = controller
        controller.onEnabledChanged = { [weak self] bsd, isEnabled in
            self?.setDisk(bsd, enabled: isEnabled)
        }
        controller.onColorChanged = { [weak self] bsd, color in
            self?.setLEDColor(color, for: bsd)
        }
        controller.onOrderChanged = { [weak self] order in
            self?.setDiskOrder(order)
        }
        controller.update(
            disks: disks,
            monitored: monitored,
            colors: ledColors
        )
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setDisk(_ bsd: String, enabled: Bool) {
        if enabled {
            monitored.insert(bsd)
            lastStats[bsd] = DiskMonitor.readStats(bsdName: bsd)
        } else {
            monitored.remove(bsd)
            lastStats.removeValue(forKey: bsd)
        }
        saveMonitored()
        updateStatusItems()
        settingsWindowController?.update(disks: disks, monitored: monitored, colors: ledColors)
    }

    private func setLEDColor(_ color: LEDRenderer.LEDColor, for bsd: String) {
        ledColors[bsd] = color
        saveLEDColors()
        redrawStatusItem(for: bsd)
        settingsWindowController?.update(disks: disks, monitored: monitored, colors: ledColors)
    }

    private func setDiskOrder(_ order: [String]) {
        let known = Set(disks.map(\.bsdName))
        diskOrder = order.filter { known.contains($0) } + disks.map(\.bsdName).filter { !order.contains($0) }
        saveDiskOrder()
        disks = orderedDisks(disks)
        updateStatusItems()
    }

    // MARK: - Disk list

    private func refreshDisks() {
        disks = orderedDisks(DiskMonitor.enumerate())

        // First run: monitor the first detected disk by default. Sorting in
        // DiskMonitor makes disk0, normally the system disk, win when present.
        if !hasInitializedDefaults, let first = disks.first {
            monitored = [first.bsdName]
            hasInitializedDefaults = true
            saveMonitored()
        }
    }

    private func orderedDisks(_ enumerated: [DiskInfo]) -> [DiskInfo] {
        let names = enumerated.map(\.bsdName)
        let reconciled = diskOrder.filter { names.contains($0) } + names.filter { !diskOrder.contains($0) }
        if reconciled != diskOrder {
            diskOrder = reconciled
            saveDiskOrder()
        }

        let indexByName = Dictionary(uniqueKeysWithValues: diskOrder.enumerated().map { ($1, $0) })
        return enumerated.sorted {
            let lhs = indexByName[$0.bsdName] ?? Int.max
            let rhs = indexByName[$1.bsdName] ?? Int.max
            if lhs == rhs {
                return $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending
            }
            return lhs < rhs
        }
    }

    // MARK: - Polling

    private func startPolling() {
        for bsd in monitored {
            lastStats[bsd] = DiskMonitor.readStats(bsdName: bsd)
        }

        let t = Timer(timeInterval: pollIntervalSec, repeats: true) { [weak self] _ in
            self?.poll()
        }
        RunLoop.current.add(t, forMode: .common)
        pollTimer = t
    }

    private func poll() {
        for bsd in monitored {
            guard let current = DiskMonitor.readStats(bsdName: bsd) else {
                lastStats.removeValue(forKey: bsd)
                continue
            }
            if let prev = lastStats[bsd], current != prev {
                flashLED(for: bsd)
            }
            lastStats[bsd] = current
        }
    }

    // MARK: - Status items

    private func updateStatusItems() {
        let activeNames = disks.map(\.bsdName).filter { monitored.contains($0) }
        let active = Set(activeNames)
        let menu = statusMenu()
        let removed = statusItems.keys.filter { !active.contains($0) }
        for bsd in removed {
            guard let item = statusItems[bsd] else { continue }
            NSStatusBar.system.removeStatusItem(item)
            offTimers[bsd]?.invalidate()
            offTimers.removeValue(forKey: bsd)
            litDisks.remove(bsd)
            statusItems.removeValue(forKey: bsd)
        }

        if activeNames != statusItemOrder {
            for (_, item) in statusItems {
                NSStatusBar.system.removeStatusItem(item)
            }
            statusItems.removeAll()
            statusItemOrder = []
        }

        // AppKit inserts new status items to the left of existing items, so
        // create them in reverse to make the visible menu-bar order match the
        // settings table order.
        for disk in disks.reversed() where active.contains(disk.bsdName) {
            let item = statusItems[disk.bsdName] ?? NSStatusBar.system.statusItem(withLength: statusItemLength)
            item.length = statusItemLength
            statusItems[disk.bsdName] = item
            item.menu = menu
            item.button?.image = LEDRenderer.image(
                on: litDisks.contains(disk.bsdName),
                color: ledColor(for: disk.bsdName)
            )
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = disk.displayName
        }
        statusItemOrder = activeNames

        if statusItems.isEmpty {
            let item = placeholderStatusItem ?? NSStatusBar.system.statusItem(withLength: statusItemLength)
            item.length = statusItemLength
            placeholderStatusItem = item
            item.menu = menu
            item.button?.image = LEDRenderer.image(on: false, color: .red)
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = "BlinkenDisk - no drives monitored"
        } else if let item = placeholderStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            placeholderStatusItem = nil
        }
    }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit BlinkenDisk", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func ledColor(for bsd: String) -> LEDRenderer.LEDColor {
        return ledColors[bsd] ?? .red
    }

    private func redrawStatusItem(for bsd: String) {
        if let item = statusItems[bsd] {
            item.button?.image = LEDRenderer.image(on: litDisks.contains(bsd), color: ledColor(for: bsd))
        }
    }

    // MARK: - LED control

    private func flashLED(for bsd: String) {
        if !litDisks.contains(bsd) {
            litDisks.insert(bsd)
            statusItems[bsd]?.button?.image = LEDRenderer.image(on: true, color: ledColor(for: bsd))
        }
        offTimers[bsd]?.invalidate()
        let t = Timer(timeInterval: ledDurationSec, repeats: false) { [weak self] _ in
            self?.turnOffLED(for: bsd)
        }
        RunLoop.current.add(t, forMode: .common)
        offTimers[bsd] = t
    }

    private func turnOffLED(for bsd: String) {
        guard litDisks.contains(bsd) else { return }
        litDisks.remove(bsd)
        offTimers.removeValue(forKey: bsd)
        statusItems[bsd]?.button?.image = LEDRenderer.image(on: false, color: ledColor(for: bsd))
    }
}

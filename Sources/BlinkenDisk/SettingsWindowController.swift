import AppKit

final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onEnabledChanged: ((String, Bool) -> Void)?
    var onColorChanged: ((String, LEDRenderer.LEDColor) -> Void)?
    var onOrderChanged: (([String]) -> Void)?

    private struct Row {
        let disk: DiskInfo
        var isEnabled: Bool
        var color: LEDRenderer.LEDColor
    }

    private enum Column {
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let color = NSUserInterfaceItemIdentifier("color")
    }

    private let tableView = NSTableView()
    private var rows: [Row] = []
    private let dragType = NSPasteboard.PasteboardType("local.blinkendisk.disk-row")

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "BlinkenDisk"
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(disks: [DiskInfo], monitored: Set<String>, colors: [String: LEDRenderer.LEDColor]) {
        rows = disks.map {
            Row(disk: $0, isEnabled: monitored.contains($0.bsdName), color: colors[$0.bsdName] ?? .red)
        }
        tableView.reloadData()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.rowSizeStyle = .medium
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([dragType])

        let enabledColumn = NSTableColumn(identifier: Column.enabled)
        enabledColumn.title = ""
        enabledColumn.width = 44
        enabledColumn.minWidth = 44
        enabledColumn.maxWidth = 44
        tableView.addTableColumn(enabledColumn)

        let nameColumn = NSTableColumn(identifier: Column.name)
        nameColumn.title = "Drive"
        nameColumn.width = 360
        nameColumn.minWidth = 180
        tableView.addTableColumn(nameColumn)

        let colorColumn = NSTableColumn(identifier: Column.color)
        colorColumn.title = "LED"
        colorColumn.width = 120
        colorColumn.minWidth = 100
        tableView.addTableColumn(colorColumn)

        scrollView.documentView = tableView

        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.bezelStyle = .rounded

        contentView.addSubview(scrollView)
        contentView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -16),

            closeButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            closeButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        window?.center()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let rowData = rows[row]

        switch identifier {
        case Column.enabled:
            let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleEnabled(_:)))
            button.state = rowData.isEnabled ? .on : .off
            button.alignment = .center
            button.tag = row
            return centered(button)

        case Column.name:
            let label = NSTextField(labelWithString: rowData.disk.displayName)
            label.lineBreakMode = .byTruncatingMiddle
            return padded(label)

        case Column.color:
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.target = self
            popup.action = #selector(changeColor(_:))
            popup.tag = row
            if rowData.isEnabled {
                for color in LEDRenderer.LEDColor.allCases {
                    popup.addItem(withTitle: color.displayName)
                    popup.lastItem?.representedObject = color.rawValue
                }
                popup.selectItem(withTitle: rowData.color.displayName)
                popup.isEnabled = true
            } else {
                popup.addItem(withTitle: "Grey")
                popup.isEnabled = false
            }
            return padded(popup)

        default:
            return nil
        }
    }

    private func centered(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func padded(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
            view.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    // MARK: - Actions

    @objc private func toggleEnabled(_ sender: NSButton) {
        let row = sender.tag
        guard rows.indices.contains(row) else { return }
        let isEnabled = sender.state == .on
        rows[row].isEnabled = isEnabled
        tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integersIn: 0..<tableView.numberOfColumns))
        onEnabledChanged?(rows[row].disk.bsdName, isEnabled)
    }

    @objc private func changeColor(_ sender: NSPopUpButton) {
        let row = sender.tag
        guard rows.indices.contains(row),
              let rawColor = sender.selectedItem?.representedObject as? String,
              let color = LEDRenderer.LEDColor(rawValue: rawColor) else {
            return
        }
        rows[row].color = color
        onColorChanged?(rows[row].disk.bsdName, color)
    }

    @objc private func closeWindow() {
        window?.close()
    }

    // MARK: - Drag/drop

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard rows.indices.contains(row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(rows[row].disk.bsdName, forType: dragType)
        return item
    }

    func tableView(
        _ tableView: NSTableView,
        validateDrop info: NSDraggingInfo,
        proposedRow row: Int,
        proposedDropOperation dropOperation: NSTableView.DropOperation
    ) -> NSDragOperation {
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(
        _ tableView: NSTableView,
        acceptDrop info: NSDraggingInfo,
        row: Int,
        dropOperation: NSTableView.DropOperation
    ) -> Bool {
        guard let bsd = info.draggingPasteboard.string(forType: dragType),
              let source = rows.firstIndex(where: { $0.disk.bsdName == bsd }) else {
            return false
        }

        var destination = row < 0 ? rows.count : row
        let moved = rows.remove(at: source)
        if source < destination {
            destination -= 1
        }
        destination = max(0, min(destination, rows.count))
        rows.insert(moved, at: destination)

        tableView.reloadData()
        onOrderChanged?(rows.map { $0.disk.bsdName })
        return true
    }
}

import AppKit

if CommandLine.arguments.contains("/reset") {
    let defaults = UserDefaults.standard
    defaults.removeObject(forKey: StatusController.prefsMonitoredKey)
    defaults.removeObject(forKey: StatusController.prefsDurationKey)
    defaults.removeObject(forKey: StatusController.prefsLEDColorsKey)
    defaults.removeObject(forKey: StatusController.prefsDiskOrderKey)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Hide from Dock and command-tab; menu bar item is the only UI.
app.setActivationPolicy(.accessory)
app.run()

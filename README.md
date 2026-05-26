# BlinkenDisk

A tiny macOS utility that puts a red LED in your menu bar and lights it up
whenever there's I/O activity on the local drives you choose to monitor.

It's the modern-era equivalent of the activity light on the front of an old
desktop tower.

## Features

- **Menu bar LEDs.** Lives in the menu bar ("clock bar"), not as a floating
  window — though it's a normal `NSStatusItem`, so it behaves like any other
  menu-bar utility. Each monitored drive gets its own LED.
- **Realistic LED.** Drawn as a small dome with a specular highlight; "off"
  is a dim tinted state so you can always see where the indicator is.
- **Small status menu.** Click any LED to open a menu with Settings... and
  Quit BlinkenDisk. Settings opens a window with a grid of local block-storage
  devices.
- **Per-drive selection.** The settings grid lets you enable each drive and
  choose its LED color; each LED's tooltip shows its drive name.
- **Per-drive ordering.** Drag rows in the settings grid to control the order
  of the menu-bar LEDs.
- **Configurable flash duration.** Default 10 ms.
- **Per-drive LED color.** Choose red, green, yellow, amber, or blue for each
  monitored drive.
- **No Dock icon, no menu bar of its own.** Built as an `LSUIElement` agent app.
- **Persistent.** Your drive selections, LED colors, order, and chosen duration survive restarts
  (stored in `~/Library/Preferences/local.blinkendisk.plist` once installed).

## Requirements

- macOS 12 (Monterey) or later
- Xcode 14+ command line tools (`xcode-select --install`) — the Swift toolchain
  is what builds it; you don't need the full Xcode IDE.

## License

BlinkenDisk is licensed for personal, non-commercial use only. Commercial use,
organizational use, and commercial redistribution require prior written
permission. See [LICENSE](LICENSE) for the full terms and warranty disclaimers.

## Build

From the project directory:

```sh
./build.sh
```

This runs `swift build -c release` and assembles `BlinkenDisk.app`. Then:

```sh
open BlinkenDisk.app
```

…or just double-click it in Finder. Move it to `/Applications` if you want it
to live there. To launch on login, drag it into **System Settings → General →
Login Items**.

To reset saved drive selections, colors, order, and duration:

```sh
open BlinkenDisk.app --args /reset
```

### Quick run without bundling

If you just want to try it without making a `.app`:

```sh
swift run -c release BlinkenDisk
```

The accessory activation policy is set in code, so you still won't get a Dock
icon — but you'll need to keep the terminal open, and `Cmd-Tab` may briefly
show the binary on launch. The proper `.app` is cleaner.

## How it works

- A Foundation `Timer` polls every **50 ms**.
- For each monitored disk it reads the `Statistics` dictionary from the
  matching `IOBlockStorageDriver` IOKit service (cumulative `Bytes (Read)`,
  `Bytes (Write)`, `Operations (Read)`, `Operations (Write)`).
- If any counter changed since the previous sample, that drive's LED is set to "on"
  and an off-timer is scheduled for the configured duration. Sustained I/O
  keeps rescheduling that timer, so the LED stays solidly lit during heavy
  activity and flickers briefly during small bursts.
- Drive list is built by iterating `IOBlockStorageDriver` services; this
  covers the whole disk (e.g. `disk0`), so all of its partitions are included
  by monitoring the disk once. Human-readable names come from DiskArbitration
  (`DADiskCopyDescription`).

### A note on short flashes

10 ms is below one frame at 60 Hz (~16.7 ms), so the LED is *programmatically*
on for the configured duration but the **visible** flash is floored by your
display's refresh rate. On a 120 Hz ProMotion display the floor is ~8 ms;
either way you'll always see at least one frame of red for every detected
sample.

## Project layout

```
BlinkenDisk/
├── Package.swift
├── build.sh                                  ← builds and bundles BlinkenDisk.app
├── README.md
└── Sources/BlinkenDisk/
    ├── main.swift                            ← entry point
    ├── AppDelegate.swift
    ├── StatusController.swift                ← NSStatusItem, polling
    ├── SettingsWindowController.swift        ← settings dialog
    ├── DiskMonitor.swift                     ← IOKit + DiskArbitration
    └── LEDRenderer.swift                     ← draws the LED
```

## Limitations / things you might want to add

- Whole disks only (e.g. `disk0`), not individual partitions. The IOKit
  statistics are exposed at the `IOBlockStorageDriver` level which sits above
  the partition map, so this is the natural granularity. Per-volume monitoring
  would need a different data source (e.g. parsing `iostat` or `fs_usage`).
- No separate read/write indication. Easy to add: render two LEDs (green for
  read, red for write) by comparing `bytesRead` and `bytesWritten` deltas
  separately in `StatusController.poll()`.
- Network volumes don't show up — they're not block-storage drivers.

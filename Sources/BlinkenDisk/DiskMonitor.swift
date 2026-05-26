import Foundation
import IOKit
import DiskArbitration

/// A local block-storage device (e.g. disk0, disk2) that we can monitor.
struct DiskInfo: Hashable {
    let bsdName: String      // e.g. "disk0"
    let displayName: String  // e.g. "APPLE SSD AP1024Z (disk0)"
}

/// Cumulative I/O counters read from IOBlockStorageDriver's "Statistics" dict.
/// Activity is detected by comparing successive samples.
struct DiskStats: Equatable {
    let bytesRead: UInt64
    let bytesWritten: UInt64
    let opsRead: UInt64
    let opsWritten: UInt64
}

enum DiskMonitor {

    // MARK: - Enumeration

    /// Returns one entry per local block-storage device (whole disks only — partitions are not
    /// separate IOBlockStorageDrivers, so polling a disk covers all activity on its slices).
    static func enumerate() -> [DiskInfo] {
        var result: [DiskInfo] = []

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            // The whole-disk IOMedia child carries the BSD Name.
            guard let bsd = wholeMediaBSDName(for: service) else {
                continue
            }

            let name = friendlyName(forBSDName: bsd)
            result.append(DiskInfo(bsdName: bsd, displayName: name))
        }

        // Stable ordering so the menu doesn't jump around between rebuilds.
        result.sort { $0.bsdName.localizedStandardCompare($1.bsdName) == .orderedAscending }
        return result
    }

    // MARK: - Stats

    /// Reads current cumulative I/O counters for the given BSD name (e.g. "disk0").
    /// Returns nil if the disk has gone away.
    static func readStats(bsdName: String) -> DiskStats? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            guard wholeMediaBSDName(for: service) == bsdName else {
                continue
            }

            guard let driverDict = copyProperties(service),
                  let stats = driverDict["Statistics"] as? [String: Any] else {
                continue
            }

            let br = uint64(stats["Bytes (Read)"])
            let bw = uint64(stats["Bytes (Write)"])
            let or = uint64(stats["Operations (Read)"])
            let ow = uint64(stats["Operations (Write)"])
            return DiskStats(bytesRead: br, bytesWritten: bw, opsRead: or, opsWritten: ow)
        }
        return nil
    }

    // MARK: - Helpers

    private static func uint64(_ any: Any?) -> UInt64 {
        if let n = any as? NSNumber { return n.uint64Value }
        return 0
    }

    private static func copyProperties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dict
    }

    private static func wholeMediaBSDName(for entry: io_registry_entry_t) -> String? {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(entry, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var child = IOIteratorNext(iterator)
        while child != 0 {
            defer {
                IOObjectRelease(child)
                child = IOIteratorNext(iterator)
            }

            if let dict = copyProperties(child),
               (dict["Whole"] as? Bool) == true,
               let bsd = dict["BSD Name"] as? String,
               !bsd.isEmpty {
                return bsd
            }

            if let bsd = wholeMediaBSDName(for: child) {
                return bsd
            }
        }

        return nil
    }

    /// Build a human-readable name using DiskArbitration: vendor + model, plus volume name
    /// if the disk is mounted with a single obvious volume. Falls back to "/dev/<bsd>".
    private static func friendlyName(forBSDName bsd: String) -> String {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return "/dev/\(bsd)"
        }

        guard let disk = bsd.withCString({ DADiskCreateFromBSDName(kCFAllocatorDefault, session, $0) }),
              let descCF = DADiskCopyDescription(disk),
              let desc = descCF as NSDictionary? as? [String: Any] else {
            return "/dev/\(bsd)"
        }

        let vendor = trimmed(desc[kDADiskDescriptionDeviceVendorKey as String] as? String)
        let model = trimmed(desc[kDADiskDescriptionDeviceModelKey as String] as? String)
        let media = trimmed(desc[kDADiskDescriptionMediaNameKey as String] as? String)
        let volume = trimmed(desc[kDADiskDescriptionVolumeNameKey as String] as? String)

        var parts: [String] = []
        let candidates: [String] = [vendor, model, volume, media]
        for p in candidates where !p.isEmpty {
            if !parts.contains(p) { parts.append(p) }
        }

        if parts.isEmpty {
            return "/dev/\(bsd)"
        }
        return "\(parts.joined(separator: " ")) (\(bsd))"
    }

    private static func trimmed(_ s: String?) -> String {
        return (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

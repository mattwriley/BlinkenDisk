// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BlinkenDisk",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "BlinkenDisk",
            path: "Sources/BlinkenDisk",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit"),
                .linkedFramework("DiskArbitration"),
            ]
        )
    ]
)

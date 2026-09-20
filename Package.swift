// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "net-meter",
    // macOS 26 baseline. The string form is used deliberately — the Makefile reads
    // the deployment target from this line, so it is stated once.
    platforms: [.macOS("26.0")],
    targets: [
        // Pure, testable logic. No AppKit UI in here.
        .target(
            name: "NetMeterCore"
        ),
        // The menu bar app. `resources:` stays empty on purpose: SwiftPM's
        // `Bundle.module` does not look inside an assembled .app bundle.
        .executableTarget(
            name: "NetMeter",
            dependencies: ["NetMeterCore"],
            resources: []
        ),
        .testTarget(
            name: "NetMeterCoreTests",
            dependencies: ["NetMeterCore"]
        ),
    ]
)

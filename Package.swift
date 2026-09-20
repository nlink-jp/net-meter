// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "net-meter",
    // macOS 26 baseline. The string form is used deliberately — the Makefile reads
    // the deployment target from this line, so it is stated once.
    platforms: [.macOS("26.0")],
    targets: [
        // Pure, testable logic. No AppKit UI, no OS calls, no clock.
        .target(
            name: "NetMeterCore"
        ),
        // The thin layer that asks the OS: sysctl counters and, later, the
        // interface information sources. Its tests are live — they read this
        // Mac's real counters.
        .target(
            name: "NetMeterSystem",
            dependencies: ["NetMeterCore"]
        ),
        // Drawing and views. A library rather than part of the executable so that
        // tests can render it offscreen, pixel by pixel, without launching the app.
        .target(
            name: "NetMeterUI",
            dependencies: ["NetMeterCore"]
        ),
        // The menu bar app: wiring only. `resources:` stays empty on purpose —
        // SwiftPM's `Bundle.module` does not look inside an assembled .app bundle.
        .executableTarget(
            name: "NetMeter",
            dependencies: ["NetMeterCore", "NetMeterSystem", "NetMeterUI"],
            resources: []
        ),
        .testTarget(
            name: "NetMeterCoreTests",
            dependencies: ["NetMeterCore"]
        ),
        .testTarget(
            name: "NetMeterSystemTests",
            dependencies: ["NetMeterCore", "NetMeterSystem"]
        ),
        .testTarget(
            name: "NetMeterUITests",
            dependencies: ["NetMeterCore", "NetMeterUI"]
        ),
    ]
)

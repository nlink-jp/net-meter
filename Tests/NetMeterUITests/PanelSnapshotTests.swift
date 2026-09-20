import NetMeterCore
@testable import NetMeterUI
import XCTest

/// What the panel is told, for each way an interface can be there or not.
@MainActor
final class PanelSnapshotTests: XCTestCase {
    private final class Script: CounterSource, @unchecked Sendable {
        var readings: [[String: InterfaceCounters]] = []
        func read() -> [String: InterfaceCounters] { readings.isEmpty ? [:] : readings.removeFirst() }
    }

    private let path = [PathInterface(name: "en0", kind: .wiredEthernet), PathInterface(name: "en1", kind: .wifi)]
    private let info: [String: InterfaceInfo] = [
        "en0": InterfaceInfo(displayName: "Ethernet", addresses: ["192.0.2.10", "2001:db8::10"]),
        "en1": InterfaceInfo(displayName: "Wi-Fi"),
        "en7": InterfaceInfo(displayName: "USB LAN"),
    ]

    private func controller(selection: InterfaceSelection, path: [PathInterface]? = nil) -> (MeterController, () -> Double) {
        let script = Script()
        func reading(_ step: UInt64) -> [String: InterfaceCounters] {
            ["en0": InterfaceCounters(rxBytes: step * 100_000, txBytes: step * 1_000_000, rxPackets: step * 100,
                                      txPackets: step * 100, linkSpeed: 2_500_000_000),
             "utun4": InterfaceCounters(rxBytes: 0, txBytes: 0, rxPackets: 0, txPackets: 0)]
        }
        script.readings = (0...3).map { reading(UInt64($0)) }
        var settings = AppSettings()
        settings.selection = selection
        var time = 0.0
        let order = path ?? self.path
        let controller = MeterController(counters: script, pathOrder: { order }, now: { time },
                                         store: InMemorySettingsStore(settings))
        for step in 0...3 {
            time = Double(step)
            controller.tick()
        }
        return (controller, { time })
    }

    private func snapshot(_ controller: MeterController, now: Double, error: String? = nil) -> PanelSnapshot {
        controller.panelSnapshot(info: info, pathOrder: path, loginItem: .off, loginItemError: error,
                                 version: "v0.1.0-dirty", now: now)
    }

    func testAPresentInterfaceShowsItsNameAddressesSpeedPeaksAndTotals() {
        let (controller, now) = controller(selection: .automatic)
        let panel = snapshot(controller, now: now())
        XCTAssertEqual(panel.heading, "Ethernet (en0)")
        XCTAssertTrue(panel.isAutomatic)
        XCTAssertEqual(panel.reading, .rate(down: 100_000, up: 1_000_000))
        XCTAssertEqual(panel.addresses, ["192.0.2.10", "2001:db8::10"])
        XCTAssertEqual(panel.linkSpeed, "2.5 Gbps")
        XCTAssertEqual(panel.peakUp, 1_000_000)
        XCTAssertEqual(panel.totals, TransferTotals(downBytes: 300_000, upBytes: 3_000_000))
        XCTAssertEqual(panel.points.map(\.offset), [-2, -1, 0])
        XCTAssertEqual(panel.fullScale, 1_000_000)
        XCTAssertEqual(panel.entries.map(\.name), ["en0", "utun4"])
        XCTAssertEqual(panel.version, "v0.1.0-dirty", "verbatim")
    }

    func testAnAbsentManualSelectionIsNamedAndShowsNothingElse() {
        let (controller, now) = controller(selection: .manual("en7"))
        let panel = snapshot(controller, now: now())
        XCTAssertEqual(panel.heading, "USB LAN (en7) — not connected")
        XCTAssertFalse(panel.isAutomatic)
        XCTAssertEqual(panel.reading, .absent)
        XCTAssertTrue(panel.addresses.isEmpty && panel.points.isEmpty)
        XCTAssertEqual(panel.linkSpeed, "—")
        XCTAssertEqual(panel.totals, TransferTotals())
        // The choice is still in the list, marked, so it does not look dropped.
        XCTAssertEqual(panel.entries.last, InterfaceListEntry(name: "en7", label: "USB LAN (en7)", isHardwarePort: true, isAvailable: false))
    }

    func testAutomaticWithNoPhysicalInterfaceSaysSo() {
        let (controller, now) = controller(selection: .automatic, path: [PathInterface(name: "utun4", kind: .other)])
        let panel = snapshot(controller, now: now())
        XCTAssertEqual(panel.heading, UIStrings.noInterface)
        XCTAssertEqual(panel.reading, .absent)
    }

    func testAnErrorFromChangingLaunchAtLoginIsCarriedSeparatelyFromThePolledState() {
        let (controller, now) = controller(selection: .automatic)
        XCTAssertNil(snapshot(controller, now: now()).loginItemError)
        let panel = snapshot(controller, now: now(), error: "Operation not permitted")
        XCTAssertEqual(panel.loginItemError, "Operation not permitted")
        XCTAssertEqual(panel.loginItem, .off)
    }
}

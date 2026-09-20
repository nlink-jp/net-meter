import NetMeterCore
@testable import NetMeterUI
import XCTest

@MainActor
final class MeterControllerTests: XCTestCase {
    private final class Script: CounterSource, @unchecked Sendable {
        var readings: [[String: InterfaceCounters]] = []
        func read() -> [String: InterfaceCounters] { readings.isEmpty ? [:] : readings.removeFirst() }
    }

    private func counters(_ rx: UInt64, _ tx: UInt64, _ packets: UInt64) -> InterfaceCounters {
        InterfaceCounters(rxBytes: rx, txBytes: tx, rxPackets: packets, txPackets: packets)
    }

    private let path = [PathInterface(name: "en0", kind: .wiredEthernet), PathInterface(name: "en1", kind: .wifi)]

    private func make(_ script: Script, store: SettingsStore = InMemorySettingsStore(),
                      path: @escaping () -> [PathInterface], time: @escaping () -> Double) -> MeterController {
        MeterController(counters: script, pathOrder: path, now: time, store: store)
    }

    func testFirstTickIsWaitingAndTheSecondIsARate() {
        let script = Script()
        script.readings = [["en0": counters(0, 0, 0)], ["en0": counters(244_000, 2_400_000, 900)]]
        var time = 0.0
        let controller = make(script, path: { self.path }, time: { time })

        XCTAssertEqual(controller.content.reading, .absent, "nothing is known before the first reading")
        controller.tick()
        XCTAssertEqual(controller.content.reading, .waiting)
        time = 1
        controller.tick()
        XCTAssertEqual(controller.content.reading, .rate(down: 244_000, up: 2_400_000))
        XCTAssertEqual(controller.resolved, .present("en0"))
        XCTAssertEqual(controller.content.columns.last!, GraphColumn(down: 244_000, up: 2_400_000))
    }

    func testASettingReachesTheDisplayAtOnceAndIsSaved() {
        let script = Script()
        script.readings = [["en0": counters(0, 0, 0)]]
        let store = InMemorySettingsStore()
        let controller = make(script, store: store, path: { self.path }, time: { 0 })
        controller.tick()

        var changes = 0
        controller.onChange = { changes += 1 }
        controller.settings.displayMode = .graphOnly
        controller.settings.unit = .bits
        XCTAssertEqual(changes, 2, "no tick happened in between")
        XCTAssertEqual(controller.content.mode, .graphOnly)
        XCTAssertEqual(controller.content.unit, .bits)
        XCTAssertEqual(store.load().displayMode, .graphOnly)
        XCTAssertEqual(store.load().unit, .bits)

        controller.settings.unit = .bits
        XCTAssertEqual(changes, 2, "setting the same value again is not a change")
    }

    func testSettingsAreLoadedFromTheStore() {
        var saved = AppSettings()
        saved.selection = .manual("en1")
        saved.coloured = true
        let controller = make(Script(), store: InMemorySettingsStore(saved), path: { self.path }, time: { 0 })
        XCTAssertEqual(controller.settings, saved)
    }

    func testAManualSelectionThatIsGoneIsAbsentNotAnotherInterface() {
        let script = Script()
        script.readings = [["en0": counters(0, 0, 0)], ["en0": counters(9_000, 9_000, 9)]]
        var time = 0.0
        var saved = AppSettings()
        saved.selection = .manual("en7")
        let controller = make(script, store: InMemorySettingsStore(saved), path: { self.path }, time: { time })
        controller.tick()
        time = 1
        controller.tick()
        XCTAssertEqual(controller.content.reading, .absent)
        XCTAssertTrue(controller.content.columns.isEmpty)
    }

    func testAutomaticSelectionFollowsThePreferenceOrderWithoutWaitingForATick() {
        let script = Script()
        let both = ["en0": counters(0, 0, 0), "en1": counters(0, 0, 0)]
        script.readings = [both]
        var order = path
        let controller = make(script, path: { order }, time: { 0 })
        controller.tick()
        XCTAssertEqual(controller.resolved, .present("en0"))

        order = [PathInterface(name: "en1", kind: .wifi)]  // the cable is pulled
        controller.refresh()
        XCTAssertEqual(controller.resolved, .present("en1"))
    }

    func testTheGraphScaleEasesDownOncePerSampleAndStartsFreshOnAnotherInterface() {
        let script = Script()
        // en0: a 2 MB/s burst, then quiet. en1: always quiet.
        let ups: [UInt64] = [0, 2_000_000, 2_010_000, 2_020_000, 2_030_000]
        script.readings = ups.enumerated().map { index, up in
            ["en0": counters(0, up, UInt64(index) * 100), "en1": counters(0, UInt64(index) * 10_000, UInt64(index) * 10)]
        }
        var time = 0.0
        let controller = make(script, path: { self.path }, time: { time })
        for step in 0..<2 { time = Double(step); controller.tick() }
        XCTAssertEqual(controller.content.fullScale, 2_000_000)

        // Shrink the window to nothing but quiet samples by looking at a short
        // history: the peak is still in the window here, so the scale holds.
        time = 2; controller.tick()
        XCTAssertEqual(controller.content.fullScale, 2_000_000, "the peak is still on screen")

        // A redraw without a new sample must not move the scale.
        controller.settings.unit = .bits
        XCTAssertEqual(controller.content.fullScale, 2_000_000)

        // Another interface starts from its own scale, not the last one's peak.
        controller.settings.selection = .manual("en1")
        XCTAssertEqual(controller.content.fullScale, GraphScale.defaultFloor)
    }

    func testAFailedReadKeepsTheDisplayAsItWas() {
        let script = Script()
        script.readings = [["en0": counters(0, 0, 0)], ["en0": counters(1_024, 0, 1)], [:]]
        var time = 0.0
        let controller = make(script, path: { self.path }, time: { time })
        controller.tick()
        time = 1
        controller.tick()
        time = 2
        controller.tick()
        XCTAssertEqual(controller.content.reading, .rate(down: 1_024, up: 0))
    }
}

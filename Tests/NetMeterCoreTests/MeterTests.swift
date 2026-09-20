import XCTest
@testable import NetMeterCore

final class MeterTests: XCTestCase {
    private func counters(_ rx: UInt64, _ tx: UInt64, _ ip: UInt64, _ op: UInt64) -> InterfaceCounters {
        InterfaceCounters(rxBytes: rx, txBytes: tx, rxPackets: ip, txPackets: op)
    }

    func testFirstReadingIsABaselineThenRatesFollow() {
        var meter = Meter()
        XCTAssertEqual(meter.ingest(["en0": counters(0, 0, 0, 0)], at: 10)["en0"], .baseline)
        let outcome = meter.ingest(["en0": counters(2_048, 1_024, 4, 2)], at: 11)["en0"]
        XCTAssertEqual(outcome, .rate(Rate(downBytesPerSecond: 2_048, upBytesPerSecond: 1_024, downBytes: 2_048, upBytes: 1_024)))
        XCTAssertEqual(meter.latest(for: "en0"), outcome)
    }

    func testRatesUseTheMeasuredIntervalNotAnAssumedSecond() {
        var meter = Meter()
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 0)
        guard case .rate(let rate) = meter.ingest(["en0": counters(4_096, 0, 4, 0)], at: 2)["en0"] else {
            return XCTFail("expected a rate")
        }
        XCTAssertEqual(rate.downBytesPerSecond, 2_048)
    }

    func testASleepIsDiscardedAndMeasuringResumesFromTheNewBaseline() {
        var meter = Meter()
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 0)
        meter.ingest(["en0": counters(1_024, 0, 1, 0)], at: 1)
        XCTAssertEqual(meter.ingest(["en0": counters(9_000_000, 0, 9_000, 0)], at: 301)["en0"], .discarded(.intervalTooLong))
        guard case .rate(let rate) = meter.ingest(["en0": counters(9_002_048, 0, 9_002, 0)], at: 302)["en0"] else {
            return XCTFail("expected a rate after re-baselining")
        }
        XCTAssertEqual(rate.downBytes, 2_048)
        // What moved during the sleep was never measured, so it is not in the totals.
        XCTAssertEqual(meter.totals(for: "en0"), TransferTotals(downBytes: 1_024 + 2_048, upBytes: 0))
    }

    func testTooSoonLeavesBaselineHistoryAndLatestAlone() {
        var meter = Meter()
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 0)
        let first = meter.ingest(["en0": counters(1_024, 0, 1, 0)], at: 1)["en0"]
        XCTAssertEqual(meter.ingest(["en0": counters(2_048, 0, 2, 0)], at: 1.2)["en0"], .tooSoon)
        XCTAssertEqual(meter.latest(for: "en0"), first)
        XCTAssertEqual(meter.history(for: "en0").count, 2)
        // The next reading is measured against the baseline from t=1, not t=1.2.
        guard case .rate(let rate) = meter.ingest(["en0": counters(3_072, 0, 3, 0)], at: 2)["en0"] else {
            return XCTFail("expected a rate")
        }
        XCTAssertEqual(rate.downBytes, 2_048)
    }

    func testAnInterfaceThatVanishesStartsOverWhenItReturns() {
        var meter = Meter()
        meter.ingest(["utun7": counters(5_000_000, 0, 5_000, 0), "en0": counters(0, 0, 0, 0)], at: 0)
        meter.ingest(["utun7": counters(5_001_024, 0, 5_001, 0), "en0": counters(0, 0, 0, 0)], at: 1)
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 2)  // the tunnel is torn down
        XCTAssertNil(meter.latest(for: "utun7"))
        XCTAssertFalse(meter.availableInterfaces.contains("utun7"))
        // Re-created with counters that happen to look like a plausible step: still a baseline.
        XCTAssertEqual(meter.ingest(["utun7": counters(5_002_048, 0, 5_002, 0), "en0": counters(0, 0, 0, 0)], at: 3)["utun7"], .baseline)
    }

    func testAFailedReadChangesNothing() {
        var meter = Meter()
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 0)
        XCTAssertTrue(meter.ingest([:], at: 1).isEmpty)
        XCTAssertTrue(meter.availableInterfaces.contains("en0"))
        guard case .rate = meter.ingest(["en0": counters(2_048, 0, 2, 0)], at: 2)["en0"] else {
            return XCTFail("the baseline must survive a failed read")
        }
    }

    func testHistoryMarksSamplesWithoutAValueAndIsBounded() {
        var meter = Meter(historyCapacity: 3)
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 0)
        meter.ingest(["en0": counters(1_024, 0, 1, 0)], at: 1)
        XCTAssertEqual(meter.history(for: "en0").map { $0.rate == nil }, [true, false])
        for step in 2...5 {
            meter.ingest(["en0": counters(UInt64(step) * 1_024, 0, UInt64(step), 0)], at: Double(step))
        }
        XCTAssertEqual(meter.history(for: "en0").map(\.time), [3, 4, 5])
    }

    func testEveryInterfaceKeepsItsOwnHistorySoSwitchingShowsRealData() {
        var meter = Meter()
        meter.ingest(["en0": counters(0, 0, 0, 0), "en1": counters(0, 0, 0, 0)], at: 0)
        meter.ingest(["en0": counters(1_024, 0, 1, 0), "en1": counters(0, 8_192, 0, 8)], at: 1)
        XCTAssertEqual(meter.totals(for: "en1"), TransferTotals(downBytes: 0, upBytes: 8_192))
        XCTAssertEqual(meter.peak(for: "en1").up, 8_192)
        XCTAssertEqual(meter.peak(for: "en0").down, 1_024)
        XCTAssertEqual(meter.totals(for: "nonexistent"), TransferTotals())
    }

    func testPeakLooksOnlyAtTheRequestedWindow() {
        var meter = Meter()
        meter.ingest(["en0": counters(0, 0, 0, 0)], at: 0)
        meter.ingest(["en0": counters(1_024_000, 0, 1_000, 0)], at: 1)
        meter.ingest(["en0": counters(1_026_048, 0, 1_002, 0)], at: 2)
        XCTAssertEqual(meter.peak(for: "en0").down, 1_024_000)
        XCTAssertEqual(meter.peak(for: "en0", since: 1.5).down, 2_048)
    }
}

final class RingBufferTests: XCTestCase {
    func testKeepsTheNewestElementsOldestFirst() {
        var buffer = RingBuffer<Int>(capacity: 3)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.last)
        for value in 1...2 { buffer.append(value) }
        XCTAssertEqual(buffer.elements, [1, 2])
        XCTAssertEqual(buffer.last, 2)
        for value in 3...7 { buffer.append(value) }
        XCTAssertEqual(buffer.elements, [5, 6, 7])
        XCTAssertEqual(buffer.last, 7)
        XCTAssertEqual(buffer.count, 3)
    }
}

final class GraphScaleTests: XCTestCase {
    func testIdleTrafficDoesNotFillTheGraph() {
        XCTAssertEqual(GraphScale.fullScale(down: [1_024, 2_048], up: [0]), GraphScale.defaultFloor)
        XCTAssertEqual(GraphScale.fraction(of: 2_048, fullScale: GraphScale.defaultFloor), 0.02048, accuracy: 1e-9)
    }

    func testBothDirectionsShareOneScale() {
        let scale = GraphScale.fullScale(down: [300_000], up: [2_400_000])
        XCTAssertEqual(scale, 2_400_000)
        XCTAssertEqual(GraphScale.fraction(of: 300_000, fullScale: scale), 0.125)
        XCTAssertEqual(GraphScale.fraction(of: 2_400_000, fullScale: scale), 1)
    }

    func testEmptyWindowsAndNonsenseAreSafe() {
        XCTAssertEqual(GraphScale.fullScale(down: [], up: []), GraphScale.defaultFloor)
        XCTAssertEqual(GraphScale.fraction(of: .nan, fullScale: 100), 0)
        XCTAssertEqual(GraphScale.fraction(of: 500, fullScale: 100), 1)
        XCTAssertEqual(GraphScale.fraction(of: 5, fullScale: 0), 0)
    }
}

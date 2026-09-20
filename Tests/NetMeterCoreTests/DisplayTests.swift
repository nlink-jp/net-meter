import XCTest
@testable import NetMeterCore

final class DisplayTests: XCTestCase {
    private func rate(_ down: Double, _ up: Double) -> Rate {
        Rate(downBytesPerSecond: down, upBytesPerSecond: up, downBytes: UInt64(down), upBytes: UInt64(up))
    }

    // MARK: settings

    func testDefaults() {
        let settings = AppSettings()
        XCTAssertEqual(settings.selection, .automatic)
        XCTAssertEqual(settings.displayMode, .numbersAndGraph)
        XCTAssertEqual(settings.unit, .bytes)
        XCTAssertFalse(settings.coloured)
    }

    func testSettingsRoundTrip() {
        var settings = AppSettings()
        settings.selection = .manual("en1")
        settings.displayMode = .graphOnly
        settings.unit = .bits
        settings.coloured = true
        XCTAssertEqual(AppSettings(values: settings.values), settings)
        XCTAssertEqual(AppSettings(values: AppSettings().values), AppSettings())
    }

    func testUnknownOrMissingValuesFallBackToDefaults() {
        let settings = AppSettings(values: ["displayMode": "hologram", "unit": "", "coloured": "yes"])
        XCTAssertEqual(settings, AppSettings())
    }

    func testDisplayModeParts() {
        XCTAssertTrue(DisplayMode.numbersAndGraph.showsNumbers && DisplayMode.numbersAndGraph.showsGraph)
        XCTAssertTrue(DisplayMode.numbersOnly.showsNumbers && !DisplayMode.numbersOnly.showsGraph)
        XCTAssertTrue(!DisplayMode.graphOnly.showsNumbers && DisplayMode.graphOnly.showsGraph)
    }

    // MARK: what there is to show

    func testAbsentInterfaceIsAbsentWhateverTheLastOutcomeWas() {
        XCTAssertEqual(meterReading(resolved: .absent, latest: .rate(rate(1, 2))), .absent)
        XCTAssertEqual(meterReading(resolved: .absent, latest: nil), .absent)
    }

    func testNoValueIsWaitingNeverZero() {
        for latest in [SampleOutcome?.none, .baseline, .discarded(.reset), .discarded(.intervalTooLong), .tooSoon] {
            XCTAssertEqual(meterReading(resolved: .present("en0"), latest: latest), .waiting)
        }
    }

    func testARateIsShownAsIs() {
        XCTAssertEqual(meterReading(resolved: .present("en0"), latest: .rate(rate(244_000, 2_400_000))),
                       .rate(down: 244_000, up: 2_400_000))
        XCTAssertEqual(meterReading(resolved: .present("en0"), latest: .rate(rate(0, 0))), .rate(down: 0, up: 0))
    }

    // MARK: graph columns

    private func history(_ rates: [Double?]) -> [HistoryPoint] {
        rates.enumerated().map { index, value in
            // Times are deliberately ragged: the columns must not depend on them.
            HistoryPoint(time: Double(index) * 1.013 + 0.37, rate: value.map { rate($0, $0 * 2) })
        }
    }

    func testOneBarPerSampleNewestOnTheRightPaddedOnTheLeft() {
        let columns = GraphWindow.columns(from: history([5, 7]))
        XCTAssertEqual(columns.count, GraphWindow.columns)
        XCTAssertEqual(Array(columns.suffix(2)), [GraphColumn(down: 5, up: 10), GraphColumn(down: 7, up: 14)])
        XCTAssertTrue(columns.dropLast(2).allSatisfy { $0 == nil })
    }

    func testEverySampleMovesTheGraphLeftByExactlyOneBarAndChangesNothingElse() {
        // What the five-second buckets got wrong: the graph stood still, then
        // jumped, and the newest bar kept changing. Here every frame is the
        // previous one shifted by one, whatever the timer's phase.
        var rates: [Double?] = (1...20).map { Double($0 * 1_000) }
        rates[8] = nil
        var previous: [GraphColumn?]?
        for length in 1...rates.count {
            let frame = GraphWindow.columns(from: history(Array(rates.prefix(length))))
            if let previous {
                XCTAssertEqual(Array(frame.dropLast()), Array(previous.dropFirst()), "frame \(length) is not the last one shifted")
            }
            previous = frame
        }
    }

    func testASampleWithoutAValueIsAGapNotAZero() {
        let columns = GraphWindow.columns(from: history([1, nil, 2]), count: 3)
        XCTAssertEqual(columns, [GraphColumn(down: 1, up: 2), nil, GraphColumn(down: 2, up: 4)])
    }

    func testOnlyTheNewestSamplesAreShown() {
        let columns = GraphWindow.columns(from: history((1...30).map { Double($0) }), count: 4)
        XCTAssertEqual(columns.map { $0?.down }, [27, 28, 29, 30])
        XCTAssertTrue(GraphWindow.columns(from: []).allSatisfy { $0 == nil })
    }

    func testFullScaleIsSharedAndHasAFloor() {
        XCTAssertEqual(GraphWindow.fullScale(of: [nil, GraphColumn(down: 10, up: 20)]), GraphScale.defaultFloor)
        XCTAssertEqual(GraphWindow.fullScale(of: [GraphColumn(down: 300_000, up: 2_400_000), nil]), 2_400_000)
    }

    func testTheScaleGrowsAtOnceAndComesDownGradually() {
        // Growing is immediate: a bar must never be clipped.
        XCTAssertEqual(GraphScale.eased(previous: 100_000, target: 2_000_000), 2_000_000)
        // A peak leaves the window: the scale eases down instead of every bar jumping.
        var scale = 2_000_000.0
        var steps = 0
        while scale > 100_000 {
            let next = GraphScale.eased(previous: scale, target: 100_000)
            XCTAssertLessThan(next, scale)
            XCTAssertGreaterThanOrEqual(next, scale * GraphScale.easing - 1e-6)
            scale = next
            steps += 1
        }
        XCTAssertEqual(scale, 100_000, "it lands on the target exactly, never below it")
        XCTAssertEqual(steps, 14, "about one graph width of samples for a 20:1 drop")
    }
}

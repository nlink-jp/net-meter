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

    func testNewestSampleLandsInTheRightmostColumn() {
        let columns = GraphWindow.columns(from: [HistoryPoint(time: 100, rate: rate(5, 7))], now: 100)
        XCTAssertEqual(columns.count, GraphWindow.columns)
        XCTAssertEqual(columns.last!, GraphColumn(down: 5, up: 7))
        XCTAssertTrue(columns.dropLast().allSatisfy { $0 == nil })
    }

    func testAColumnKeepsTheHighestRateInItsBucket() {
        let history = [HistoryPoint(time: 99.2, rate: rate(10, 1)), HistoryPoint(time: 100, rate: rate(3, 9))]
        XCTAssertEqual(GraphWindow.columns(from: history, now: 100).last!, GraphColumn(down: 10, up: 9))
    }

    func testSamplesWithoutAValueLeaveAGapNotAZero() {
        let history = [
            HistoryPoint(time: 96, rate: rate(1, 1)),
            HistoryPoint(time: 98, rate: nil),
            HistoryPoint(time: 100, rate: rate(2, 2)),
        ]
        let columns = GraphWindow.columns(from: history, now: 100, count: 3, secondsPerColumn: 2)
        XCTAssertEqual(columns, [GraphColumn(down: 1, up: 1), nil, GraphColumn(down: 2, up: 2)])
    }

    func testTheWindowIsAboutAMinute() {
        XCTAssertEqual(Double(GraphWindow.columns) * GraphWindow.secondsPerColumn, 60)
        let edge = HistoryPoint(time: 40.5, rate: rate(3, 3)), outside = HistoryPoint(time: 39.5, rate: rate(9, 9))
        let columns = GraphWindow.columns(from: [outside, edge], now: 100)
        XCTAssertEqual(columns.first!, GraphColumn(down: 3, up: 3))
    }

    func testSamplesOlderThanTheWindowOrFromTheFutureAreIgnored() {
        let history = [HistoryPoint(time: 10, rate: rate(9, 9)), HistoryPoint(time: 101, rate: rate(9, 9))]
        XCTAssertTrue(GraphWindow.columns(from: history, now: 100).allSatisfy { $0 == nil })
    }

    func testFullScaleIsSharedAndHasAFloor() {
        XCTAssertEqual(GraphWindow.fullScale(of: [nil, GraphColumn(down: 10, up: 20)]), GraphScale.defaultFloor)
        XCTAssertEqual(GraphWindow.fullScale(of: [GraphColumn(down: 300_000, up: 2_400_000), nil]), 2_400_000)
    }
}

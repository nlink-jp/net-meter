import XCTest
@testable import NetMeterCore

final class PanelTests: XCTestCase {
    func testByteTotals() {
        XCTAssertEqual(PanelFormat.bytes(0), "0 KB")
        XCTAssertEqual(PanelFormat.bytes(1_024), "1 KB")
        XCTAssertEqual(PanelFormat.bytes(999_400), "999 KB")
        XCTAssertEqual(PanelFormat.bytes(999_500), "1.00 MB")
        XCTAssertEqual(PanelFormat.bytes(12_340_000), "12.3 MB")
        XCTAssertEqual(PanelFormat.bytes(1_756_346_368), "1.76 GB")   // measured total
        XCTAssertEqual(PanelFormat.bytes(1_050_000_000), "1.05 GB")
        XCTAssertEqual(PanelFormat.bytes(250_000_000_000), "250 GB")
        XCTAssertEqual(PanelFormat.bytes(3_400_000_000_000), "3.40 TB")
    }

    func testLinkSpeedsAsMeasured() {
        XCTAssertEqual(PanelFormat.linkSpeed(2_500_000_000), "2.5 Gbps")   // wired
        XCTAssertEqual(PanelFormat.linkSpeed(239_040_000), "239 Mbps")     // Wi-Fi
        XCTAssertEqual(PanelFormat.linkSpeed(100_000_000), "100 Mbps")     // a virtual NIC's claim
        XCTAssertEqual(PanelFormat.linkSpeed(1_000_000_000), "1 Gbps")
        XCTAssertEqual(PanelFormat.linkSpeed(10_000_000_000), "10 Gbps")
    }

    func testAnInterfaceThatReportsNoSpeedIsUnknownNotZero() {
        XCTAssertEqual(PanelFormat.linkSpeed(0), "—")
    }

    func testChartPointsCoverTheWindowAndSkipSecondsWithoutAValue() {
        let rate = Rate(downBytesPerSecond: 5, upBytesPerSecond: 7, downBytes: 5, upBytes: 7)
        let history = [
            HistoryPoint(time: 10, rate: rate),     // older than the window
            HistoryPoint(time: 820, rate: rate),
            HistoryPoint(time: 900, rate: nil),     // discarded sample: a gap
            HistoryPoint(time: 1_000, rate: rate),
            HistoryPoint(time: 1_001, rate: rate),  // from the future
        ]
        let points = PanelHistory.points(from: history, now: 1_000)
        XCTAssertEqual(points, [ChartPoint(offset: -180, down: 5, up: 7), ChartPoint(offset: 0, down: 5, up: 7)])
    }

    func testOnlyAClickElsewhereClosesThePanel() {
        XCTAssertFalse(PopoverClick.statusButton.closesPanel, "the button toggles; closing too would reopen")
        XCTAssertFalse(PopoverClick.insidePanel.closesPanel)
        XCTAssertTrue(PopoverClick.elsewhere.closesPanel)
    }
}

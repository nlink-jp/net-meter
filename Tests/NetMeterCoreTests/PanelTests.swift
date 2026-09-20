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

    // MARK: one click, two handlers

    /// Drives the toggle the way the app does and keeps the panel's state.
    private struct Panel {
        var toggle = PanelToggle()
        var shown = false

        mutating func apply(_ effect: PanelToggle.Effect) {
            switch effect {
            case .open: shown = true
            case .close: shown = false
            case .none: break
            }
        }
        /// A click on the status item as macOS 27 delivers it: the global monitor
        /// first (if one is installed), then — usually — the action.
        mutating func clickItem(actionArrives: Bool = true) {
            if toggle.needsMonitor(panelShown: shown) {
                apply(toggle.globalMouseDown(panelShown: shown, onStatusItem: true))
            }
            if actionArrives { apply(toggle.statusItemAction(panelShown: shown)) }
        }
        mutating func clickElsewhere() {
            if toggle.needsMonitor(panelShown: shown) {
                apply(toggle.globalMouseDown(panelShown: shown, onStatusItem: false))
            }
        }
    }

    func testRapidClicksOnTheItemAlternateOpenAndClosedWithoutSkipping() {
        // The defect reported from real use: at two clicks a second, every other
        // "open" click did nothing.
        var panel = Panel()
        for click in 1...20 {
            panel.clickItem()
            XCTAssertEqual(panel.shown, click % 2 == 1, "after click \(click)")
        }
        XCTAssertFalse(panel.toggle.needsMonitor(panelShown: panel.shown), "nothing is left waiting")
    }

    func testTheClickThatClosesThePanelDoesNotOpenItAgain() {
        var panel = Panel()
        panel.clickItem()
        XCTAssertTrue(panel.shown)
        XCTAssertEqual(panel.toggle.globalMouseDown(panelShown: true, onStatusItem: true), .close)
        XCTAssertEqual(panel.toggle.statusItemAction(panelShown: false), .none, "that click's action is dropped")
        XCTAssertEqual(panel.toggle.statusItemAction(panelShown: false), .open, "the next one is a new click")
    }

    func testAnActionThatNeverComesDoesNotSwallowTheNextClick() {
        var panel = Panel()
        panel.clickItem()
        panel.clickItem(actionArrives: false)   // closes; its action is lost
        XCTAssertFalse(panel.shown)
        XCTAssertTrue(panel.toggle.needsMonitor(panelShown: false), "the monitor stays until another mouse-down voids the note")
        panel.clickItem()
        XCTAssertTrue(panel.shown, "the next click opens the panel")
    }

    func testAClickElsewhereClosesAndTheNextItemClickOpens() {
        var panel = Panel()
        panel.clickItem()
        panel.clickElsewhere()
        XCTAssertFalse(panel.shown)
        XCTAssertFalse(panel.toggle.needsMonitor(panelShown: false))
        panel.clickItem()
        XCTAssertTrue(panel.shown)
    }

    func testWithoutAGlobalMonitorSeeingItemClicksItIsAPlainToggle() {
        // macOS 26, or wherever the item's clicks stay inside the app.
        var toggle = PanelToggle()
        XCTAssertEqual(toggle.statusItemAction(panelShown: false), .open)
        XCTAssertEqual(toggle.statusItemAction(panelShown: true), .close)
        XCTAssertEqual(toggle.statusItemAction(panelShown: false), .open)
    }

    func testOnlyAClickElsewhereClosesThePanel() {
        XCTAssertFalse(PopoverClick.statusButton.closesPanel, "the button toggles; closing too would reopen")
        XCTAssertFalse(PopoverClick.insidePanel.closesPanel)
        XCTAssertTrue(PopoverClick.elsewhere.closesPanel)
    }
}

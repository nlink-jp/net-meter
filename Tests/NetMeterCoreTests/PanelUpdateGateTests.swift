import XCTest
@testable import NetMeterCore

final class PanelUpdateGateTests: XCTestCase {
    func testUpdatesFlowWhenNoMenuIsOpen() {
        var gate = PanelUpdateGate()
        XCTAssertTrue(gate.shouldDeliverUpdate())
        XCTAssertFalse(gate.updatePending)
    }

    func testUpdatesAreHeldWhileAMenuIsOpenAndOneIsDeliveredWhenItCloses() {
        var gate = PanelUpdateGate()
        gate.menuDidBeginTracking()
        XCTAssertFalse(gate.shouldDeliverUpdate())
        XCTAssertFalse(gate.shouldDeliverUpdate(), "a second tick while the menu is still open")
        XCTAssertTrue(gate.menuDidEndTracking(), "one update is owed")
        XCTAssertFalse(gate.updatePending)
        XCTAssertTrue(gate.shouldDeliverUpdate())
    }

    func testAMenuThatOpensAndClosesBetweenTicksOwesNothing() {
        var gate = PanelUpdateGate()
        gate.menuDidBeginTracking()
        XCTAssertFalse(gate.menuDidEndTracking())
    }

    func testASubmenuKeepsTheGateClosedUntilTheOutermostMenuEnds() {
        var gate = PanelUpdateGate()
        gate.menuDidBeginTracking()
        gate.menuDidBeginTracking()
        XCTAssertFalse(gate.shouldDeliverUpdate())
        XCTAssertFalse(gate.menuDidEndTracking())
        XCTAssertFalse(gate.shouldDeliverUpdate(), "the outer menu is still open")
        XCTAssertTrue(gate.menuDidEndTracking())
    }

    func testAnEndWithoutABeginningDoesNotJamTheGate() {
        var gate = PanelUpdateGate()
        XCTAssertFalse(gate.menuDidEndTracking())
        XCTAssertEqual(gate.trackingDepth, 0)
        XCTAssertTrue(gate.shouldDeliverUpdate())
    }

    func testClosingThePanelClearsWhateverWasPending() {
        var gate = PanelUpdateGate()
        gate.menuDidBeginTracking()
        _ = gate.shouldDeliverUpdate()
        gate.reset()
        XCTAssertEqual(gate, PanelUpdateGate())
    }
}

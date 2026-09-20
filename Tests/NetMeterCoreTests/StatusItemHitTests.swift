import CoreGraphics
import XCTest
@testable import NetMeterCore

final class StatusItemHitTests: XCTestCase {
    /// A status item window as measured: the menu bar's full 30 pt, at the top of a 2160 pt screen.
    private let frame = CGRect(x: 2009, y: 2130, width: 68, height: 30)

    func testTheInsideIsOwned() {
        XCTAssertTrue(statusItemOwns(CGPoint(x: 2040, y: 2145), itemWindowFrame: frame))
    }

    func testTheScreensTopRowIsOwnedAndTheFirstRowBelowTheMenuBarIsNot() {
        // A pointer pushed against the top edge reports y == frame.maxY.
        XCTAssertTrue(statusItemOwns(CGPoint(x: 2040, y: frame.maxY), itemWindowFrame: frame))
        XCTAssertFalse(statusItemOwns(CGPoint(x: 2040, y: frame.minY), itemWindowFrame: frame))
        XCTAssertTrue(statusItemOwns(CGPoint(x: 2040, y: frame.minY + 1), itemWindowFrame: frame))
    }

    func testTheLeftColumnIsOwnedAndTheNeighboursFirstColumnIsNot() {
        XCTAssertTrue(statusItemOwns(CGPoint(x: frame.minX, y: 2145), itemWindowFrame: frame))
        XCTAssertFalse(statusItemOwns(CGPoint(x: frame.maxX, y: 2145), itemWindowFrame: frame))
        XCTAssertFalse(statusItemOwns(CGPoint(x: frame.minX - 1, y: 2145), itemWindowFrame: frame))
    }

    func testNoFrameOwnsNothing() {
        XCTAssertFalse(statusItemOwns(CGPoint(x: 1, y: 1), itemWindowFrame: nil))
        XCTAssertFalse(statusItemOwns(CGPoint(x: 1, y: 1), itemWindowFrame: .zero))
        XCTAssertFalse(statusItemOwns(CGPoint(x: 1, y: 1), itemWindowFrame: .null))
    }
}

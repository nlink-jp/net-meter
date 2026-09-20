import CoreGraphics
import XCTest
@testable import NetMeterCore

final class PanelPlacementTests: XCTestCase {
    /// A 3840 x 2160 screen: 30 pt of menu bar at the top, nothing at the bottom.
    private let visible = CGRect(x: 0, y: 0, width: 3840, height: 2130)
    private let size = CGSize(width: 320, height: 500)

    func testHangsBelowTheItemCentredOnIt() {
        let item = CGRect(x: 2000, y: 2134, width: 100, height: 22)
        let frame = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: visible)
        XCTAssertEqual(frame.midX, item.midX)
        XCTAssertEqual(frame.maxY, visible.maxY - PanelPlacement.margin, "the item's bottom edge is the visible frame's top")
        XCTAssertEqual(frame.size, size)
    }

    func testAnItemNearTheRightEdgeKeepsThePanelOnScreen() {
        let item = CGRect(x: 3790, y: 2134, width: 40, height: 22)
        let frame = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: visible)
        XCTAssertEqual(frame.maxX, visible.maxX - PanelPlacement.margin)
        XCTAssertEqual(frame.width, size.width)
    }

    func testAnItemNearTheLeftEdgeKeepsThePanelOnScreen() {
        let item = CGRect(x: 4, y: 2134, width: 40, height: 22)
        XCTAssertEqual(PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: visible).minX, PanelPlacement.margin)
    }

    func testASecondScreenWithAnOffsetOriginIsRespected() {
        let second = CGRect(x: -1920, y: 300, width: 1920, height: 1050)
        let item = CGRect(x: -400, y: 1354, width: 100, height: 22)
        let frame = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: second)
        XCTAssertTrue(second.contains(frame), "\(frame) is outside \(second)")
        XCTAssertEqual(frame.midX, item.midX)
    }

    func testAPanelTallerThanTheScreenIsReducedNotPushedOffIt() {
        let small = CGRect(x: 0, y: 0, width: 1280, height: 420)
        let item = CGRect(x: 600, y: 424, width: 100, height: 22)
        let frame = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: small)
        XCTAssertTrue(small.contains(frame))
        XCTAssertEqual(frame.height, small.height - PanelPlacement.margin * 2)
    }

    func testTheTopEdgeStaysPutWhenOnlyTheHeightChanges() {
        // The panel grows a line (a note appears): it must grow downwards, not jump.
        let item = CGRect(x: 2000, y: 2134, width: 100, height: 22)
        let a = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: visible)
        let b = PanelPlacement.frame(itemFrame: item, panelSize: CGSize(width: 320, height: 520), visibleFrame: visible)
        XCTAssertEqual(a.maxY, b.maxY)
        XCTAssertEqual(a.minX, b.minX)
    }

    func testAFractionalHeightNeitherMovesTheTopEdgeNorClipsTheContent() {
        let item = CGRect(x: 2000, y: 2134, width: 100, height: 22)
        let whole = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: visible)
        let fractional = PanelPlacement.frame(itemFrame: item, panelSize: CGSize(width: 320, height: 520.5), visibleFrame: visible)
        XCTAssertEqual(fractional.maxY, whole.maxY, "rounding the origin instead of the top edge moved it by half a point")
        XCTAssertEqual(fractional.height, 521)
        XCTAssertEqual(fractional.minY, fractional.minY.rounded())
    }

    func testAnItemOnAScreenWithoutAMenuBarGapStillHangsBelowIt() {
        // A notched display reports a visible frame that ends below the item's bottom edge.
        let item = CGRect(x: 1000, y: 1080, width: 100, height: 37)
        let notched = CGRect(x: 0, y: 0, width: 1728, height: 1070)
        let frame = PanelPlacement.frame(itemFrame: item, panelSize: size, visibleFrame: notched)
        XCTAssertEqual(frame.maxY, notched.maxY - PanelPlacement.margin)
    }
}

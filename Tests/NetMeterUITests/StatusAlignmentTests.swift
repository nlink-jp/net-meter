import AppKit
import NetMeterCore
@testable import NetMeterUI
import XCTest

/// The arrow and the digits of a row have to look centred on each other. "Looks
/// centred" is measured: the vertical middle of each one's ink.
@MainActor
final class StatusAlignmentTests: XCTestCase {
    /// Vertical ink extent (in points, from the bottom) within an x range and a row.
    private func inkCentre(_ rep: NSBitmapImageRep, scale: CGFloat, x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> (centre: CGFloat, height: CGFloat)? {
        var rows: [Int] = []
        for py in Int(y.lowerBound * scale)..<Int(y.upperBound * scale) {
            let row = rep.pixelsHigh - 1 - py
            for px in Int(x.lowerBound * scale)..<Int(x.upperBound * scale) {
                let alpha = (rep.bitmapData! + row * rep.bytesPerRow + px * 4)[3]
                if alpha > 96 { rows.append(py); break }   // ignore faint antialiasing fringes
            }
        }
        guard let low = rows.min(), let high = rows.max() else { return nil }
        return (CGFloat(low + high + 1) / 2 / scale, CGFloat(high - low + 1) / scale)
    }

    func testArrowsAreVerticallyCentredOnTheDigits() throws {
        let content = StatusContent(reading: .rate(down: 888_000, up: 888_000), columns: [], mode: .numbersOnly, unit: .bytes)
        let arrowX = StatusRenderer.padding...(StatusRenderer.padding + StatusRenderer.arrowWidth)
        let digitsX = (StatusRenderer.padding + StatusRenderer.arrowWidth)...(StatusRenderer.padding + StatusRenderer.arrowWidth + StatusRenderer.numberFieldWidth())
        let half = StatusRenderer.height / 2
        for scale in [CGFloat(1), 2] {
            let rep = StatusRenderer.bitmap(content: content, finish: .template, scale: scale)
            for (name, row) in [("down", 0...half), ("up", half...StatusRenderer.height)] {
                let arrow = try XCTUnwrap(inkCentre(rep, scale: scale, x: arrowX, y: row))
                let digits = try XCTUnwrap(inkCentre(rep, scale: scale, x: digitsX, y: row))
                print(String(format: "scale %.0fx %@ row: arrow centre %.2f (height %.1f), digits centre %.2f (height %.1f), offset %+.2f pt",
                             scale, name, arrow.centre, arrow.height, digits.centre, digits.height, arrow.centre - digits.centre))
                XCTAssertEqual(arrow.centre, digits.centre, accuracy: 0.5, "\(name) row at \(scale)x")
            }
        }
    }
}

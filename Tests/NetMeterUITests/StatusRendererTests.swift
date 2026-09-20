import AppKit
import NetMeterCore
@testable import NetMeterUI
import XCTest

/// Offscreen, pixel by pixel: nothing is launched and nothing appears on screen.
@MainActor
final class StatusRendererTests: XCTestCase {
    /// Premultiplied RGBA, addressed in points from the bottom-left like the drawing code.
    private struct Pixels {
        let rep: NSBitmapImageRep
        let scale: CGFloat
        var wide: Int { rep.pixelsWide }
        var high: Int { rep.pixelsHigh }

        func rgba(_ px: Int, _ pyFromBottom: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            let row = high - 1 - pyFromBottom
            let p = rep.bitmapData! + row * rep.bytesPerRow + px * 4
            return (Int(p[0]), Int(p[1]), Int(p[2]), Int(p[3]))
        }

        /// Inked pixels within a rectangle given in points.
        func ink(x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) -> [(x: Int, y: Int, r: Int, g: Int, b: Int, a: Int)] {
            var found: [(Int, Int, Int, Int, Int, Int)] = []
            let xs = max(0, Int(x.lowerBound * scale))..<min(wide, Int(x.upperBound * scale))
            let ys = max(0, Int(y.lowerBound * scale))..<min(high, Int(y.upperBound * scale))
            for py in ys { for px in xs {
                let c = rgba(px, py)
                if c.a > 0 { found.append((px, py, c.r, c.g, c.b, c.a)) }
            } }
            return found
        }
    }

    private func render(_ reading: MeterReading, columns: [GraphColumn?] = [], mode: DisplayMode = .numbersAndGraph,
                        unit: RateUnit = .bytes, finish: StatusFinish = .template, scale: CGFloat = 2) -> Pixels {
        let padded = [GraphColumn?](repeating: nil, count: max(0, GraphWindow.columns - columns.count)) + columns
        let content = StatusContent(reading: reading, columns: padded, mode: mode, unit: unit)
        return Pixels(rep: StatusRenderer.bitmap(content: content, finish: finish, scale: scale), scale: scale)
    }

    private func graphX(mode: DisplayMode = .numbersAndGraph, unit: RateUnit = .bytes) -> ClosedRange<CGFloat> {
        let right = StatusRenderer.size(mode: mode, unit: unit).width - StatusRenderer.padding
        return (right - StatusRenderer.graphWidth)...right
    }

    private let centre = StatusRenderer.height / 2
    private let everyHeight: ClosedRange<CGFloat> = 0...StatusRenderer.height

    // MARK: the width never depends on the values

    func testWidthDependsOnTheModeAndUnitSystemOnly() {
        let readings: [MeterReading] = [.absent, .waiting, .rate(down: 0, up: 0), .rate(down: 244_000, up: 2_400_000),
                                        .rate(down: 999_400, up: 999_500_000), .rate(down: 1e13, up: 1e13)]
        for mode in DisplayMode.allCases { for unit in RateUnit.allCases {
            let widths = Set(readings.map { render($0, mode: mode, unit: unit).wide })
            XCTAssertEqual(widths.count, 1, "\(mode) \(unit): widths \(widths)")
        } }
    }

    func testEachDisplayModeHasItsOwnWidth() {
        let both = StatusRenderer.size(mode: .numbersAndGraph, unit: .bytes).width
        let numbers = StatusRenderer.size(mode: .numbersOnly, unit: .bytes).width
        let graph = StatusRenderer.size(mode: .graphOnly, unit: .bytes).width
        XCTAssertEqual(graph, StatusRenderer.graphWidth + StatusRenderer.padding * 2)
        XCTAssertGreaterThan(numbers, graph)
        XCTAssertEqual(both, numbers + StatusRenderer.textGraphGap + StatusRenderer.graphWidth)
        XCTAssertLessThan(both, 110, "the item has to stay narrow enough for a notched menu bar")
    }

    func testPixelSizeFollowsTheDisplayScale() {
        let size = StatusRenderer.size(mode: .numbersAndGraph, unit: .bytes)
        for scale in [CGFloat(1), 2] {
            let pixels = render(.rate(down: 1, up: 1), scale: scale)
            XCTAssertEqual(pixels.wide, Int(size.width * scale))
            XCTAssertEqual(pixels.high, Int(StatusRenderer.height * scale))
        }
    }

    // MARK: the two finishes

    func testTemplateFinishDrawsNoColourAtAll() {
        let columns = [GraphColumn(down: 50_000, up: 90_000), GraphColumn(down: 10_000, up: 0)]
        let pixels = render(.rate(down: 244_000, up: 2_400_000), columns: columns, finish: .template)
        let ink = pixels.ink(x: 0...500, y: everyHeight)
        XCTAssertFalse(ink.isEmpty)
        XCTAssertTrue(ink.allSatisfy { $0.r == 0 && $0.g == 0 && $0.b == 0 }, "a template image is black with alpha only")
    }

    func testImageIsMarkedAsATemplateOnlyInTheTemplateFinish() {
        let content = StatusContent(reading: .waiting, columns: [], mode: .numbersOnly, unit: .bytes)
        XCTAssertTrue(StatusRenderer.image(content: content, finish: .template, scale: 1).isTemplate)
        XCTAssertFalse(StatusRenderer.image(content: content, finish: .coloured(darkMenuBar: true), scale: 1).isTemplate)
    }

    func testColouredForegroundFollowsTheMenuBar() {
        let dark = render(.rate(down: 244_000, up: 244_000), mode: .numbersOnly, finish: .coloured(darkMenuBar: true))
        let light = render(.rate(down: 244_000, up: 244_000), mode: .numbersOnly, finish: .coloured(darkMenuBar: false))
        // The unit label is drawn in the foreground colour: light on a dark bar, dark on a light one.
        let unitX = (StatusRenderer.padding + StatusRenderer.arrowWidth + StatusRenderer.numberFieldWidth() + StatusRenderer.numberUnitGap)...500
        let brightest = { (p: Pixels) in p.ink(x: unitX, y: self.everyHeight).map { $0.r + $0.g + $0.b }.max() ?? 0 }
        XCTAssertGreaterThan(brightest(dark), 600)
        XCTAssertLessThan(brightest(light), 60)
    }

    // MARK: the graph

    func testUpstreamIsDrawnAboveTheCentreAndDownstreamBelow() {
        let upOnly = render(.rate(down: 0, up: 1), columns: [GraphColumn(down: 0, up: 500_000)], finish: .coloured(darkMenuBar: true))
        XCTAssertFalse(upOnly.ink(x: graphX(), y: centre...StatusRenderer.height).isEmpty)
        XCTAssertTrue(upOnly.ink(x: graphX(), y: 0...(centre - 1)).isEmpty, "nothing below the centre line")
        XCTAssertTrue(upOnly.ink(x: graphX(), y: centre...StatusRenderer.height).allSatisfy { $0.r > $0.g }, "upstream colour")

        let downOnly = render(.rate(down: 1, up: 0), columns: [GraphColumn(down: 500_000, up: 0)], finish: .coloured(darkMenuBar: true))
        XCTAssertTrue(downOnly.ink(x: graphX(), y: centre...StatusRenderer.height).isEmpty, "nothing above the centre line")
        let below = downOnly.ink(x: graphX(), y: 0...(centre - 1))
        XCTAssertFalse(below.isEmpty)
        XCTAssertTrue(below.allSatisfy { $0.g > $0.r }, "downstream colour")
    }

    func testBarsStayInsideTheItem() {
        let pixels = render(.rate(down: 1, up: 1), columns: [GraphColumn(down: 9e9, up: 9e9)])
        let bars = pixels.ink(x: graphX(), y: everyHeight).map(\.y)
        XCTAssertGreaterThanOrEqual(bars.min()!, Int((centre - 1 - StatusRenderer.maximumBar) * 2) - 1)
        XCTAssertLessThan(bars.max()!, Int((centre + StatusRenderer.maximumBar) * 2) + 1)
    }

    func testAnyTrafficShowsAsAtLeastOnePixel() {
        // One busy column sets the scale; the trickle next to it must not vanish.
        let columns = [GraphColumn(down: 1, up: 0), GraphColumn(down: 0, up: 900_000_000)]
        let pixels = render(.rate(down: 1, up: 1), columns: columns, scale: 1)
        let trickleColumn = (graphX().upperBound - 2)...(graphX().upperBound - 1)
        XCTAssertFalse(pixels.ink(x: trickleColumn, y: 0...(centre - 1)).isEmpty)
    }

    func testAColumnWithoutAValueIsAGapNotAZero() {
        let columns: [GraphColumn?] = [GraphColumn(down: 80_000, up: 80_000), nil, GraphColumn(down: 80_000, up: 80_000)]
        let pixels = render(.rate(down: 1, up: 1), columns: columns, scale: 1)
        let gap = (graphX().upperBound - 2)...(graphX().upperBound - 1)
        let rows = Set(pixels.ink(x: gap, y: everyHeight).map(\.y))
        XCTAssertEqual(rows.count, 1, "only the centre line crosses a gap; got rows \(rows.sorted())")
    }

    // MARK: states without a value

    func testWaitingShowsADashAndNoUnitSoItCannotBeReadAsZero() {
        let waiting = render(.waiting, mode: .numbersOnly)
        let zero = render(.rate(down: 0, up: 0), mode: .numbersOnly)
        let unitX = (StatusRenderer.padding + StatusRenderer.arrowWidth + StatusRenderer.numberFieldWidth() + StatusRenderer.numberUnitGap)...500
        XCTAssertTrue(waiting.ink(x: unitX, y: everyHeight).isEmpty)
        XCTAssertFalse(zero.ink(x: unitX, y: everyHeight).isEmpty)
    }

    func testAbsentIsDimmedAndDrawsNoBars() {
        let columns = [GraphColumn(down: 80_000, up: 80_000)]
        let absent = render(.absent, columns: columns)
        let present = render(.rate(down: 1, up: 1), columns: columns)
        let strongest = { (p: Pixels) in p.ink(x: 0...500, y: self.everyHeight).map(\.a).max() ?? 0 }
        XCTAssertLessThanOrEqual(strongest(absent), Int(255 * StatusRenderer.absentDimming) + 2)
        XCTAssertGreaterThan(strongest(present), 200)
        XCTAssertEqual(Set(absent.ink(x: graphX(), y: everyHeight).map(\.y)).count, 1, "the centre line only: one device pixel at any scale")
    }

    func testNumbersAreRightAligned() {
        let numberX = (StatusRenderer.padding + StatusRenderer.arrowWidth)...(StatusRenderer.padding + StatusRenderer.arrowWidth + StatusRenderer.numberFieldWidth())
        let top = (centre + 0.5)...StatusRenderer.height
        let short = render(.rate(down: 0, up: 2_400_000), mode: .numbersOnly)   // "2.4"
        let long = render(.rate(down: 0, up: 244_000), mode: .numbersOnly)      // "244"
        XCTAssertEqual(short.ink(x: numberX, y: top).map(\.x).max(), long.ink(x: numberX, y: top).map(\.x).max())
        XCTAssertGreaterThan(short.ink(x: numberX, y: top).map(\.x).min()!, long.ink(x: numberX, y: top).map(\.x).min()!)
    }
}

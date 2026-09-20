import AppKit
import NetMeterCore

/// Everything the menu bar item shows at one moment.
public struct StatusContent: Equatable, Sendable {
    public var reading: MeterReading
    /// Oldest first; nil where there was no value.
    public var columns: [GraphColumn?]
    /// The rate drawn at full height.
    public var fullScale: Double
    public var mode: DisplayMode
    public var unit: RateUnit

    /// - Parameter fullScale: nil takes the scale the columns call for, unsmoothed.
    public init(reading: MeterReading, columns: [GraphColumn?], fullScale: Double? = nil, mode: DisplayMode, unit: RateUnit) {
        self.reading = reading
        self.columns = columns
        self.fullScale = fullScale ?? GraphWindow.fullScale(of: columns)
        self.mode = mode
        self.unit = unit
    }
}

/// How the image is finished (ADR-0002).
public enum StatusFinish: Equatable, Sendable {
    /// Drawn in black with alpha and marked as a template: the OS picks the colour.
    case template
    /// Colours baked in; the foreground follows the menu bar the button reports.
    case coloured(darkMenuBar: Bool)
}

/// ADR-0002: one pure function from "values to show + finish" to an image for
/// `NSStatusItem.button.image`. The width depends on the display mode alone —
/// never on the values, and not on the unit either — so neighbouring items move
/// only when the user changes what the item shows.
@MainActor
public enum StatusRenderer {
    public static let height: CGFloat = 22
    static let fontSize: CGFloat = 9
    static let padding: CGFloat = 2
    static let arrowWidth: CGFloat = 8
    static let numberUnitGap: CGFloat = 2
    static let textGraphGap: CGFloat = 4
    /// Bars of `barWidth` with `barGap` between them; whole points, so a bar is
    /// whole pixels at any scale.
    static let barWidth: CGFloat = 2
    static let barGap: CGFloat = 1
    static let graphWidth = CGFloat(GraphWindow.columns) * (barWidth + barGap) - barGap
    /// Room a bar has on either side of the centre line.
    static let maximumBar: CGFloat = 8
    static let absentDimming: CGFloat = 0.35

    static var font: NSFont { .monospacedDigitSystemFont(ofSize: fontSize, weight: .medium) }

    // MARK: layout

    static func width(of text: String) -> CGFloat {
        ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width)
    }

    static func numberFieldWidth() -> CGFloat {
        width(of: String(repeating: "9", count: RateFormatter.numberWidth))
    }

    /// Room for the widest unit label of either unit system, so that switching
    /// between bytes and bits does not move the neighbouring items.
    static func unitFieldWidth() -> CGFloat {
        RateUnit.allCases.flatMap(RateFormatter.units(for:)).map(width(of:)).max() ?? 0
    }

    static func textBlockWidth() -> CGFloat {
        arrowWidth + numberFieldWidth() + numberUnitGap + unitFieldWidth()
    }

    /// The size of the image, in points, for a display mode.
    public static func size(mode: DisplayMode) -> NSSize {
        var width = padding * 2
        if mode.showsNumbers { width += textBlockWidth() }
        if mode.showsNumbers && mode.showsGraph { width += textGraphGap }
        if mode.showsGraph { width += graphWidth }
        return NSSize(width: ceil(width), height: height)
    }

    // MARK: drawing

    /// The image carries a 1x and a 2x representation, each drawn pixel-aligned
    /// for its own scale, and AppKit picks per screen. With a single
    /// representation, a Mac with one Retina and one 1x display would show an
    /// interpolated — blurred — item on one of them.
    public static func image(content: StatusContent, finish: StatusFinish) -> NSImage {
        let image = NSImage(size: size(mode: content.mode))
        for scale in [CGFloat(1), 2] {
            image.addRepresentation(bitmap(content: content, finish: finish, scale: scale))
        }
        image.isTemplate = finish == .template
        return image
    }

    /// The pixels themselves; `image` wraps this. Tests read it directly.
    public static func bitmap(content: StatusContent, finish: StatusFinish, scale: CGFloat) -> NSBitmapImageRep {
        let scale = max(1, scale.rounded())
        let size = size(mode: content.mode)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        bitmap.size = size

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

        let palette = Palette(finish: finish, dimmed: content.reading == .absent)
        var x = padding
        if content.mode.showsNumbers {
            drawNumbers(content, at: x, palette: palette)
            x += textBlockWidth() + textGraphGap
        }
        if content.mode.showsGraph {
            drawGraph(content, at: x, scale: scale, palette: palette)
        }
        return bitmap
    }

    private static func drawNumbers(_ content: StatusContent, at x: CGFloat, palette: Palette) {
        let rowHeight = height / 2
        let rows: [(arrow: String, value: Double?, colour: NSColor, bottom: CGFloat)]
        switch content.reading {
        case .rate(let down, let up):
            rows = [("↑", up, palette.up, rowHeight), ("↓", down, palette.down, 0)]
        case .waiting, .absent:
            rows = [("↑", nil, palette.up, rowHeight), ("↓", nil, palette.down, 0)]
        }
        let numberRight = x + arrowWidth + numberFieldWidth()
        for row in rows {
            drawArrow(up: row.arrow == "↑", colour: row.colour, leftAt: x, rowBottom: row.bottom)
            if let value = row.value {
                let formatted = RateFormatter.format(bytesPerSecond: value, unit: content.unit)
                draw(formatted.number, colour: palette.foreground, rightAt: numberRight, rowBottom: row.bottom)
                draw(formatted.unit, colour: palette.foreground, leftAt: numberRight + numberUnitGap, rowBottom: row.bottom)
            } else {
                // No value is not zero: a dash, and no unit to suggest a magnitude.
                draw(RateFormatter.noValue, colour: palette.foreground, rightAt: numberRight, rowBottom: row.bottom)
            }
        }
    }

    private static func draw(_ text: String, colour: NSColor, leftAt x: CGFloat, rowBottom: CGFloat) {
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: colour])
        let lineHeight = string.size().height
        string.draw(at: NSPoint(x: x, y: rowBottom + ((height / 2 - lineHeight) / 2).rounded()))
    }

    /// A filled arrow — a triangular head on a two-point stem — rather than the
    /// font's glyph, which is a hairline at 9 pt. Every coordinate is a whole
    /// point, so the stem is crisp at 1x.
    private static func drawArrow(up: Bool, colour: NSColor, leftAt x: CGFloat, rowBottom: CGFloat) {
        let centre = x + 3, bottom = rowBottom + 2, top = rowBottom + 10
        let path = NSBezierPath()
        if up {
            path.move(to: NSPoint(x: centre, y: top))
            path.line(to: NSPoint(x: centre + 3, y: top - 4))
            path.line(to: NSPoint(x: centre + 1, y: top - 4))
            path.line(to: NSPoint(x: centre + 1, y: bottom))
            path.line(to: NSPoint(x: centre - 1, y: bottom))
            path.line(to: NSPoint(x: centre - 1, y: top - 4))
            path.line(to: NSPoint(x: centre - 3, y: top - 4))
        } else {
            path.move(to: NSPoint(x: centre, y: bottom))
            path.line(to: NSPoint(x: centre + 3, y: bottom + 4))
            path.line(to: NSPoint(x: centre + 1, y: bottom + 4))
            path.line(to: NSPoint(x: centre + 1, y: top))
            path.line(to: NSPoint(x: centre - 1, y: top))
            path.line(to: NSPoint(x: centre - 1, y: bottom + 4))
            path.line(to: NSPoint(x: centre - 3, y: bottom + 4))
        }
        path.close()
        colour.setFill()
        path.fill()
    }

    private static func draw(_ text: String, colour: NSColor, rightAt x: CGFloat, rowBottom: CGFloat) {
        draw(text, colour: colour, leftAt: x - width(of: text), rowBottom: rowBottom)
    }

    private static func drawGraph(_ content: StatusContent, at x: CGFloat, scale: CGFloat, palette: Palette) {
        let pixel = 1 / scale
        let centre = (height / 2 * scale).rounded() / scale
        // The centre line takes the pixel row just below `centre`.
        palette.baseline.setFill()
        NSRect(x: x, y: centre - pixel, width: graphWidth, height: pixel).fill()

        guard content.reading != .absent else { return }
        let fullScale = content.fullScale

        func barHeight(_ value: Double) -> CGFloat {
            guard value > 0 else { return 0 }
            let exact = CGFloat(GraphScale.fraction(of: value, fullScale: fullScale)) * maximumBar
            // Any traffic at all shows as at least one pixel.
            return max(pixel, (exact * scale).rounded() / scale)
        }

        for (index, column) in content.columns.enumerated() {
            guard let column else { continue }
            let left = x + barOffset(index)
            let up = barHeight(column.up), down = barHeight(column.down)
            if up > 0 {
                palette.up.setFill()
                NSRect(x: left, y: centre, width: barWidth, height: up).fill()
            }
            if down > 0 {
                palette.down.setFill()
                NSRect(x: left, y: centre - pixel - down, width: barWidth, height: down).fill()
            }
        }
    }

    /// Where bar `index` starts, from the graph's left edge.
    static func barOffset(_ index: Int) -> CGFloat {
        CGFloat(index) * (barWidth + barGap)
    }

    /// The colours of one finish. In the template finish everything is black and
    /// only the alpha differs; the OS supplies the colour.
    @MainActor
    struct Palette {
        var foreground: NSColor
        var up: NSColor
        var down: NSColor
        var baseline: NSColor

        init(finish: StatusFinish, dimmed: Bool) {
            let factor: CGFloat = dimmed ? StatusRenderer.absentDimming : 1
            switch finish {
            case .template:
                foreground = NSColor(deviceWhite: 0, alpha: 1 * factor)
                up = foreground
                down = foreground
                baseline = NSColor(deviceWhite: 0, alpha: 0.35 * factor)
            case .coloured(let dark):
                foreground = NSColor(deviceWhite: dark ? 1 : 0, alpha: (dark ? 0.92 : 0.85) * factor)
                up = dark
                    ? NSColor(deviceRed: 1.00, green: 0.42, blue: 0.42, alpha: factor)
                    : NSColor(deviceRed: 0.85, green: 0.21, blue: 0.21, alpha: factor)
                down = dark
                    ? NSColor(deviceRed: 0.37, green: 0.83, blue: 0.55, alpha: factor)
                    : NSColor(deviceRed: 0.12, green: 0.62, blue: 0.33, alpha: factor)
                baseline = NSColor(deviceWhite: dark ? 1 : 0, alpha: 0.35 * factor)
            }
        }
    }
}

import AppKit

// Renders the net-meter app icon (1024x1024 PNG): a dark rounded-rect plate with
// the menu bar graph on it — upstream bars rising from a centre line, downstream
// bars hanging below it — in the two colours the panel uses.
// Run: swift scripts/gen-icon.swift [out.png]

let size = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/AppIcon-1024.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!

let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

let S = CGFloat(size)

// Rounded-rect plate (macOS squircle proportions).
let inset: CGFloat = 96
let plate = CGRect(x: inset, y: inset, width: S - 2 * inset, height: S - 2 * inset)
let radius = plate.width * 0.2237
let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)

cg.saveGState()
cg.addPath(platePath)
cg.clip()
let bgColors = [
    NSColor(srgbRed: 0.16, green: 0.18, blue: 0.22, alpha: 1).cgColor,
    NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1).cgColor,
] as CFArray
let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors, locations: [0, 1])!
cg.drawLinearGradient(bg, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// The graph: bars either side of a centre line.
let up = NSColor(srgbRed: 1.00, green: 0.45, blue: 0.43, alpha: 1).cgColor
let down = NSColor(srgbRed: 0.35, green: 0.85, blue: 0.56, alpha: 1).cgColor
let graph = plate.insetBy(dx: 132, dy: 0)
let centreY = S / 2
let count = 9
let gap: CGFloat = 22
let barWidth = (graph.width - gap * CGFloat(count - 1)) / CGFloat(count)
let upHeights: [CGFloat] = [0.30, 0.52, 0.78, 0.95, 0.70, 0.46, 0.62, 0.86, 0.58]
let downHeights: [CGFloat] = [0.55, 0.40, 0.26, 0.34, 0.60, 0.82, 0.66, 0.38, 0.28]
let maxBar: CGFloat = 250
let lineHalf: CGFloat = 7

for index in 0..<count {
    let x = graph.minX + CGFloat(index) * (barWidth + gap)
    let upRect = CGRect(x: x, y: centreY + lineHalf + 10, width: barWidth, height: upHeights[index] * maxBar)
    let downHeight = downHeights[index] * maxBar
    let downRect = CGRect(x: x, y: centreY - lineHalf - 10 - downHeight, width: barWidth, height: downHeight)
    cg.setFillColor(up)
    cg.addPath(CGPath(roundedRect: upRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
    cg.fillPath()
    cg.setFillColor(down)
    cg.addPath(CGPath(roundedRect: downRect, cornerWidth: 12, cornerHeight: 12, transform: nil))
    cg.fillPath()
}

cg.setFillColor(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55).cgColor)
cg.fill(CGRect(x: graph.minX - 24, y: centreY - lineHalf, width: graph.width + 48, height: lineHalf * 2))
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()

let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")

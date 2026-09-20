import AppKit
import NetMeterCore
@testable import NetMeterUI
import XCTest

/// Writes a sheet of what the menu bar item looks like, for a person to look at.
/// Opt-in, because it produces a file rather than a verdict:
///
///     NET_METER_PREVIEW_DIR=/some/dir swift test --filter StatusPreviewTests
///
/// Every state × finish × display mode is drawn at the real size on a dark and a
/// light strip, then magnified with nearest-neighbour sampling so single pixels
/// stay visible.
@MainActor
final class StatusPreviewTests: XCTestCase {
    func testWritePreviewSheet() throws {
        guard let directory = ProcessInfo.processInfo.environment["NET_METER_PREVIEW_DIR"] else {
            throw XCTSkip("set NET_METER_PREVIEW_DIR to write the preview sheet")
        }
        var columns: [GraphColumn?] = (0..<GraphWindow.columns).map { index in
            let phase = Double(index) / 2
            return GraphColumn(down: 300_000 * abs(sin(phase)) + 20_000, up: 2_400_000 * abs(cos(phase * 0.7)))
        }
        columns[GraphWindow.columns / 3] = nil

        let readings: [(String, MeterReading)] = [
            ("rate", .rate(down: 244_000, up: 2_400_000)),
            ("idle", .rate(down: 0, up: 1_024)),
            ("fast", .rate(down: 288_226_304, up: 999_400)),
            ("waiting", .waiting),
            ("absent", .absent),
        ]
        let finishes: [(StatusFinish, NSColor)] = [
            (.template, NSColor(deviceWhite: 0.12, alpha: 1)),          // tinted white below, as the OS would on a dark bar
            (.coloured(darkMenuBar: true), NSColor(deviceWhite: 0.12, alpha: 1)),
            (.coloured(darkMenuBar: false), NSColor(deviceWhite: 0.93, alpha: 1)),
        ]

        for scale in [CGFloat(1), 2] {
            let cellWidth = StatusRenderer.size(mode: .numbersAndGraph, unit: .bytes).width + 8
            let cellHeight = StatusRenderer.height + 6
            let sheetSize = NSSize(width: cellWidth * CGFloat(finishes.count * DisplayMode.allCases.count),
                                   height: cellHeight * CGFloat(readings.count))
            let sheet = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(sheetSize.width * scale), pixelsHigh: Int(sheetSize.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            sheet.size = sheetSize
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheet)
            NSGraphicsContext.current?.imageInterpolation = .none

            for (row, reading) in readings.enumerated() {
                var column = 0
                for (finish, background) in finishes {
                    for mode in DisplayMode.allCases {
                        let origin = NSPoint(x: CGFloat(column) * cellWidth, y: sheetSize.height - CGFloat(row + 1) * cellHeight)
                        background.setFill()
                        NSRect(origin: origin, size: NSSize(width: cellWidth, height: cellHeight)).fill()
                        let content = StatusContent(reading: reading.1, columns: columns, mode: mode, unit: .bytes)
                        var image = StatusRenderer.image(content: content, finish: finish, scale: scale)
                        if finish == .template { image = Self.tinted(image, NSColor(deviceWhite: 1, alpha: 0.9)) }
                        image.draw(at: NSPoint(x: origin.x + 4, y: origin.y + 3), from: .zero, operation: .sourceOver, fraction: 1)
                        column += 1
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            // Magnify 4x with hard pixels.
            let factor = 4
            let big = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: sheet.pixelsWide * factor, pixelsHigh: sheet.pixelsHigh * factor,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: big)!
            context.imageInterpolation = .none
            NSGraphicsContext.current = context
            sheet.draw(in: NSRect(x: 0, y: 0, width: big.pixelsWide, height: big.pixelsHigh))
            NSGraphicsContext.restoreGraphicsState()

            let url = URL(fileURLWithPath: directory).appendingPathComponent("status-preview-\(Int(scale))x.png")
            try big.representation(using: .png, properties: [:])!.write(to: url)
            print("wrote \(url.path)")
        }
    }

    /// What the OS does to a template image, approximately: keep the alpha, replace the colour.
    private static func tinted(_ image: NSImage, _ colour: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        colour.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }
}

import AppKit
import NetMeterCore
@testable import NetMeterUI
import XCTest

/// Writes the graph as it looks second after second, one frame per row, so that
/// how it moves can be looked at. Opt-in:
///
///     NET_METER_PREVIEW_DIR=/some/dir swift test --filter StatusFilmstripTests
///
/// The frames come from the real controller, meter and renderer, fed a scripted
/// traffic pattern on a clock that is never exactly on the second.
@MainActor
final class StatusFilmstripTests: XCTestCase {
    private final class Script: CounterSource, @unchecked Sendable {
        var rx: UInt64 = 0, tx: UInt64 = 0, packets: UInt64 = 0
        var second = 0
        func read() -> [String: InterfaceCounters] {
            // Upstream: quiet, with bursts that are easy to follow by eye.
            let bursts: [Int: UInt64] = [4: 2_000_000, 11: 1_200_000, 12: 1_200_000, 19: 600_000, 27: 2_000_000]
            let up = bursts[second] ?? 60_000
            // Downstream: a slow ramp, so every bar is different from its neighbours.
            let down = UInt64(80_000 + (second % 10) * 40_000)
            tx += up; rx += down; packets += 500
            second += 1
            return ["en0": InterfaceCounters(rxBytes: rx, txBytes: tx, rxPackets: packets, txPackets: packets)]
        }
    }

    func testWriteFilmstrip() throws {
        guard let directory = ProcessInfo.processInfo.environment["NET_METER_PREVIEW_DIR"] else {
            throw XCTSkip("set NET_METER_PREVIEW_DIR to write the filmstrip")
        }
        let frames = 36
        var time = 0.0
        var settings = AppSettings()
        settings.displayMode = .graphOnly
        let controller = MeterController(
            counters: Script(),
            pathOrder: { [PathInterface(name: "en0", kind: .wiredEthernet)] },
            now: { time },
            store: InMemorySettingsStore(settings)
        )

        let magnify = 3
        let size = StatusRenderer.size(mode: .graphOnly)
        let rowHeight = Int(size.height) + 2
        let sheet = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width) * magnify, pixelsHigh: rowHeight * frames * magnify,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: sheet)!
        context.imageInterpolation = .none
        NSGraphicsContext.current = context
        NSColor(deviceWhite: 0.12, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: sheet.pixelsWide, height: sheet.pixelsHigh).fill()

        for frame in 0..<frames {
            time = Double(frame) * 1.013 + 0.37
            controller.tick()
            let bitmap = StatusRenderer.bitmap(content: controller.content, finish: .coloured(darkMenuBar: true), scale: 1)
            let y = (frames - 1 - frame) * rowHeight * magnify
            bitmap.draw(in: NSRect(x: 0, y: y, width: Int(size.width) * magnify, height: Int(size.height) * magnify))
        }
        NSGraphicsContext.restoreGraphicsState()

        let url = URL(fileURLWithPath: directory).appendingPathComponent("status-filmstrip.png")
        try sheet.representation(using: .png, properties: [:])!.write(to: url)
        print("wrote \(url.path)")
    }
}

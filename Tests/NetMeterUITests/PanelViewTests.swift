import AppKit
import NetMeterCore
@testable import NetMeterUI
import SwiftUI
import XCTest

/// The panel laid out offscreen by the real layout engine with real fonts.
/// Nothing is launched and nothing appears on screen.
@MainActor
final class PanelViewTests: XCTestCase {
    static func snapshot(reading: MeterReading = .rate(down: 244_000, up: 2_400_000),
                         heading: String = "Ethernet (en0)",
                         addresses: [String] = ["192.0.2.10", PanelViewTests.worstCaseIPv6],
                         loginItem: LoginItemState = .off) -> PanelSnapshot {
        let points = (0..<170).map { index -> ChartPoint in
            let phase = Double(index) / 9
            return ChartPoint(offset: Double(index) - 175, down: 300_000 * abs(sin(phase)), up: 2_400_000 * abs(cos(phase * 0.6)))
        }
        return PanelSnapshot(
            heading: heading, isAutomatic: true, reading: reading, addresses: addresses, linkSpeed: "2.5 Gbps",
            peakDown: 300_000, peakUp: 2_400_000, totals: TransferTotals(downBytes: 40_095_744, upBytes: 1_756_346_368),
            points: reading == .absent ? [] : points, fullScale: 2_400_000, settings: AppSettings(),
            entries: [
                InterfaceListEntry(name: "en0", label: "Ethernet (en0)", isHardwarePort: true, isAvailable: true),
                InterfaceListEntry(name: "en1", label: "Wi-Fi (en1)", isHardwarePort: true, isAvailable: true),
            ],
            loginItem: loginItem, version: "v0.1.0-3-gabc1234-dirty"
        )
    }

    /// No run of zeros to compress: 39 characters, as long as an IPv6 address gets.
    static let worstCaseIPv6 = "fd12:3456:789a:bcde:f012:3456:789a:bcde"

    static func host(_ snapshot: PanelSnapshot) -> NSHostingView<PanelView> {
        let view = NSHostingView(rootView: PanelView(model: PanelModel(snapshot: snapshot)))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        return view
    }

    func testTheWidthIsThePanelsOwnAndTheHeightComesFromTheContent() {
        let size = Self.host(Self.snapshot()).fittingSize
        XCTAssertEqual(size.width, PanelView.width)
        XCTAssertGreaterThan(size.height, 300)
        XCTAssertLessThan(size.height, 620, "taller than a small display can show below the menu bar")
    }

    func testTheLongestIPv6AddressFitsOnOneLine() {
        XCTAssertEqual(Self.worstCaseIPv6.count, 39)
        let font = NSFont.monospacedSystemFont(ofSize: PanelView.addressFontSize, weight: .regular)
        let needed = NSAttributedString(string: Self.worstCaseIPv6, attributes: [.font: font]).size().width
        let available = PanelView.width - PanelView.padding * 2
        XCTAssertLessThanOrEqual(needed + 10, available, "needs \(needed) pt of \(available) pt; an address must not be cut in the middle")
    }

    func testMoreAddressesThanTheLimitAreSummarisedNotStackedWithoutEnd() {
        let few = Self.host(Self.snapshot(addresses: Array(repeating: "", count: 0) + (1...PanelView.addressLimit).map { "192.0.2.\($0)" }))
        let many = Self.host(Self.snapshot(addresses: (1...12).map { "192.0.2.\($0)" }))
        XCTAssertLessThan(many.fittingSize.height - few.fittingSize.height, 24, "one '+N more' line, not eight more rows")
    }

    func testALongInterfaceNameDoesNotWidenThePanel() {
        let long = Self.snapshot(heading: "Thunderbolt Ethernet Slot 2, Port 1 with a very long name (en12) — not connected")
        XCTAssertEqual(Self.host(long).fittingSize.width, PanelView.width)
    }

    func testStatesWithoutAValueKeepTheLayoutWhereItWas() {
        // The panel must not jump when the interface goes away or a sample is discarded.
        let base = Self.host(Self.snapshot()).fittingSize.height
        for reading in [MeterReading.waiting, .absent] {
            let height = Self.host(Self.snapshot(reading: reading)).fittingSize.height
            XCTAssertEqual(height, base, accuracy: 1, "\(reading)")
        }
    }

    func testTheNotesUnderLaunchAtLoginOnlyAddTheirOwnLine() {
        let base = Self.host(Self.snapshot()).fittingSize.height
        for state in [LoginItemState.requiresApproval, .unavailable] {
            let height = Self.host(Self.snapshot(loginItem: state)).fittingSize.height
            XCTAssertGreaterThan(height, base)
            XCTAssertLessThan(height, base + 40, "\(state): the note is meant to be one or two caption lines")
        }
    }

    /// Opt-in: NET_METER_PREVIEW_DIR=<dir> writes the panel as a PNG to look at.
    func testWritePanelPreview() throws {
        guard let directory = ProcessInfo.processInfo.environment["NET_METER_PREVIEW_DIR"] else {
            throw XCTSkip("set NET_METER_PREVIEW_DIR to write the panel preview")
        }
        for (name, snapshot) in [("rate", Self.snapshot()), ("absent", Self.snapshot(reading: .absent, heading: "USB LAN (en7) — not connected", addresses: []))] {
            let view = Self.host(snapshot)
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            let url = URL(fileURLWithPath: directory).appendingPathComponent("panel-\(name).png")
            try rep.representation(using: .png, properties: [:])!.write(to: url)
            print("wrote \(url.path) \(Int(view.bounds.width))x\(Int(view.bounds.height))")
        }
    }
}

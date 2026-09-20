import AppKit
import NetMeterCore
@testable import NetMeterUI
import SwiftUI
import XCTest

/// ADR-0003, pinned. The window is never shown here.
@MainActor
final class PanelWindowTests: XCTestCase {
    func testAClickInThePanelCannotActivateTheApp() {
        // The whole fix. Without this bit the first click inside the panel activates
        // the app, and the activation ends the menu that click has just opened.
        XCTAssertTrue(PanelWindow().styleMask.contains(.nonactivatingPanel))
    }

    func testItTakesKeyStatusButIsNeverTheMainWindow() {
        let panel = PanelWindow()
        XCTAssertTrue(panel.canBecomeKey, "Esc and text selection need key status")
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testItDoesNotHideItselfBehindTheOwnersBack() {
        let panel = PanelWindow()
        XCTAssertFalse(panel.hidesOnDeactivate, "hides without clearing isVisible, and the app is never active anyway")
        XCTAssertEqual(panel.animationBehavior, .none)
        XCTAssertFalse(panel.isReleasedWhenClosed)
    }

    func testItCanBeShownOverAFullScreenAppAndOnTheActiveSpace() {
        let behaviour = PanelWindow().collectionBehavior
        XCTAssertTrue(behaviour.contains(.fullScreenAuxiliary))
        XCTAssertTrue(behaviour.contains(.moveToActiveSpace))
    }

    func testEscGoesToTheOwner() {
        let panel = PanelWindow()
        var cancelled = 0
        panel.onCancel = { cancelled += 1 }
        panel.cancelOperation(nil)
        XCTAssertEqual(cancelled, 1)
    }

    func testTheContentSaysHowBigItWantsToBeAndIsReleasedOnRequest() {
        let panel = PanelWindow()
        XCTAssertFalse(panel.hasContent)
        let model = PanelModel(snapshot: PanelViewTests.snapshot())
        let size = panel.setContent(PanelView(model: model))
        XCTAssertEqual(size.width, PanelView.width)
        XCTAssertEqual(size.height, PanelViewTests.host(PanelViewTests.snapshot()).fittingSize.height, accuracy: 0.5,
                       "the same height the layout tests measure")
        XCTAssertTrue(panel.hasContent)

        panel.clearContent()
        XCTAssertFalse(panel.hasContent)
        XCTAssertNil(panel.contentView)
    }

    func testTheMaterialIsDrawnActiveWhateverTheAppsState() throws {
        let panel = PanelWindow()
        panel.setContent(Text("x"))
        let material = try XCTUnwrap(panel.contentView as? NSVisualEffectView)
        XCTAssertEqual(material.state, .active, "the app stays inactive; a material that followed the window would look sunken")
    }

    func testTheAppNeverAsksToBeActivated() throws {
        // ADR-0003, decision 1. Right after launch the OS refuses the request, and a
        // design that depends on it works everywhere except there.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // NetMeterUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        let asks = try NSRegularExpression(pattern: #"\.activate\(|yieldActivation|NSPopover\("#)
        for spelling in ["NSApp.activate(ignoringOtherApps: true)", "NSApp.activate()", "app.activate(options: [])",
                         "NSApp.yieldActivation(to: other)", "let popover = NSPopover()"] {
            XCTAssertNotNil(asks.firstMatch(in: spelling, range: NSRange(spelling.startIndex..., in: spelling)), spelling)
        }
        var checked = 0
        for directory in ["Sources/NetMeter", "Sources/NetMeterUI", "Sources/NetMeterSystem", "Sources/NetMeterCore"] {
            let files = try FileManager.default
                .contentsOfDirectory(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            for file in files {
                // Comments may name what is not done; code may not do it.
                let code = try String(contentsOf: file, encoding: .utf8)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                    .joined(separator: "\n")
                XCTAssertNil(asks.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)),
                             "\(file.lastPathComponent) asks for activation or brings the popover back; see ADR-0003")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 20, "the sources were not found")
    }
}

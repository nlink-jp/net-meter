import XCTest

/// The app layer's shape, machine-checked at the source (ADR-0004). What these
/// cannot see is what the shape is for — the item shown pressed while the panel
/// is open, a pop-up menu that survives the first click after launch, no work
/// while closed — all of which live in another process or on the screen and were
/// measured by filming and synthetic clicks (macOS 27.0, 2026-09-21). These only
/// keep the code in the shape that was measured.
final class MenuBarShapeTests: XCTestCase {
    private func root() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // NetMeterUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
    }

    /// Code lines only: a comment that names a type is not a use of it.
    private func code(_ relativePath: String) throws -> [String] {
        let text = try String(contentsOf: root().appendingPathComponent(relativePath), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private func appSources() throws -> [(String, [String])] {
        var out: [(String, [String])] = []
        for directory in ["Sources/NetMeter", "Sources/NetMeterUI"] {
            let found = try FileManager.default
                .contentsOfDirectory(at: root().appendingPathComponent(directory), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(found.isEmpty, "no sources found in \(directory)")
            for file in found { out.append(("\(directory)/\(file.lastPathComponent)", try code("\(directory)/\(file.lastPathComponent)"))) }
        }
        return out
    }

    func testTheItemAndThePanelAreAMenuBarExtraWindow() throws {
        let app = try code("Sources/NetMeter/NetMeterApp.swift").joined(separator: "\n")
        XCTAssertTrue(app.contains("MenuBarExtra {"), "the item and the panel are one MenuBarExtra")
        XCTAssertTrue(app.contains(".menuBarExtraStyle(.window)"), "a window, not a menu")
        // A container of our own cannot keep the item shown pressed through public API.
        for (file, lines) in try appSources() {
            for line in lines {
                for type in ["NSStatusItem", "NSStatusBar", "NSPanel", "NSPopover"] {
                    XCTAssertFalse(line.contains(type), "\(file) brings back a container of its own: \(line)")
                }
            }
        }
    }

    func testOnlyTheLabelWatchesTheStateThatChangesEverySecond() throws {
        let delegate = try code("Sources/NetMeter/AppDelegate.swift")
        let declaration = delegate.first { $0.contains("final class AppDelegate") } ?? ""
        XCTAssertFalse(declaration.isEmpty, "wrong file, or AppDelegate was renamed")
        XCTAssertFalse(declaration.contains("ObservableObject"),
                       "whatever observed AppDelegate would be woken once a second: \(declaration)")

        let app = try code("Sources/NetMeter/NetMeterApp.swift")
        let observed = app.filter { $0.contains("@ObservedObject") || $0.contains("@StateObject") || $0.contains("@EnvironmentObject") }
        XCTAssertEqual(observed.map { $0.trimmingCharacters(in: .whitespaces) }, ["@ObservedObject var model: StatusModel"],
                       "only the label observes anything here; the panel observes its own model inside PanelView")
    }

    func testThePanelIsPushedToOnlyWhileItIsOpen() throws {
        let delegate = try code("Sources/NetMeter/AppDelegate.swift")
        guard let start = delegate.firstIndex(where: { $0.contains("private func pushPanelUpdate()") }) else {
            return XCTFail("pushPanelUpdate is gone or renamed")
        }
        let body = delegate[(start + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        XCTAssertTrue(body.contains("guard panelOpen"), "the first thing pushPanelUpdate does is check the panel is open: \(body)")
    }
}

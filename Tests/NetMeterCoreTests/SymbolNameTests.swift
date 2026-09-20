import AppKit
import XCTest
@testable import NetMeterCore

final class SymbolNameTests: XCTestCase {
    func testEveryListedSymbolResolves() {
        XCTAssertFalse(SymbolName.all.isEmpty)
        for name in SymbolName.all {
            XCTAssertNotNil(
                NSImage(systemSymbolName: name, accessibilityDescription: nil),
                "SF Symbol '\(name)' does not exist on this macOS"
            )
        }
    }

    func testAMadeUpNameDoesNotResolve() {
        // Shows the check above can fail: a plausible-looking name yields nil
        // rather than an error.
        XCTAssertNil(
            NSImage(systemSymbolName: "arrow.up.arrow.down.net-meter-no-such-variant",
                    accessibilityDescription: nil)
        )
    }

    func testAppSourcesNeverSpellASymbolNameAsALiteral() throws {
        // A literal would bypass the list the first test walks.
        let appSources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // NetMeterCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/NetMeter")
        let files = try FileManager.default
            .contentsOfDirectory(at: appSources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "no app sources found at \(appSources.path)")

        let literal = try NSRegularExpression(pattern: #"system(Symbol)?Name:\s*""#)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(text.startIndex..., in: text)
            XCTAssertNil(
                literal.firstMatch(in: text, range: range),
                "\(file.lastPathComponent) spells an SF Symbol name as a literal; use SymbolName"
            )
        }
    }
}

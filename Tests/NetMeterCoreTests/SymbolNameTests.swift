import AppKit
import XCTest
@testable import NetMeterCore

final class SymbolNameTests: XCTestCase {
    func testEveryListedSymbolResolves() {
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
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // NetMeterCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
        var files: [URL] = []
        for directory in ["Sources/NetMeter", "Sources/NetMeterUI"] {
            let found = try FileManager.default
                .contentsOfDirectory(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "swift" }
            XCTAssertFalse(found.isEmpty, "no sources found in \(directory)")
            files += found
        }

        // AppKit's `systemSymbolName:`, and SwiftUI's `systemName:` and `systemImage:`.
        let literal = try NSRegularExpression(pattern: #"system(SymbolName|Name|Image):\s*""#)
        for spelling in [#"NSImage(systemSymbolName: "x""#, #"Image(systemName: "x")"#, #"Label("Quit", systemImage: "power")"#] {
            XCTAssertNotNil(literal.firstMatch(in: spelling, range: NSRange(spelling.startIndex..., in: spelling)), spelling)
        }
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

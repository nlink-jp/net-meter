import XCTest

/// Replacing a piece of UI leaves its strings behind unless something notices.
/// This walks the catalogue and requires every entry to be used by some source
/// file, so a string cannot outlive the control it labelled.
final class UIStringsTests: XCTestCase {
    func testEveryStringIsUsedSomewhere() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalogue = root.appendingPathComponent("Sources/NetMeterUI/UIStrings.swift")
        let declared = try NSRegularExpression(pattern: #"public static (?:let|func) (\w+)"#)
        let text = try String(contentsOf: catalogue, encoding: .utf8)
        let names = declared.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .map { String(text[Range($0.range(at: 1), in: text)!]) }
        XCTAssertGreaterThan(names.count, 10, "the catalogue was not parsed")

        var sources = ""
        for directory in ["Sources/NetMeter", "Sources/NetMeterUI"] {
            let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(directory), includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "swift" && file.lastPathComponent != "UIStrings.swift" {
                sources += try String(contentsOf: file, encoding: .utf8)
            }
        }
        // `UIStrings.version(` inside the catalogue itself does not count; a use does.
        for name in Set(names) {
            XCTAssertTrue(sources.contains("UIStrings.\(name)"), "UIStrings.\(name) is not used by any source file")
        }
    }
}

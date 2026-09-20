import XCTest
@testable import NetMeterCore

final class RateFormatterTests: XCTestCase {
    private func bytes(_ value: Double) -> String { RateFormatter.format(bytesPerSecond: value, unit: .bytes).text }
    private func bits(_ value: Double) -> String { RateFormatter.format(bytesPerSecond: value, unit: .bits).text }

    func testTheValuesInTheOriginalRequest() {
        XCTAssertEqual(bytes(2_400_000), "2.4 MB/s")
        XCTAssertEqual(bytes(244_000), "244 KB/s")
    }

    func testKilobytesAreWholeNumbers() {
        // The counters are floored to 1 KiB; decimals below that would be invented.
        XCTAssertEqual(bytes(0), "0 KB/s")
        XCTAssertEqual(bytes(1_024), "1 KB/s")
        XCTAssertEqual(bytes(2_400), "2 KB/s")
        XCTAssertEqual(bytes(999_400), "999 KB/s")
    }

    func testRoundingUpToFourDigitsMovesToTheNextUnit() {
        XCTAssertEqual(bytes(999_500), "1.0 MB/s")
        XCTAssertEqual(bytes(999_500_000), "1.0 GB/s")
    }

    func testOneDecimalBelowTenThenWholeNumbers() {
        XCTAssertEqual(bytes(9_940_000), "9.9 MB/s")
        XCTAssertEqual(bytes(9_960_000), "10 MB/s")
        XCTAssertEqual(bytes(288_226_304), "288 MB/s")  // measured peak
        XCTAssertEqual(bytes(1_250_000_000), "1.3 GB/s")
    }

    func testBitsPerSecond() {
        XCTAssertEqual(bits(0), "0 kbps")
        XCTAssertEqual(bits(125_000), "1.0 Mbps")
        XCTAssertEqual(bits(30_500), "244 kbps")
        XCTAssertEqual(bits(288_226_304), "2.3 Gbps")
    }

    func testTheNumberNeverOutgrowsItsField() {
        var value = 1.0
        while value < 1e15 {
            for unit in RateUnit.allCases {
                let formatted = RateFormatter.format(bytesPerSecond: value, unit: unit)
                XCTAssertLessThanOrEqual(formatted.number.count, RateFormatter.numberWidth, "\(value) -> \(formatted.text)")
                XCTAssertFalse(formatted.number.isEmpty)
            }
            value *= 1.37
        }
    }

    func testNonsenseInputIsZeroNotACrash() {
        XCTAssertEqual(bytes(-5), "0 KB/s")
        XCTAssertEqual(bytes(.nan), "0 KB/s")
        XCTAssertEqual(bytes(.infinity), "0 KB/s")
        XCTAssertEqual(bytes(1e300), "999 GB/s", "finite but absurd: clamped, not a trap")
    }
}

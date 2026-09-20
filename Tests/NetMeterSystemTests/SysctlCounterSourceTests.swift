import Foundation
import NetMeterCore
import NetMeterSystem
import XCTest

/// Live tests: they read this Mac's real counters. They need no network traffic,
/// no permission and no particular interface beyond loopback.
final class SysctlCounterSourceTests: XCTestCase {
    func testReadsTheLoopbackInterfaceWithoutAnyPrivilege() {
        XCTAssertNotEqual(getuid(), 0, "run the tests unprivileged; that is what the app is")
        let reading = SysctlCounterSource().read()
        XCTAssertFalse(reading.isEmpty, "sysctl NET_RT_IFLIST2 returned nothing")
        XCTAssertNotNil(reading["lo0"], "interfaces seen: \(reading.keys.sorted())")
        for name in reading.keys {
            XCTAssertFalse(name.isEmpty)
            XCTAssertFalse(name.contains("\0"))
        }
    }

    func testAnOrdinarySecondIsNeverJudgedAResetOnAnyLiveInterface() {
        // ADR-0001 against the real thing: whatever this Mac's interfaces are
        // doing right now, one second of it must come out as a rate.
        let source = SysctlCounterSource()
        let clock = ContinuousClock()
        var meter = Meter()

        let start = clock.now
        let first = meter.ingest(source.read(), at: 0)
        XCTAssertFalse(first.isEmpty)
        XCTAssertTrue(first.values.allSatisfy { $0 == .baseline })

        Thread.sleep(forTimeInterval: 1.0)
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let second = meter.ingest(source.read(), at: seconds)

        for (name, outcome) in second {
            guard case .rate(let rate) = outcome else {
                // An interface that appeared within this second is a baseline; nothing else is acceptable.
                XCTAssertEqual(outcome, .baseline, "\(name): \(outcome) after \(seconds) s")
                XCTAssertNil(first[name], "\(name) was present in both readings but came out as \(outcome)")
                continue
            }
            XCTAssertTrue(rate.downBytesPerSecond.isFinite && rate.downBytesPerSecond >= 0, name)
            XCTAssertTrue(rate.upBytesPerSecond.isFinite && rate.upBytesPerSecond >= 0, name)
        }
    }

    func testTwoReadingsInARowDescribeTheSameInterfaces() {
        let source = SysctlCounterSource()
        let a = Set(source.read().keys), b = Set(source.read().keys)
        XCTAssertEqual(a, b)
    }
}

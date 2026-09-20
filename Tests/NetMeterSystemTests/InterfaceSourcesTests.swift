import Foundation
import NetMeterCore
@testable import NetMeterSystem
import XCTest

/// Live tests against this Mac. They assert only what holds on any Mac, and they
/// never print an address.
final class InterfaceSourcesTests: XCTestCase {
    func testLoopbackHasItsAddressAndNoDisplayName() {
        let info = SystemInterfaceInfoSource().info()
        XCTAssertEqual(info["lo0"]?.addresses.first, "127.0.0.1")
        XCTAssertNil(info["lo0"]?.displayName, "loopback is not a hardware port")
    }

    func testAddressesAreNumericUnscopedAndNotLinkLocal() {
        for (name, entry) in SystemInterfaceInfoSource().info() {
            for address in entry.addresses {
                XCTAssertFalse(address.contains("%"), "\(name): scope suffix left in")
                XCTAssertFalse(address.lowercased().hasPrefix("fe80:"), "\(name): link-local left in")
                XCTAssertFalse(address.isEmpty, name)
            }
            let firstV6 = entry.addresses.firstIndex { $0.contains(":") } ?? entry.addresses.count
            XCTAssertFalse(entry.addresses[firstV6...].contains { !$0.contains(":") }, "\(name): IPv4 must come first")
        }
    }

    func testEveryNamedPortAlsoHasCounters() {
        // The list the user picks from is built from both sources; a display name
        // for an interface the counter reader cannot see would be a dead entry.
        let counters = SysctlCounterSource().read()
        for (name, displayName) in SystemInterfaceInfoSource.displayNames() {
            XCTAssertFalse(displayName.isEmpty)
            XCTAssertNotNil(counters[name], "\(name) has a display name but no counters")
        }
    }

    func testPathMonitorDeliversAnOrderSoonAfterStart() {
        let monitor = PathOrderMonitor()
        let delivered = expectation(description: "first path update")
        delivered.assertForOverFulfill = false
        let box = Box()
        monitor.start { order in
            box.set(order)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        monitor.cancel()

        XCTAssertEqual(monitor.current, box.get())
        let counters = SysctlCounterSource().read()
        for interface in monitor.current {
            XCTAssertNotNil(counters[interface.name], "\(interface.name) is in the path order but has no counters")
        }
    }

    func testEveryPathTypeMapsToAKind() {
        XCTAssertEqual(PathOrderMonitor.kind(of: .wifi), .wifi)
        XCTAssertEqual(PathOrderMonitor.kind(of: .wiredEthernet), .wiredEthernet)
        XCTAssertEqual(PathOrderMonitor.kind(of: .cellular), .cellular)
        XCTAssertEqual(PathOrderMonitor.kind(of: .loopback), .loopback)
        XCTAssertEqual(PathOrderMonitor.kind(of: .other), .other)
        XCTAssertTrue(InterfaceKind.wifi.isPhysical && InterfaceKind.wiredEthernet.isPhysical)
        XCTAssertFalse(InterfaceKind.other.isPhysical || InterfaceKind.loopback.isPhysical || InterfaceKind.cellular.isPhysical)
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [PathInterface] = []
    func set(_ new: [PathInterface]) { lock.lock(); value = new; lock.unlock() }
    func get() -> [PathInterface] { lock.lock(); defer { lock.unlock() }; return value }
}

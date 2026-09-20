import XCTest
@testable import NetMeterCore

final class InterfaceCatalogTests: XCTestCase {
    private let info: [String: InterfaceInfo] = [
        "en0": InterfaceInfo(displayName: "Ethernet"),
        "en1": InterfaceInfo(displayName: "Wi-Fi"),
        "en10": InterfaceInfo(displayName: "USB 10/100/1000 LAN"),
        "en2": InterfaceInfo(displayName: "Thunderbolt 1"),
        "utun4": InterfaceInfo(),
        "bridge100": InterfaceInfo(displayName: ""),
    ]
    private let path = [
        PathInterface(name: "en0", kind: .wiredEthernet),
        PathInterface(name: "en0", kind: .wiredEthernet),
        PathInterface(name: "en1", kind: .wifi),
        PathInterface(name: "lo0", kind: .loopback),
    ]

    func testLabel() {
        XCTAssertEqual(InterfaceCatalog.label(name: "en0", displayName: "Ethernet"), "Ethernet (en0)")
        XCTAssertEqual(InterfaceCatalog.label(name: "utun4", displayName: nil), "utun4")
        XCTAssertEqual(InterfaceCatalog.label(name: "bridge100", displayName: ""), "bridge100")
    }

    func testHardwarePortsComeFirstInPreferenceOrderThenTheRestByName() {
        let entries = InterfaceCatalog.entries(
            available: ["utun4", "en10", "en1", "bridge100", "en2", "en0", "lo0"],
            info: info, pathOrder: path, selection: .automatic
        )
        XCTAssertEqual(entries.map(\.name), ["en0", "en1", "en2", "en10", "bridge100", "utun4"])
        XCTAssertEqual(entries.map(\.isHardwarePort), [true, true, true, true, false, false])
        XCTAssertEqual(entries.first?.label, "Ethernet (en0)")
        XCTAssertTrue(entries.allSatisfy(\.isAvailable))
    }

    func testNamesSortNumericallyNotLexically() {
        let entries = InterfaceCatalog.entries(
            available: ["utun10", "utun2", "utun1"], info: [:], pathOrder: [], selection: .automatic
        )
        XCTAssertEqual(entries.map(\.name), ["utun1", "utun2", "utun10"])
    }

    func testLoopbackIsLeftOut() {
        let entries = InterfaceCatalog.entries(available: ["lo0", "en0"], info: info, pathOrder: path, selection: .automatic)
        XCTAssertEqual(entries.map(\.name), ["en0"])
    }

    func testAnAbsentManualSelectionStaysInTheListMarkedUnavailable() {
        let entries = InterfaceCatalog.entries(
            available: ["en0", "en1"], info: info, pathOrder: path, selection: .manual("en10")
        )
        XCTAssertEqual(entries.map(\.name), ["en0", "en1", "en10"])
        XCTAssertEqual(entries.last, InterfaceListEntry(
            name: "en10", label: "USB 10/100/1000 LAN (en10)", isHardwarePort: true, isAvailable: false
        ))
    }

    func testAPresentManualSelectionIsNotListedTwice() {
        let entries = InterfaceCatalog.entries(
            available: ["en0", "en1"], info: info, pathOrder: path, selection: .manual("en1")
        )
        XCTAssertEqual(entries.map(\.name), ["en0", "en1"])
    }
}

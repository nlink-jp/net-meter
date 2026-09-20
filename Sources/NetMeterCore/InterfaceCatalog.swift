import Foundation

/// What the OS can tell about an interface besides its counters.
public struct InterfaceInfo: Equatable, Sendable {
    /// The name System Settings shows ("Ethernet", "Wi-Fi"). Nil for interfaces
    /// that are not hardware ports: tunnels, bridges, loopback.
    public var displayName: String?
    /// Numeric addresses, IPv4 first.
    public var addresses: [String]

    public init(displayName: String? = nil, addresses: [String] = []) {
        self.displayName = displayName
        self.addresses = addresses
    }
}

/// Where display names and addresses come from. The real source asks
/// SystemConfiguration and `getifaddrs`.
public protocol InterfaceInfoSource: Sendable {
    /// Keyed by BSD name.
    func info() -> [String: InterfaceInfo]
}

/// One row of the manual selection list.
public struct InterfaceListEntry: Equatable, Sendable {
    public var name: String
    /// "Ethernet (en0)", or just "utun4" when there is no display name.
    public var label: String
    /// A port System Settings knows by name, as opposed to a tunnel or a bridge.
    public var isHardwarePort: Bool
    /// False for a manual selection that is currently gone. It stays in the
    /// list, marked, so the user's choice never looks silently dropped.
    public var isAvailable: Bool

    public init(name: String, label: String, isHardwarePort: Bool, isAvailable: Bool) {
        self.name = name
        self.label = label
        self.isHardwarePort = isHardwarePort
        self.isAvailable = isAvailable
    }
}

public enum InterfaceCatalog {
    /// "Ethernet (en0)" when the OS has a name for the port, otherwise the BSD name.
    public static func label(name: String, displayName: String?) -> String {
        guard let displayName, !displayName.isEmpty else { return name }
        return "\(displayName) (\(name))"
    }

    /// The manual selection list: hardware ports first, in the OS preference
    /// order and then by name; every other interface after them, by name
    /// (`en2` before `en10`). Loopback is left out — it is never what anyone
    /// means by "my network". A manual selection that is absent is appended.
    public static func entries(
        available: Set<String>,
        info: [String: InterfaceInfo],
        pathOrder: [PathInterface],
        selection: InterfaceSelection
    ) -> [InterfaceListEntry] {
        var preference: [String: Int] = [:]
        for (index, interface) in pathOrder.enumerated() where preference[interface.name] == nil {
            preference[interface.name] = index
        }
        let loopback = Set(pathOrder.filter { $0.kind == .loopback }.map(\.name)).union(["lo0"])

        func isHardware(_ name: String) -> Bool { !(info[name]?.displayName ?? "").isEmpty }
        func entry(_ name: String, isAvailable: Bool) -> InterfaceListEntry {
            InterfaceListEntry(
                name: name,
                label: label(name: name, displayName: info[name]?.displayName),
                isHardwarePort: isHardware(name),
                isAvailable: isAvailable
            )
        }
        func byName(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }

        let names = available.subtracting(loopback)
        let hardware = names.filter(isHardware).sorted { a, b in
            switch (preference[a], preference[b]) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return byName(a, b)
            }
        }
        let others = names.filter { !isHardware($0) }.sorted(by: byName)

        var entries = (hardware + others).map { entry($0, isAvailable: true) }
        if case .manual(let chosen) = selection, !available.contains(chosen) {
            entries.append(entry(chosen, isAvailable: false))
        }
        return entries
    }
}

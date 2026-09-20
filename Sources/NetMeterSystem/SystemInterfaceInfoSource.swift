import Darwin
import NetMeterCore
import SystemConfiguration

/// Display names from SystemConfiguration and numeric addresses from `getifaddrs`.
/// Neither needs a privilege, an entitlement or a TCC grant.
public struct SystemInterfaceInfoSource: InterfaceInfoSource {
    public init() {}

    public func info() -> [String: InterfaceInfo] {
        var result: [String: InterfaceInfo] = [:]
        for (name, displayName) in Self.displayNames() {
            result[name, default: InterfaceInfo()].displayName = displayName
        }
        for (name, addresses) in Self.addresses() {
            result[name, default: InterfaceInfo()].addresses = addresses
        }
        return result
    }

    /// Hardware ports only: tunnels, bridges and loopback have no entry here.
    static func displayNames() -> [String: String] {
        var names: [String: String] = [:]
        for interface in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            guard let bsdName = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let displayName = SCNetworkInterfaceGetLocalizedDisplayName(interface) as String?,
                  !displayName.isEmpty else { continue }
            names[bsdName] = displayName
        }
        return names
    }

    /// IPv4 first, then IPv6. Link-local IPv6 is left out: every interface has
    /// one and it identifies nothing.
    static func addresses() -> [String: [String]] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [:] }
        defer { freeifaddrs(head) }

        var v4: [String: [String]] = [:], v6: [String: [String]] = [:]
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = entry.pointee.ifa_addr else { continue }
            let family = Int32(address.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            var text = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            // A scoped address is printed as "fe80::1%en0".
            if let percent = text.firstIndex(of: "%") { text = String(text[..<percent]) }

            let name = String(cString: entry.pointee.ifa_name)
            if family == AF_INET {
                v4[name, default: []].append(text)
            } else if !text.lowercased().hasPrefix("fe80:") {
                v6[name, default: []].append(text)
            }
        }
        var result: [String: [String]] = [:]
        for name in Set(v4.keys).union(v6.keys) {
            result[name] = (v4[name] ?? []) + (v6[name] ?? [])
        }
        return result
    }
}

// Feasibility spike: can we resolve "the physical interface carrying traffic" with public API?
import Foundation
import Network
import SystemConfiguration

func typeName(_ t: NWInterface.InterfaceType) -> String {
    switch t {
    case .wifi: return "wifi"
    case .wiredEthernet: return "wiredEthernet"
    case .cellular: return "cellular"
    case .loopback: return "loopback"
    case .other: return "other"
    @unknown default: return "unknown"
    }
}

// SystemConfiguration view: hardware-backed interfaces and their kind.
var scKinds: [String: String] = [:]
for iface in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
    if let bsd = SCNetworkInterfaceGetBSDName(iface) as String? {
        scKinds[bsd] = (SCNetworkInterfaceGetInterfaceType(iface) as String?) ?? "-"
    }
}

let sem = DispatchSemaphore(value: 0)
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    print("path status=\(path.status) — availableInterfaces (preference order):")
    for (i, nif) in path.availableInterfaces.enumerated() {
        print("  [\(i)] \(nif.name) type=\(typeName(nif.type)) scKind=\(scKinds[nif.name] ?? "(not in SC list)")")
    }
    let physical = path.availableInterfaces.first { $0.type == .wifi || $0.type == .wiredEthernet }
    print("first physical = \(physical?.name ?? "nil")")
    sem.signal()
}
monitor.start(queue: DispatchQueue(label: "spike"))
_ = sem.wait(timeout: .now() + 3)
monitor.cancel()

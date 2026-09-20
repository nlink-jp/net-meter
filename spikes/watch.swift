// Spike: record what the app will see, once per second, as JSON lines.
//
// Each line holds the elapsed time on a clock that keeps running during sleep,
// the OS interface preference order with types, and every interface's raw
// counters. Run it across the events the design has to survive — a sleep, a VPN
// connecting, an adapter being unplugged — then read the log with
// spikes/analyze_watch.py.
//
//   watch [seconds]     default 60; 0 = until interrupted
import Darwin
import Foundation
import Network

func readCounters() -> [String: [UInt64]] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var len = 0
    guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return [:] }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return [:] }
    var result: [String: [UInt64]] = [:]
    buf.withUnsafeBytes { p in
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= len {
            let hdr = p.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                let m = p.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(m.ifm_index), &nameBuf) != nil {
                    let d = m.ifm_data
                    // rx, tx, ipkts, opkts, baud
                    result[String(cString: nameBuf)] =
                        [d.ifi_ibytes, d.ifi_obytes, d.ifi_ipackets, d.ifi_opackets, d.ifi_baudrate]
                }
            }
            if hdr.ifm_msglen == 0 { break }
            offset += Int(hdr.ifm_msglen)
        }
    }
    return result
}

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

final class PathBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: [[String]] = []
    func set(_ v: [[String]]) { lock.lock(); value = v; lock.unlock() }
    func get() -> [[String]] { lock.lock(); defer { lock.unlock() }; return value }
}

let limit = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 60 : 60
let pathBox = PathBox()
let monitor = NWPathMonitor()
monitor.pathUpdateHandler = { path in
    pathBox.set(path.availableInterfaces.map { [$0.name, typeName($0.type)] })
}
monitor.start(queue: DispatchQueue(label: "watch.path"))

setvbuf(stdout, nil, _IOLBF, 0)
let clock = ContinuousClock()
let start = clock.now
let wall = ISO8601DateFormatter()
while true {
    let elapsed = clock.now - start
    let t = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let line: [String: Any] = [
        "t": (t * 1000).rounded() / 1000,
        "wall": wall.string(from: Date()),
        "path": pathBox.get(),
        "if": readCounters().filter { $0.value.prefix(4).contains { $0 > 0 } },
    ]
    if let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]),
       let text = String(data: data, encoding: .utf8) {
        print(text)
    }
    if limit > 0 && t >= limit { break }
    Thread.sleep(forTimeInterval: 1.0)
}

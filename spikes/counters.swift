// Spike: what an unprivileged process is handed by sysctl NET_RT_IFLIST2.
//
// Prints, per interface, the byte and packet counters, the link speed, and the
// rates over a one-second interval. Bracket a run with `netstat -ibn` to compare
// against the unaltered values — see spikes/README.md.
//
//   counters            one reading pair, one second apart
//   counters --raw      one reading, machine-readable: name rx tx ipkts opkts baud
import Darwin
import Foundation
import SystemConfiguration

func primaryInterface() -> String? {
    for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
        if let dict = SCDynamicStoreCopyValue(nil, key as CFString) as? [String: Any],
           let name = dict["PrimaryInterface"] as? String {
            return name
        }
    }
    return nil
}

struct Counters {
    var rx: UInt64, tx: UInt64
    var ipkts: UInt64, opkts: UInt64
    var baud: UInt64
}

func readCounters() -> [String: Counters] {
    var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
    var len = 0
    guard sysctl(&mib, 6, nil, &len, nil, 0) == 0 else { return [:] }
    var buf = [UInt8](repeating: 0, count: len)
    guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return [:] }
    var result: [String: Counters] = [:]
    buf.withUnsafeBytes { p in
        var offset = 0
        while offset + MemoryLayout<if_msghdr>.size <= len {
            let hdr = p.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
            if Int32(hdr.ifm_type) == RTM_IFINFO2 {
                let m = p.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                var nameBuf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                if if_indextoname(UInt32(m.ifm_index), &nameBuf) != nil {
                    let d = m.ifm_data
                    result[String(cString: nameBuf)] = Counters(
                        rx: d.ifi_ibytes, tx: d.ifi_obytes,
                        ipkts: d.ifi_ipackets, opkts: d.ifi_opackets,
                        baud: d.ifi_baudrate
                    )
                }
            }
            if hdr.ifm_msglen == 0 { break }
            offset += Int(hdr.ifm_msglen)
        }
    }
    return result
}

func displayNames() -> [String: String] {
    var map: [String: String] = [:]
    for iface in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
        if let bsd = SCNetworkInterfaceGetBSDName(iface) as String?,
           let disp = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String? {
            map[bsd] = disp
        }
    }
    return map
}

if CommandLine.arguments.contains("--raw") {
    let now = readCounters()
    for name in now.keys.sorted() {
        let c = now[name]!
        print("\(name) \(c.rx) \(c.tx) \(c.ipkts) \(c.opkts) \(c.baud)")
    }
    exit(0)
}

let names = displayNames()
let primary = primaryInterface()
print("uid=\(getuid()) primary=\(primary ?? "nil") (\(primary.flatMap { names[$0] } ?? "-"))")

let clock = ContinuousClock()
let a = readCounters()
let t0 = clock.now
Thread.sleep(forTimeInterval: 1.0)
let b = readCounters()
let elapsed = clock.now - t0
let dt = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

print("interfaces seen: \(b.count); elapsed \(String(format: "%.4f", dt)) s")
for name in b.keys.sorted() {
    guard let x = a[name], let y = b[name], y.rx > 0 || y.tx > 0 else { continue }
    // Always modulo 2^32: correct whether or not the OS truncated the counter.
    let down = Double((y.rx &- x.rx) & 0xFFFF_FFFF) / dt
    let up = Double((y.tx &- x.tx) & 0xFFFF_FFFF) / dt
    let mark = name == primary ? "*" : " "
    print("\(mark) \(name) [\(names[name] ?? "-")]")
    print("    bytes   rx=\(y.rx) tx=\(y.tx)  (rx%1024=\(y.rx % 1024) tx%1024=\(y.tx % 1024))")
    print("    packets in=\(y.ipkts) out=\(y.opkts)")
    print("    baud    \(y.baud) bit/s")
    print(String(format: "    rate    down=%.1f KB/s up=%.1f KB/s", down / 1000, up / 1000))
}

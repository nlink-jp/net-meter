// Feasibility spike: primary interface detection + 64-bit byte counters, unprivileged.
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

struct Counters { var rx: UInt64; var tx: UInt64 }

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
                    result[String(cString: nameBuf)] =
                        Counters(rx: m.ifm_data.ifi_ibytes, tx: m.ifm_data.ifi_obytes)
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

let names = displayNames()
let primary = primaryInterface()
print("uid=\(getuid()) primary=\(primary ?? "nil") (\(primary.flatMap { names[$0] } ?? "-"))")

let a = readCounters()
let t0 = DispatchTime.now().uptimeNanoseconds
Thread.sleep(forTimeInterval: 1.0)
let b = readCounters()
let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e9

print("interfaces seen: \(b.count); MemoryLayout(ifi_ibytes)=\(MemoryLayout.size(ofValue: b.first!.value.rx)) bytes")
for name in b.keys.sorted() {
    guard let x = a[name], let y = b[name], y.rx > 0 || y.tx > 0 else { continue }
    let down = Double(y.rx &- x.rx) / dt, up = Double(y.tx &- x.tx) / dt
    let mark = name == primary ? "*" : " "
    print(String(format: "%@ %-8@ %-24@ total rx=%llu tx=%llu  down=%.1f KB/s up=%.1f KB/s",
                 mark, name as NSString, (names[name] ?? "-") as NSString, y.rx, y.tx, down / 1000, up / 1000))
}

# spikes

Measurement code the design rests on. These files are not part of the Swift
package (SwiftPM only builds `Sources/` and `Tests/`) and are never shipped. They
exist so that a measured claim in the RFP can be measured again.

## counters.swift

Reads the per-interface byte counters the way the app will — `sysctl`
`NET_RT_IFLIST2`, unprivileged — twice, one second apart, and prints the totals
and the rates. It also prints the primary interface and the display names.

```bash
swiftc -O spikes/counters.swift -o .build/counters
```

```bash
.build/counters
```

To see what the OS does to the values, bracket a run with the system's own
`netstat`, which is handed the unaltered counters:

```bash
netstat -ibn -I en0; .build/counters; netstat -ibn -I en0
```

What this showed (2026-09-20):

| Environment | Floored to 1 KiB | Truncated to 32 bits | Observations |
|-------------|------------------|----------------------|--------------|
| macOS 27.0 (real machine, wired) | Yes | Yes — the value is the true value modulo 2^32 | Two bracketed comparisons, run independently |
| macOS 26.6.2 (VM, virtual NIC) | Yes | Unconfirmed — the counters were below 4 GiB | One bracketed comparison |

Not read yet: the packet counters (`ifi_ipackets` / `ifi_opackets`) and the link
speed (`ifi_baudrate`). The reset rule's candidates depend on them, and since the
byte counters arrive altered, these cannot be assumed to arrive untouched. Extend
this spike to print them before designing the rule.

Reading notes:

- A truncated value can only be recognised once the true counter has passed
  4 GiB. Compare against `netstat`'s value modulo 4294967296.
- In `netstat -ibn` output, a row without an address (`lo0`, `utun*`) has one
  column fewer, so `Ibytes`/`Obytes` are fields 6 and 9 there instead of 7 and 10.
- Pushing 4 GiB through loopback with `nc` did not generate traffic on the VM;
  another way of producing the load is needed to settle the macOS 26 column.

To run it on an older macOS than the build machine, cross-compile and copy the
binary over; an ad-hoc signed binary copied with `scp` carries no quarantine
attribute and runs as is.

```bash
swiftc -O -target arm64-apple-macos26.0 spikes/counters.swift -o .build/counters26
```

## path_order.swift

Lists `NWPathMonitor.availableInterfaces` — the OS preference order, with each
interface's type — and the first Wi-Fi or wired Ethernet entry, which is the
"physical interface" rule the automatic selection uses.

```bash
swiftc -O spikes/path_order.swift -o .build/path_order
```

```bash
.build/path_order
```

What this showed (2026-09-20, macOS 27.0, no VPN, two runs): wired Ethernet first,
Wi-Fi second, and **the same interface listed twice** — in both runs. Behaviour
while a VPN is connected has not been measured yet; run it with the VPN up and
check that the tunnel interface appears with type `other` and is skipped, and
that the physical interface is still in the list.

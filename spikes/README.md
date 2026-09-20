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

| Environment | Byte counters floored to 1 KiB | Byte counters truncated to 32 bits | Observations |
|-------------|-------------------------------|------------------------------------|--------------|
| macOS 27.0 (real machine, wired) | Yes | Yes — the value is the true value modulo 2^32 | Three bracketed comparisons, one of them run independently |
| macOS 26.6.2 (VM, virtual NIC) | Yes | Yes — true 5,438,231,389 read as 1,143,263,232 | Flooring three times; truncation once, after pushing 4.5 GB in so the true counter passed 2^32 |

The packet counters (`ifi_ipackets` / `ifi_opackets`) arrive **unaltered**: not
floored, and equal to `netstat` on an idle interface (macOS 27.0 on two interfaces,
macOS 26.6.2 on one). Whether they are truncated to 32 bits is unknown — no
interface had reached 2^32 packets.

The link speed (`ifi_baudrate`) is readable but **is not a ceiling**: wired
reported 2,500,000,000 (matching `ifconfig`'s 2500Base-T), Wi-Fi 239,040,000, a
virtual NIC on the host 100,000,000 while carrying 2.3 Gbps, and the VM's virtual
NIC 0. ADR-0001 therefore does not judge samples by it.

`counters --raw` prints one machine-readable reading (`name rx tx ipkts opkts
baud`) for scripted comparisons.

Reading notes:

- A truncated value can only be recognised once the true counter has passed
  4 GiB. Compare against `netstat`'s value modulo 4294967296.
- In `netstat -ibn` output, a row without an address (`lo0`, `utun*`) has one
  column fewer, so `Ibytes`/`Obytes` are fields 6 and 9 there instead of 7 and 10.
- To get a counter past 2^32 on a fresh machine, push data into it over SSH:
  `head -c 4500000000 /dev/zero | ssh <vm> 'cat > /dev/null'` took 16 seconds to
  a VM on the same host. (An earlier attempt with `nc` over loopback generated no
  traffic.)
- Scripts that drive `ssh` with options held in a variable belong in bash, not
  zsh: zsh does not split an unquoted variable into words.

To run it on an older macOS than the build machine, cross-compile and copy the
binary over; an ad-hoc signed binary copied with `scp` carries no quarantine
attribute and runs as is.

```bash
swiftc -O -target arm64-apple-macos26.0 spikes/counters.swift -o .build/counters26
```

## watch.swift and analyze_watch.py

`watch` records what the app will see, once per second, as JSON lines: elapsed
time on a clock that keeps running during sleep, the interface preference order
with types, and every interface's raw counters. `analyze_watch.py` reads the log
and reports, per interface, the largest bytes-per-packet ratio in one sample,
stretched intervals, counters that went backwards, interfaces appearing and
disappearing, and changes in the preference order. Its tests run with `make test`.

```bash
swiftc -O spikes/watch.swift -o .build/watch
```

```bash
.build/watch 120 > watch.jsonl
```

```bash
python3 spikes/analyze_watch.py watch.jsonl
```

What this showed (2026-09-20, macOS 27.0, 50 samples, 17 interfaces, while pushing
and then pulling 2 GB at about 286 MB/s): the largest bytes-per-packet ratio was
31,477 (TSO makes a counted packet larger than the MTU, but none exceeded
64 KiB); no sample had more than 1 KiB of bytes with zero packets; no stretched
interval and no counter going backwards. These are the inputs to ADR-0001.

A second recording (2026-09-20, macOS 27.0, 385 samples of ordinary use, up to
25.9 MB/s, with a split-tunnel VPN connected for about 71 seconds): the tunnel
appeared as `utun6` and disappeared again; no stretched interval, no counter
going backwards, no bytes without packets; the largest bytes-per-packet ratio was
42,609 — a new maximum, still below 64 KiB.

Replaying a log through the real `Meter` shows what every sample comes out as:

```bash
NET_METER_REPLAY_LOG=watch.jsonl swift test --filter ReplayTests
```

For the recording above: on every interface, one baseline and then nothing but
rates — no sample judged a reset, none discarded. `utun6` started from a baseline
when it appeared.

A third recording (2026-09-20, macOS 27.0, 3,482 samples — about 58 minutes of
ordinary use with other work running): the wired interface sent 16.6 GB, so its
32-bit byte counter **wrapped at least three times** during the recording.
Replayed through `Meter`: one baseline and then 3,481 rates on every interface —
no wrap was judged a reset, and nothing was discarded.

Still to be recorded: a wake from sleep, an adapter being unplugged, a switch
between Wi-Fi and wired, and a full-tunnel VPN.

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

What this showed (2026-09-20, macOS 27.0, no VPN, three runs including one by
`watch`): wired Ethernet first, Wi-Fi second, and **the same interface listed
twice** — in all three.

With a split-tunnel VPN up (one observation, recorded by `watch`): the tunnel
interface was appended **at the end** of the list with type `other`, and the
physical interfaces kept their places — `en0`, `en0`, `en1`, `utun6`. A
full-tunnel VPN, which takes over the default route, has not been measured and
may order the list differently.

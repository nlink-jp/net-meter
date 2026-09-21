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

A third recording (2026-09-20, macOS 27.0, 3,569 samples — an hour of ordinary
use with other work running, the split-tunnel VPN period above included): the
wired interface sent 17.1 GB at up to 50.7 MB/s, so its 32-bit byte counter
**wrapped at least three times** during the recording. No stretched interval, no
counter going backwards, no bytes without packets; the largest bytes-per-packet
ratio was 43,776 — the highest seen so far, still below 64 KiB. Replayed through
`Meter`: one baseline and then 3,568 rates on every interface that was present
throughout — no wrap was judged a reset, and nothing was discarded.

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

## CPU while resident (the shipped app, not a spike)

Taken from the installed `NetMeter.app` v0.1.1 (/Applications, launched at login),
2026-09-21, Apple silicon, macOS 27, one sample each:

| What | Value |
|---|---|
| `ps -o time=` before / after a 60 s wait, panel not touched | 6:24.56 → 6:25.31 = **1.25%** of one core |
| cumulative CPU time over uptime (`ps -o etime=,time=`) | 384 s over 26 630 s = **1.44%** |

The 0.1.0 changelog's "about 0.3%" came from the first live build of 2026-09-20,
before the panel and the one-bar-a-second graph, and was not re-measured when
they landed. One machine, one run each: enough to say the old figure was wrong,
not enough to call this one a specification.

## The item's highlight and the panel's container (ADR-0004, not a spike)

The tools for this were throwaway and are not in the repository; the method is
what matters, and each step uses only public API.

- **Is the item highlighted?** Film only the item's rectangle with
  `SCStream` (`sourceRect` = the item's frame, 60 fps, cursor hidden) and judge
  each frame by the median brightness of its background: the pill behind a
  pressed or highlighted item lifts it well above the idle level, and the median
  ignores the digits and the graph. The threshold is half-way between the idle
  level and the first frame after the mouse-down. An in-process
  `isHighlighted` is not evidence: another process draws the menu bar, and
  `highlight(true)` left the value true while the screen stayed dark.
- **Where is the item?** Ask the app's own accessibility element
  (`AXExtrasMenuBar` → first child → position and size), and wait until two reads
  0.3–0.5 s apart agree: a newly launched item moves while the menu bar settles.
- **Clicks** are `CGEvent` mouse-down / mouse-up posted to `.cghidEventTap`,
  90 ms apart, at the item's centre. Put the cursor back afterwards.
- **Run the build under test beside the installed copy** with its own bundle id
  (`make build-app BUNDLE_ID=... DIST_DIR=...`), launched with `open` so that
  LaunchServices starts it, and remove its preferences domain and its
  LaunchServices registration (`lsregister -u`) afterwards.
- **Who lights the item** was found with lldb on small probe apps, opened and
  closed from code: `NSPopover.show` calls the status item's private
  `_willPresentContent:cancellationHandler:`; `MenuBarExtra` receives
  `_beginExpandedInterfaceSession:` from the menu bar. That is how "no public API
  for a panel of our own" was established — nothing of it is used by the app.
- **A pop-up menu right after launch**: launch through LaunchServices, open the
  panel, click the pop-up button (found through the accessibility tree), and read
  `NSMenu.didBeginTracking` / `didEndTracking` and `NSApplication.didBecomeActive`
  from the diagnostic build. Always run a popover control alongside: a harness
  that cannot reproduce ADR-0003's defect cannot show its absence.

Results are in ADR-0004's table. The org knowledge base has the general form
(macos-gui: "メニューバー項目の「開いている間のハイライト」は器が決める").

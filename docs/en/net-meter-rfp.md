# RFP: net-meter

> Generated: 2026-09-20
> Status: Implemented — the Amendments record what changed on the way

## 1. Problem Statement

I want to see, in the macOS menu bar and in real time, how much traffic is going up and
down the network interface I am currently using. The existing apps that can do this offer
it as one feature of an all-in-one system monitor covering CPU, memory, sensors and more,
so they bring unwanted features, resident cost and configuration complexity with them.
net-meter does exactly one thing: it shows the current traffic of one interface in the
menu bar, as numbers and a graph.

The target user is a macOS user who wants network activity always in view (first of all,
the author).

## 2. Functional Specification

### Commands / API Surface

A menu bar resident GUI app with no Dock icon. There is no CLI.

**Interface selection**

| Mode | Behaviour |
|------|-----------|
| Automatic (default) | Shows the first physical interface (Wi-Fi or wired Ethernet) in the OS preference order. VPN tunnel interfaces (`utun` and the like) are never chosen; the physical interface actually carrying the traffic underneath is shown instead. Interface changes (Wi-Fi ⇔ wired, for example) are followed automatically |
| Manual | Pick one from a list (display name plus BSD name, e.g. "Ethernet (en0)") |

- When a manually selected interface disappears (a USB adapter is unplugged, for example),
  the app shows "absent" and waits, and resumes on its own when the interface returns.
  It does not silently switch to another interface. "Absent" must look different from
  0 KB/s (no traffic).
- When automatic selection finds no physical interface at all, the same "absent" state is shown.

**Menu bar display**

| Display mode | Content |
|--------------|---------|
| Numbers + graph (default) | Two lines of numbers with the graph to their right |
| Numbers only | Two lines of numbers |
| Graph only | The graph |

- The upper line is upstream (↑) and the lower line is downstream (↓). The width is fixed
  and the digits are monospaced and right-aligned, so that neighbouring icons do not move
  every time the number of digits changes.
- The graph has its origin at the vertical centre: upstream is drawn upwards and
  downstream downwards. ~~The window is about 60 seconds.~~ (2026-09-20: changed to the last
  fourteen samples, one bar each — see Amendment A12.)
- The vertical axis is a linear auto-scale that follows the maximum within the window.
  The full scale has a floor, so that trickle traffic while idle does not fill the graph.
  Upstream and downstream share one scale.
- Monochrome is the default and follows the menu bar's light/dark appearance. A setting
  switches to separate colours for upstream and downstream.
- The update interval is fixed at 1 second.
- Visual details such as graph width, line weight and the floor value are tuned on a real
  menu bar.

**Units**

- Bytes per second (KB/s, MB/s, GB/s) by default. A setting switches to bits per second
  (kbps, Mbps, Gbps).
- Prefixes are SI (1 MB = 1000 KB), matching Finder and Activity Monitor.

**Panel (click the menu bar item)**

- History graph (fixed 3-minute window, newest at the right edge)
- Current values (up/down)
- Interface name (display name, BSD name, automatic or manual)
- Interface identity (IP addresses, link speed)
- Peak values within the history window (up/down)
- Cumulative transfer since launch (up/down), kept per interface and in memory only
- Settings: interface selection, display mode, unit, colour, launch at login
- Quit

### Input / Output

- Input: the per-interface cumulative byte counters, the interface preference order and
  types, and the interface display names that the OS exposes.
- Output: drawing in the menu bar item and the panel only. No file output, no standard
  output, no network transmission.
- History lives only in in-memory ring buffers and is never persisted.

### Configuration

- Stored in `UserDefaults`. There is no configuration file.
- Launch at login is an `SMAppService` toggle, off by default.

### External Dependencies

None. Only OS standard frameworks are used. The app itself makes no network connections.

## 3. Design Decisions

**Language and frameworks**

- Swift 6 (strict concurrency) with Swift Package Manager.
- The menu bar item is custom-drawn ~~on an AppKit `NSStatusItem`. SwiftUI's `MenuBarExtra`
  is not used because it does not suit a custom two-line layout updated every second.~~ and shown as
  the label of a SwiftUI `MenuBarExtra` (2026-09-21: Amendment A14, ADR-0004).
- The panel is SwiftUI hosted in ~~an `NSPopover`~~ ~~a non-activating `NSPanel` (2026-09-20:
  Amendment A13, ADR-0003)~~ the `MenuBarExtra`'s window (A14), with the history graph drawn by Swift
  Charts. Panel content is ~~created when the panel opens and released when it closes~~ built on the first
  open and pushed to only while the panel is open (A14).
- Supported environment: macOS 26 or later, Apple Silicon only.

**How the data is read**

- Counters are read with `sysctl` (`NET_RT_IFLIST2`), once per second, for all interfaces
  at once. Samples go into per-interface ring buffers, so real history is available
  immediately after the displayed interface changes, and cumulative transfer can be kept
  per interface.
- Deltas are always taken modulo 2^32. The result is correct whether the counter is
  truncated to 32 bits or is a true 64-bit value, as long as the increase per sample is
  below 4 GiB (see §7). At a 1-second interval this is unambiguous up to about 34 Gbps.
- A counter wrap is distinguished from a counter reset (a tunnel interface being
  re-created~~, wake from sleep~~, and so on; 2026-09-20: wake from sleep withdrawn as
  unmeasured — see Amendments A3 and A2). A sample judged to be a reset is discarded and
  the baseline is re-established. The rule (packet counters going backwards, a cap of
  link speed × elapsed time, and so on) is decided from measurements in Phase 1 and
  recorded in an ADR.
- Rates are divided by the actual elapsed time from a monotonic clock. Timers get
  coalesced, so 1 second is never assumed.
- Automatic selection takes the first interface of type Wi-Fi or wired Ethernet from the
  preference order returned by `NWPathMonitor`. The same interface is returned more than
  once, so duplicates are removed.

**Testability**

- Delta and reset detection, interface resolution, number formatting (fixed width, unit
  switching) and scale calculation are pure functions.
- The counter reader and the interface information sources are injected through protocols
  and replaced in tests.

**Relation to existing tools**

- It pairs with load-spinner (CPU/GPU load in the menu bar) and follows the same shape for
  structure, signing and distribution.

**Out of scope**

- Per-process traffic (the API it needs is private)
- Showing several interfaces in the menu bar at once
- Persisting or exporting history; monthly usage accounting
- Notifications and threshold alerts
- Speed tests, packet capture
- A CLI
- Intel Macs; macOS 25 and earlier

## 4. Development Plan

### Phase 1: Core

- Implement the reader, delta/wrap/reset detection, automatic interface resolution, number
  formatting and scale calculation, with unit tests.
- Checks on real systems (measurement scripts live in `spikes/` and are not shipped):
  - Counter behaviour on a macOS 27 machine and on the macOS 26 verification VM. Whether
    32-bit truncation happens on macOS 26 is checked by pushing more than 4 GiB of traffic
  - Automatic selection returns the physical interface while a split-tunnel VPN is connected
  - Wake from sleep, plugging and unplugging interfaces, switching Wi-Fi ⇔ wired
  - Whether the value readable as link speed is sensible for Wi-Fi
- Settle the reset detection rule and record it in an ADR.

### Phase 2: Features

- `NSStatusItem` drawing (three display modes, fixed width, monochrome/colour, the "absent" state).
- The panel (history graph, current values, interface information, peaks, cumulative transfer, settings).
- Settings persistence, launch at login~~, single-instance guard~~.
  (2026-09-20: the guard was implemented in the scaffold — see Amendment A7)
- Tune the appearance on a real menu bar (both light and dark, including a notched machine).
- Measure the resident CPU load.

### Phase 3: Release

- README (English and Japanese), AGENTS.md, CHANGELOG, ADRs.
- App icon.
- Signing, notarization, Homebrew cask, GitHub Release.
- Add as a submodule of util-series; update the org profile and the web catalogue.
- Feed reusable findings back to the knowledge repository (such as the behaviour of the
  counters visible to an unprivileged process).

Each phase can be reviewed independently. An independent verification pass runs when the
design is settled and again before release.

## 5. Required API Scopes / Permissions

None.

No TCC permission, entitlement or administrator privilege is needed. The app itself makes
no network connections. This property is a requirement to be maintained.

## 6. Series Placement

Series: util-series
Reason: A single-purpose menu bar GUI utility that takes the same shape (structure,
signing, distribution) as load-spinner in the same series. It depends on no external
service and no LLM.

## 7. External Platform Constraints

**Counter precision (measured)**

The per-interface byte counters that an unprivileged third-party process can read through
`sysctl` (`NET_RT_IFLIST2`) have 64-bit fields, but the OS alters the values before
returning them. The OS's own `netstat -ib` returns unaltered values at the same moment,
and the two were compared to confirm this. The reason for the difference is unconfirmed.

| Environment | Floored to 1 KiB | Truncated to 32 bits |
|-------------|------------------|----------------------|
| macOS 27.0 (real machine) | Yes | Yes (the value is the true value modulo 2^32) |
| macOS 26.6.2 (VM) | Yes | ~~Unconfirmed (the counters were below 4 GiB; to be checked in Phase 1)~~ Yes (confirmed 2026-09-20 — see Amendment A10) |

Consequences for the design:

- The counter wraps every 4 GiB (about every 8 minutes at 9 MB/s). "The field is 64-bit,
  so no wrap handling is needed" does not hold.
- The resolution is 1 KiB per sample. That is enough for KB/s to MB/s display, but below
  1 KB/s the value alternates between 0 and 1.0 KB/s.
- The values are the interface's whole L2 traffic, including traffic inside the LAN (to a
  NAS, for example). When the physical interface is shown during a VPN connection, the
  encapsulation overhead is included too.

**Menu bar**

- The height is about 22 pt, so two lines of numbers use a font of around 9 pt.
- On notched machines the OS hides items when their total width is too large. Being able
  to choose the width through the three display modes has practical value.
- The menu bar is tinted by the wallpaper and switches between light and dark. The
  coloured display needs a palette, settled on real hardware, that reads well in both.

**Panel**

- Popovers in an app with no Dock icon have known pitfalls around focus, automatic closing
  and layout cost while hidden. Findings from the existing tools are reviewed before
  implementation.

**Limits of the verification environment**

- The macOS 26 verification environment is a VM with only a virtual NIC; it has no Wi-Fi
  and no VPN. On macOS 26 only counter behaviour and appearance can be checked. Automatic
  interface selection and behaviour under a VPN are checked on macOS 27 hardware only.

---

## Amendments

The body stays as it was when confirmed; later additions and withdrawals are recorded
here. A withdrawn statement is struck through in the body.

### 2026-09-20 — Amendments from the independent design review

Right after scaffolding, the design was checked independently against the organization's
knowledge base and conventions. These are the results; all were settled before development
Phase 1 began.

**A1. The panel shows the version (addition to §2 Panel)**
A menu bar app has nothing like `--version`, so unless the version is on screen a user has
no way to tell which build they are running. The panel shows it verbatim (no prefix or
suffix stripped) and selectable for copying. When the panel replaces the scaffold's menu,
the version must not lose its place.

**A2. A sample whose elapsed time is too long is discarded unconditionally (addition to §3 How the data is read)**
"Correct as long as the increase per sample is below 4 GiB" assumes a bounded sampling
interval. When a sleep or a stalled timer stretches the interval, the delta modulo 2^32 is
no longer unambiguous. A sample whose elapsed time exceeds a threshold is discarded and the
baseline re-established, whatever the counters say. Elapsed time is measured with a clock
that keeps running while the Mac sleeps; with a clock that stops, a sleep hides inside an
interval of ordinary length. The threshold is set in Phase 1.

**A3. "A wake from sleep resets the counters" is unmeasured (correction to §3)**
The body listed wake from sleep as an example of a reset, but it was never measured. What a
wake does to the counters is a Phase 1 verification item and is treated as a hypothesis
until then. With A2 in place, the sample after a wake is re-baselined whatever the actual
behaviour turns out to be.

**A4. First find out whether the values the reset rule needs can be read (addition to §4 Phase 1)**
The values the candidate rules rely on (packet counters, link speed) have not yet been read
from an unprivileged process. The OS alters the byte counters before returning them, so
these cannot be assumed to come through untouched. A spike reads them at the start of
Phase 1. A link-speed cap alone is not enough: assuming the delta after a reset is spread
evenly over 4 GiB, a 10GbE cap (1.25 GB per second) accepts roughly three in ten as a
normal increase.

**A5. The menu bar drawing approach is decided in an ADR at the start of Phase 2 (addition to §3)**
A template image follows the menu bar's light/dark appearance but cannot carry colour. With
templating turned off for the coloured mode, the given colours are baked in and nothing
follows the appearance any more, the digits included. The monochrome default and the
coloured mode therefore cannot share one naive drawing path. An ADR decides the approach
(a template image, a title string combined with an image, or a subview that resolves the
appearance itself); the renderer is a pure "values → image" function, and both appearances
are checked offscreen.

**A6. The automatic-selection rule is unmeasured under a VPN and is revisited if it fails (supplement to Discussion Log 3)**
"Take the first Wi-Fi or wired Ethernet interface in preference order" was decided without
ever looking at the list during a VPN connection. If the tunnel interface does not appear
with type `other`, or the physical interface drops out of the list, the decision is
revisited in an ADR. "The same interface is returned more than once" was observed in both
of two runs (macOS 27.0, wired first, no VPN: `en0` twice, then Wi-Fi).

**A7. The single-instance guard was implemented in the scaffold (correction to §4 Phase 2)**
The guard covers the assembled `.app` only. A bare `swift run` binary has no bundle
identifier and starts next to a running `.app` (measured).

**A8. A manually selected interface stays in the panel's selection while it is absent (addition to §2)**
Removing an absent interface from the list would look as if the user's choice had been
silently dropped. The selection stays, shown as absent.

**A9. Feeding the knowledge base is not saved up for Phase 3 (correction to §4 Phase 3)**
The organization's conventions require reusable findings to be fed back as part of the work
that produced them, not deferred. A finding is fed back once it is settled; Phase 3 only
confirms that nothing was missed.

**A10. Results of the Phase 1 measurements (additions to the table in §7 and to §3)**
Truncation to 32 bits was confirmed on macOS 26.6.2 as well (after pushing 4.5 GB in, a true
value of 5,438,231,389 was read as 1,143,263,232). Packet counters arrive unaltered on both
OS versions. The value readable as link speed is not a ceiling (one interface reported
100 Mbps while carrying 2.3 Gbps, another reported 0) and is not used to accept or reject a
sample. The rules, including the wrap-versus-reset distinction, are set out in
[ADR-0001](adr/0001-counter-readings-to-rates.md).

**A11. Automatic selection measured under a split-tunnel VPN (the outcome of A6)**
While the VPN was connected, the tunnel interface (`utun6`) joined the preference order **at
the end** with type `other`, and the physical interfaces stayed at the front (macOS 27.0,
once). The rule "take the first Wi-Fi or wired Ethernet interface" returns the physical
interface, and the decision stands. A VPN that routes all traffic through the tunnel has
not been measured and may order the list differently — the rule depends only on the
tunnel's type, not its position, so the result is the same as long as the physical interface
stays in the list. The 385 samples of real traffic recorded from before the connection to
after the disconnection were also fed through `Meter`: no sample was misjudged as a reset
and none was discarded. A wake from sleep, an adapter being unplugged and a switch between
Wi-Fi and wired remain unmeasured.

**A12. One bar of the menu bar graph is one sample (correction to §2 Menu bar display)**
The body said "the window is about 60 seconds". When the bars were made wider on real
hardware (2 pt with a 1 pt gap), each bar became a five-second time bucket to keep that
minute — and the user reported that although the graph should be moving from right to left,
its segments changed oddly as time passed. Drawn as a second-by-second filmstrip, the graph
stood still for about five seconds and then jumped by a whole bar, and in between only the
rightmost bar kept changing height. Bars are no longer cut by time: **the last fourteen
samples are drawn one bar each**. The graph moves left by exactly one bar every second and a
bar never changes once drawn. The window becomes about fourteen seconds; the longer view is
the panel's three-minute chart. With it, the vertical auto-scale now **grows at once and comes
down by 20% per sample**, so that the remaining bars do not all jump taller in the instant a
peak leaves the window.

### 2026-09-20 — Amendment after the first release

**A13. The panel lives in a non-activating `NSPanel`, not an `NSPopover` (correction to §3; ADR-0003)**
After the first release the user reported that, only the first time after launch, the panel's
drop-down did not expand and something redrew. The first release had closed a related problem —
the first click inside the panel activates the app, and the activation ends the menu's tracking —
by activating the app when the panel opens. Recorded with the signed bundle launched through
LaunchServices, that request was refused by the OS right after launch, the first click then
activated the app, and the menu ended after 71 ms. macOS 14 and later refuse activation for up
to about 30 seconds after launch. The checks made during development (nine out of nine) used a
build started from a terminal and never met this condition.
The panel now lives in an `NSPanel` with `.nonactivatingPanel`, and the app never asks to be
activated. Under the same condition (the first click, 21.8 s after launch) the menu stayed open
for 1,906 ms and no activation happened at all (one run). The popover's arrow is gone; the panel
appears directly below the item. The full decision, the rejected alternatives and the prior
implementations are in ADR-0003.

### 2026-09-21 — Amendment after a report on the item's highlight

**A14. The item and the panel are a SwiftUI `MenuBarExtra` window (correction to §3; supersedes A13's
container; ADR-0004)**
The user noticed that while the panel was open the item was not shown pressed, as other menu bar
items are, and that apps built on `MenuBarExtra` did show it. Measured on macOS 27.0: the menu bar
keeps that highlight only for `NSPopover` and `MenuBarExtra`, each through private machinery inside
the framework; no public API lights it for a panel of our own, and this project does not use private
API. A13's reason for leaving the popover was checked against `MenuBarExtra` and did not apply: a
pop-up menu opened right after a LaunchServices launch stayed open (3 of 3), where a popover ended
it 88–97 ms in (2 of 2). §3's reason for not using `MenuBarExtra` was checked too and did not hold:
net-meter's own two-line image shows as its label and updates once a second. The verification — the
highlight, the menus, the ways of closing that were tried, the label's appearance, CPU while closed — is
recorded in ADR-0004, with what it did not cover: switching to another app with the keyboard now leaves
the panel open until the next click.

---

## Discussion Log

1. **Feasibility check (2026-09-20)** — A Swift spike of about 60 lines confirmed on a
   macOS 27 machine that the primary interface, the interface display names and the byte
   counters can all be read without any permission. It also revealed that the counters
   visible to an unprivileged process are truncated to 32 bits and floored to 1 KiB
   (compared against `netstat` readings taken immediately before and after).
2. **Tool name** — `net-meter`. The `-lens` family consists of tools that accumulate and
   analyse history, which differs in character from this instantaneous display with no
   accumulation, so that suffix was not adopted. Other candidates were `netif-meter`,
   `net-pulse` and `net-lens`.
3. **Automatic selection during a VPN connection** — Decided to prefer the physical
   interface. Following the OS primary (`utun`) was rejected because traffic outside the
   tunnel becomes invisible in a split-tunnel setup. A switchable setting was rejected
   because it adds a setting and more to verify. Pinning a `utun` manually is fragile
   because its number can change on every connection. A further spike confirmed that
   `NWPathMonitor` returns interfaces in preference order with their types (and returns
   the same interface more than once). Behaviour during a VPN connection is unconfirmed
   and became a Phase 1 verification item (a split-tunnel VPN environment is available).
4. **Units** — Bytes per second by default, switchable to bits per second.
5. **Disappearance of a manually selected interface** — Show "absent" and wait. Switching
   to automatic selection while the interface is gone was rejected because numbers from a
   different interface would appear under what the user believes is their manual choice.
6. **CLI** — None. Bundling a diagnostic `doctor` subcommand was not adopted. Checks on
   real systems use the measurement scripts in `spikes/`.
7. **Graph** — Origin at the centre, upstream upwards and downstream downwards (specified
   by the user). Overlaying both series in one frame was rejected because colour would be
   the only way to tell them apart. The vertical axis is a linear auto-scale with a floor;
   a fixed logarithmic range and a scale fixed to the link speed were not adopted.
8. **Colour** — Monochrome by default, switchable to colour.
9. **UI on click** — A panel (popover). A menu-only design was considered, but being able
   to see the history graph and interface information took priority. In addition to the
   basic layout, the panel carries the interface identity (IP addresses, link speed), peak
   values and cumulative transfer since launch.
10. **Minimum OS** — macOS 26 or later. The original plan was to check macOS 26 on a real
    test machine, but that machine turned out to have been upgraded to macOS 27, so a
    macOS 26.6.2 VM was prepared as the verification environment. Flooring to 1 KiB was
    confirmed on this VM. Confirming 32-bit truncation was deferred to Phase 1.
11. **Provisional decisions (conventional defaults, no objection raised)** — A fixed
    1-second update interval, SI prefixes, settings in `UserDefaults`, launch at login off
    by default, a shared scale for upstream and downstream, a menu bar graph window of
    about 60 seconds, a fixed 3-minute history window in the panel, Apple Silicon only.

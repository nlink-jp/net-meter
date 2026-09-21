# Changelog

All notable changes to net-meter are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

### Documentation

- ADR-0004 records the 0.2.0 release build on macOS 26, the minimum: the panel
  works and the item stays highlighted while it is open (hand check). It was the
  first item on the "not measured" list.

## [0.2.0] - 2026-09-21

### Changed

- **The menu bar item now stays highlighted while the panel is open**, like every
  other menu bar item. It used to lose the highlight the moment the mouse button
  came up. macOS 27 keeps that highlight only for the panels it provides itself,
  so the item and the panel are now a SwiftUI `MenuBarExtra` window
  ([ADR-0004](docs/en/adr/0004-menubarextra-panel.md)). What the panel shows is
  unchanged. It still opens below the item without switching you away from the
  app you are working in, the settings' pop-up menus work from the first click
  after launch, and Esc, a click outside the panel or a click on the item closes
  it. Two things behave differently:
  - Switching to another app with the keyboard (⌘Tab) leaves the panel open until
    your next click; before, it closed.
  - ⌘C now copies a selected address or version. ⌘Q does nothing while the panel
    is open, as before; use the panel's Quit button.
- VoiceOver reads the item as one name, "net-meter, Up …, down …", where it
  used to read the name and the rates separately: the new item passes a name on
  and drops a separate value.

### Documentation

- **The CPU figure was wrong by about four times.** 0.1.0's notes say "about 0.3%
  CPU while resident". That was measured on the day's first build, before the
  panel and the second-by-second graph existed, and was never re-taken. The
  shipped 0.1.1, left running from /Applications on an M-series Mac: 1.25% of one
  core over a 60-second sample (`ps` cumulative CPU time, panel not touched), and
  1.44% averaged over the 7 h 24 min it had been up. The figure is recorded in
  `spikes/README.md` with how it was taken, which the 0.3% never was.
- `AGENTS.md` described the menu bar graph as "the last minute"; it is fourteen
  seconds, as the READMEs say.

## [0.1.1] - 2026-09-20

### Fixed

- The first time the panel was opened after launch, its pop-up menus closed the
  moment they opened. The panel asked macOS to activate the app when it opened;
  right after launch macOS refuses that, so the first click inside the panel
  activated the app instead and the activation ended the menu (71 ms after it
  began, measured). The panel is now a non-activating panel and the app never
  asks to be activated: the menus work from the first click, and opening the
  panel no longer makes net-meter the active app (ADR-0003).

### Changed

- The panel appears directly below the menu bar item, without the popover's
  arrow, is kept within the screen, and follows the item when the item moves or
  changes width. Esc closes it, and so does another app
  coming to the front or a change of Space. While it is open the keyboard
  belongs to the panel.

## [0.1.0] - 2026-09-20

### Added

- The menu bar item: the upstream and downstream rate of one network interface
  as two lines of numbers with solid arrows, and a mirrored graph of the last
  fourteen seconds, one bar per second moving left as time passes — upstream
  above the centre line, downstream below it. The scale grows at once and comes
  down gradually, so bars already drawn do not all jump when a peak scrolls out. Its width depends on the display mode alone, so neighbouring items do
  not move when the digits or the unit change. Monochrome as a template image,
  so it takes the menu bar's own colour like the system's items; or coloured,
  with a foreground chosen from the menu bar the item reports (ADR-0002). Drawn
  pixel-aligned for 1x and 2x displays. A second without a value is a dash, never
  a zero; an interface that is not there dims the whole item.
- The panel behind it: a three-minute history chart with a fixed window and one
  scale for both directions, the interface's addresses and reported link speed,
  peaks, totals since launch, every setting, launch at login, and the version —
  selectable, at the bottom. Its content exists only while it is open. Outside
  clicks close it even where macOS's own transient behaviour misses them; clicking
  the item again closes it and clicking once more opens it, however fast the
  clicks come; its pop-up menus open and stay open on the very first click, and
  what is chosen in them takes effect; and a failed attempt to change launch at
  login is reported where the toggle is.
- Interface selection: automatic — the first physical link in macOS's preference
  order, which keeps showing the link itself while a VPN is up (measured with a
  split tunnel) — or any interface by hand. A manual choice that is absent is
  shown as absent and stays in the list; another interface is never shown in its
  place.
- Display modes (numbers and graph, numbers only, graph only), bytes or bits per
  second with SI prefixes, colour on or off. Settings are saved in UserDefaults
  and take effect at once.
- The rule that turns two counter readings into a rate, or into the reason there
  is none (ADR-0001). macOS hands an ordinary app byte counters truncated to 32
  bits and floored to 1 KiB, in 64-bit fields (measured on macOS 26 and 27), so
  deltas are taken modulo 2^32; samples after a stretched interval — a sleep —
  are discarded unseen; a counter reset is told from a wrap by the packet
  counters, not by the reported link speed, which was measured not to be a
  ceiling. An hour of recorded use with at least three real wraps replayed
  without one sample misjudged.
- No permission of any kind: no privacy grant, no entitlement, no administrator
  rights, and no network connection of its own. About 0.3% CPU while resident —
  measured before the panel and the graph existed; the shipped app measures
  about 1.3% (see 0.2.0).
- A single-instance guard, so a second copy exits instead of stacking a second
  menu bar item.
- `make test` checks the documents as well as the code: relative links resolve,
  every English document has its Japanese mirror, each pair names the same
  identifiers, no withdrawn name is still in use, and every UI string is used.

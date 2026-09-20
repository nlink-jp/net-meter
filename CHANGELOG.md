# Changelog

All notable changes to net-meter are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [Unreleased]

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
  arrow, and is kept within the screen. Esc closes it, and so does another app
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
  rights, and no network connection of its own. About 0.3% CPU while resident.
- A single-instance guard, so a second copy exits instead of stacking a second
  menu bar item.
- `make test` checks the documents as well as the code: relative links resolve,
  every English document has its Japanese mirror, each pair names the same
  identifiers, no withdrawn name is still in use, and every UI string is used.

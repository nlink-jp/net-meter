# ADR-0004: The panel moves to a SwiftUI MenuBarExtra window

| Field | Value |
|-------|-------|
| Status | **Accepted** |
| Date | 2026-09-21 |
| Binds | net-meter |
| Supersedes | ADR-0003 decisions 1, 3, 4, 5 and 6 and part of 7 (the container, and what came with owning it); ADR-0002 decisions 1 and 2 in part (where the image goes and where the coloured finish reads the appearance) |
| Decision makers | nlink-jp maintainers |
| Triggered by | A user report: "looking closely, the icon's highlight blinks or is gone when the panel opens" — for net-meter, load-spinner and task-clock-gui, and for none of the MenuBarExtra apps. (load-spinner is a popover app; its blink was a `show` slow enough to outlast the release, fixed there.) |

## Context

Measured on macOS 27.0 on 2026-09-21, filming only the item's rectangle at 60 fps:

- With the non-activating `NSPanel`, the item is highlighted while the button is held, goes dark at the
  release, and stays dark while the panel is open (5 of 5).
- The open-panel highlight is kept by `NSPopover` and by SwiftUI's `MenuBarExtra`, each through private
  AppKit machinery inside the framework (callers traced with lldb). `NSButton.highlight(_:)` and
  `isHighlighted` do not reach the screen: five timings, three tries each, all dark.
- The private call a popover makes also lights the item when made for a panel. It is not an option:
  this project does not use private API.
- ADR-0003 left `NSPopover` because the first click inside the panel activates the app and ends the
  pop-up menu it opened. The same test, right after a LaunchServices launch: a popover control closed
  its menu 88–97 ms in, followed by activation (2 of 2, matching ADR-0003's 78 ms); a `MenuBarExtra`
  window kept its menu open until the closing click and the app never activated (3 of 3).
- net-meter's own item image — coloured and template — shows unchanged as a `MenuBarExtra` label and
  updates once a second (filmed, both finishes).

## Decision

1. The panel is a `MenuBarExtra` with `.menuBarExtraStyle(.window)`; its content is `PanelView`. The app
   becomes a SwiftUI `App`. The item's label is `Image(nsImage:)` of `StatusRenderer.image(...)`, which
   stays the one drawing function (ADR-0002).
2. What owning the window required goes: the panel's own window type, the placement function, the click
   monitors and the order-matched toggle, and the Space / other-app observers — provided the verification
   below shows SwiftUI covers each case. Anything it does not cover is kept, not re-invented. One case is
   not covered and cannot be kept: another app coming forward without a click (⌘Tab) leaves the
   `MenuBarExtra` window open, and there is no public way to close it from code. That is accepted
   (see Consequences).
3. Kept: the meter, `MeterController`, `StatusRenderer`, the panel's model and view (less the size
   report the old window was placed from), `PanelUpdateGate` (a refresh still must not land while a menu in the panel is open), the single-instance
   guard, the login item, and the rule that the app asks for no permission and opens no connection.

## Verification before release

On the release build, with synthetic clicks and filming as in the Context:

- the highlight holds while open and goes when closed (5 cycles);
- a pop-up menu opened right after a LaunchServices launch stays open (3 launches);
- each way of closing: an outside click, a click on the item, Esc, another app coming forward, a Space
  change;
- the panel does no SwiftUI work while closed (ADR-0003 decision 7), measured, not assumed;
- both label finishes, the unit and mode changes, and the item's width change while the panel is open;
- a maintainer's hand check before the release.

## Verification results (2026-09-21, macOS 27.0)

Taken on a release-shaped build with the recorder compiled in and its own bundle id, beside the installed
v0.1.1; a clean build of the same source for the hand check.

| Check | Result |
|---|---|
| Highlight while open, 5 open/close cycles, filmed | held every time, no dark frame; gone after each close |
| Pop-up menu right after a LaunchServices launch | stayed open until the next click, 3 launches of 3; the app never became frontmost |
| Click on an empty stretch of the menu bar | closed the panel |
| Click on another app's window | closed the panel |
| Click on the item | closed the panel (5 of 5) |
| Esc | closed the panel (hand check) |
| Another app coming forward without a click (launched, becoming frontmost) | the panel stayed open (1 of 1); it closed at the next click on the item |
| Display mode changed with the panel open | the item resized and the window followed (hand check) |
| Label, template and coloured | both drawn and updated once a second (filmed) |
| The label's appearance | system `Aqua`, menu bar `VibrantDark`: `colorScheme` read `dark` — it follows the menu bar. At launch the item's window went from `VibrantLight` to `VibrantDark` and `colorScheme` followed within 48 ms |
| Assistive software | the label's accessibility label arrives as the item's AXTitle and an accessibility value is dropped, so the rates are in the title: "net-meter, Up 0 KB/s, down 1 KB/s" (read from the AX element) |
| Work while closed | the content is built once, on the first open, and kept; CPU over 30 s matched v0.1.1: 0.43 s vs 0.42 s before any open, 0.48 s vs 0.49 s after use |
| Copy from an address's context menu, overall look | fine (hand check) |
| Keyboard | SwiftUI installs a main menu: ⌘C copies a selected address (hand check), and ⌘Q quit net-meter while the panel had the keyboard (hand check) — so the termination command is replaced with nothing: the menu has no Quit item (read from the app's AX menu bar) and ⌘Q no longer quits (hand check). ⌘H and ⌘W stay; not measured |
| macOS 26 (the verification VM), the 0.2.0 build from GitHub Releases | the panel worked and the item stayed highlighted while it was open (hand check, 2026-09-22) |

Not measured: a Space change; a unit change with the panel open; the menu bar's appearance changing while the app runs; opening over a full-screen app; a right-click outside the panel; content taller than the visible frame (the 566 pt limit was measured on the old window).

## Consequences

- The item looks like every other menu bar item while its panel is open.
- Placement, material and closing become SwiftUI's. net-meter can no longer correct them itself; a case
  SwiftUI handles badly would need a new decision, not a patch.
- There is no public way to close a `MenuBarExtra` window from code. Quit still works; nothing else in
  the panel needs to close it. Switching to another app with the keyboard therefore leaves the panel open
  until the next click, which v0.1.1 did not.
- The known limitation is carried over unmeasured: content taller than the screen's visible area was cut
  off in the old window.

## Alternatives considered

- **Keep the panel and record the missing highlight as a known limitation.** The fallback if the
  verification fails.
- **Call the popover's private presentation methods for the panel.** Works (3 of 3, no blink); rejected —
  no private API.
- **Return to `NSPopover`.** Keeps the highlight but brings back ADR-0003's defect, reproduced 2 of 2.

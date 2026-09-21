# ADR-0003: The panel lives in a non-activating NSPanel, not an NSPopover

| Field | Value |
|-------|-------|
| Status | **Accepted**; decisions 1, 3, 4, 5 and 6 superseded by [ADR-0004](0004-menubarextra-panel.md) |
| Date | 2026-09-20 |
| Binds | net-meter |
| Decision makers | nlink-jp maintainers |
| Triggered by | A report after the first release: "only the first time after launch, the panel's drop-down does not expand and something redraws" |

## Context

The panel has pop-up buttons (interface, display, unit). The first release hosted it in an
`NSPopover`, as RFP §3 said, and called `makeKey()` right after showing it.

`makeKey()` makes the popover key but leaves the accessory app inactive. So the first click
inside the panel activates the app, and that notification arrives while the menu the click
just opened is tracking and ends the tracking (measured: the menu ended 78 ms after it began).

The first release closed this by activating the app when the panel opens. In a debug build
started from a terminal, activation completed 12–39 ms after the panel appeared, nine times
out of nine, and the problem seemed gone.

After the release, measured again with the signed bundle launched through LaunchServices,
**the very first activation request after launch was not honoured**. After the request the
frontmost app was still the previous one, no `didBecomeActive` arrived, and the first click
then activated the app and ended the menu after 71 ms (once, reproduced on request). Focus
stealing prevention in macOS 14 and later refuses activation for up to about 30 seconds after
launch — a fact already recorded in the organization's knowledge base, and not looked up when
activation was adopted. On macOS 27 another process receives the click on a status item, so
from the OS's point of view the request is not tied to anything the user did. The build
started from a terminal probably got through because it was a child of the frontmost app.

## Decision

1. The panel is hosted in an **`NSPanel` with `.nonactivatingPanel`**. A click inside it does
   not activate the app, so nothing interrupts menu tracking. The app never asks for activation.
2. The first release's "activate on open, hand activation back on close" is removed. What is
   never taken does not have to be given back.
3. The panel can become key (`canBecomeKey`) but never main. `hidesOnDeactivate` is not used.
   It is shown without animation, and whether it is open is a boolean of the app's own, not
   the window's `isVisible`.
4. It sits directly below the status item, centred on it and kept within the screen's visible
   frame. The placement is a pure function. It is placed again when the item's width or the
   panel's height changes.
5. Its material is always drawn in the active state. The app stays inactive, so a material
   that follows the window's state would look sunken.
6. There is one way to close it. Outside clicks (global + local monitors), a re-click on the
   item and Esc all go through it, and it always removes the monitors and releases the content.
7. Content built on open and released on close, refreshes held while a menu is tracking, item
   clicks and actions matched by order — none of that changes with the host.

## Consequences

- The menus work from the first click, even right after launch. The app no longer takes focus
  from whatever the user was working in.
- The popover's arrow is gone. Sitting directly below the item is what shows the connection.
- Position, size and material are now the app's to manage; the popover did that implicitly.
- Copying with the keyboard (⌘C) does not work, because there is no main menu. That is
  unchanged from the first release; selecting an address or the version and copying from the
  context menu works.

## Alternatives considered

- **Stay with `NSPopover` and activate on open** (the first release). Rejected. Right after
  launch the request is refused, and there is nothing to do when it is. When it does succeed it
  takes focus from another app and needs code to give it back.
- **Activate once at launch.** Rejected. With launch at login it takes focus from the app the
  user is working in, and right after launch is exactly when requests are refused.
- **Re-open the first menu when it closes early.** Rejected. It replays the user's click with a
  synthesized event and treats the symptom, not the cause.
- **Replace the pop-up buttons with segmented controls or radio buttons.** Rejected. The
  interface list has an open-ended number of entries and fits nothing but a menu.

## Amendments

### 2026-09-20 — from the independent review before the release

- **"No longer takes focus" was imprecise.** What the app never takes is *activation*: the
  frontmost app does not change (measured). The panel does take key status while it is open,
  so keystrokes go to the panel until it closes — that is what makes Esc work. The README and
  the changelog say it this way.
- **Decision 6 listed three ways to close; there are five.** Going elsewhere does not always
  involve a mouse-down: another app comes to the front (Cmd-Tab), or the Space changes. A
  popover closed itself then; a non-activating panel is told nothing, and after a Space change
  it stayed open out of sight, so that the next click on the item closed a panel nobody could
  see. Both now go down the same close path.
- **"Always removes the monitors" was overstated.** The close path brings the monitors in
  line: they stay until the action of a closing click on the item has been dealt with.
- **Known limitation, not handled:** content taller than the screen's visible frame (under
  about 566 pt) is clipped at the top and the bottom. It needs a scrolling design.
- **Not measured with the new panel:** copying an address from the context menu.

### 2026-09-21 — the container is superseded by ADR-0004

A user noticed that, with the panel open, the item was not shown pressed as other menu bar items are.
Measured on macOS 27.0: the menu bar keeps that highlight only for `NSPopover` and `MenuBarExtra`, through
private machinery, and no public API lights it for a panel of our own. The panel moved to a `MenuBarExtra`
window. This decision's reason still stands for `NSPopover` — a probe reproduced the menu ended by the first
click after launch, 88–97 ms in (2 of 2) — but not for `MenuBarExtra`, where the same menu stayed open
(3 of 3). Decisions 1, 3, 4, 5 and 6 are superseded; decision 2 (the app never asks to be activated) still
holds; of decision 7, the content is now built once and kept, pushed to only while open, the update gate
stays, and the click-and-action matching went with the window.

## References

- Org knowledge base, macos-gui: "two pitfalls of a menu bar NSPanel" (pitfall 2: activation
  refused right after launch)
- Prior implementations: `AppController` in task-clock-gui and instant-translate
- RFP §3, Amendment A13

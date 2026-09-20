# ADR-0002: Menu bar drawing — one pure "values → image" function with two finishes

| Field | Value |
|-------|-------|
| Status | **Accepted** |
| Date | 2026-09-20 |
| Binds | net-meter |
| Decision makers | nlink-jp maintainers |
| Triggered by | RFP Amendment A5. The monochrome default (following the menu bar's appearance) and the coloured mode cannot share one naive drawing path |

## Context

The menu bar shows two lines of numbers and a graph, at a fixed width, redrawn every second.
Monochrome is the default; a setting colours upstream and downstream separately (RFP §2).

- A template image (`isTemplate = true`) is recoloured by the OS to suit the menu bar's
  light/dark appearance, the wallpaper tint and the pressed highlight — but it cannot carry
  colour. And `isTemplate` is honoured only for an image placed in `NSStatusItem.button.image`,
  not for one embedded in a title string (org knowledge base: "put the menu bar icon in
  `button.image`").
- Without templating, the given colours are baked in and nothing follows the appearance any
  more, the digits included.

Measured (`spikes/status_appearance.swift`, macOS 27.0, once): with the system in light mode
and the app's appearance Aqua, the status item button's `effectiveAppearance` was
`VibrantDark`. The button reports **the menu bar's own appearance** (dark under a dark
wallpaper), not the system's. The same run showed a button height of 22 pt and a display
scale of 1x (non-Retina).

## Decision

1. Drawing is **one pure function from "values to show + finish" to an image**, and the
   result goes in `button.image`. No title string, no subview.
2. There are two finishes.
   - **Monochrome (default)**: everything is drawn in black, with alpha for shades, and
     `isTemplate = true`. The OS picks the colour, so the item matches the system's own items
     exactly and the pressed highlight is the OS's business.
   - **Coloured**: `isTemplate = false`. The foreground of the digits and the baseline is
     chosen from whether **the button's `effectiveAppearance`** is dark or light; the
     upstream and downstream colours come in one pair for a dark menu bar and one for a light one.
3. The per-second redraw also picks up appearance changes. There is no observer just for them.
4. Drawing happens at the real display scale, with lines and bars aligned to pixel
   boundaries. 1x displays exist.
5. The width never depends on the values. The number field always reserves
   `RateFormatter.numberWidth` characters and the unit field the longest unit; only the
   display mode (numbers + graph / numbers only / graph only) changes the width.
6. States without a value (absent, just started, a discarded sample) are drawn by the same
   function. "Absent" dims the whole item, so it cannot be mistaken for 0 KB/s.

## Consequences

- In the coloured mode the digits do not match the colour the OS gives a template exactly.
  Accepted: coloured is a mode the user opts into, and the monochrome default is unaffected.
- Because drawing is a pure function, the combinations of appearance × scale × display mode ×
  state can be checked offscreen without launching the app: the width does not change with
  the values, monochrome produces no colour, upstream is drawn above the centre and
  downstream below it.
- An appearance change reaches the display up to one second late.
- "The button reports the menu bar's appearance" rests on one observation. Confirming it
  under a light menu bar, and the coloured palette itself, are settled during Phase 2's
  tuning on real hardware.

## Alternatives considered

- **Coloured images embedded in an attributed title** (what status-lens does). Rejected. A
  fixed two-line layout with a graph does not fit text flow, and the monochrome default would
  lose the benefit of templating.
- **A layer-backed subview on the button** (what load-spinner does). Rejected. Even the
  monochrome default would have to resolve its own colours and would not match the system's
  items. load-spinner draws a fixed accent colour, so it never had this problem.
- **A template image for the monochrome parts with a subview overlaid for the coloured
  parts.** Rejected. Two drawing surfaces need aligning, and the advantage of checking one
  pure function is lost.
- **Observe appearance changes with KVO and redraw at once.** Deferred. The per-second redraw
  is enough.

## References

- RFP §2 "Menu bar display", Amendment A5
- `spikes/status_appearance.swift`
- Org knowledge base, macos-gui: "put the menu bar icon in `button.image`"

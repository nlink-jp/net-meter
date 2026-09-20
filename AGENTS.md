# AGENTS.md — net-meter

## Summary

macOS menu bar app (util-series) that shows the current upstream/downstream rate
of one network interface, as numbers and a graph. Swift 6 (strict concurrency),
Swift Package Manager, AppKit `NSStatusItem` + a SwiftUI popover, macOS 26+,
Apple Silicon. GUI only — there is no CLI. Bundle id `jp.nlink.net-meter`;
the app bundle is `NetMeter.app`, the repository and the cask are `net-meter`.

**Scaffold stage.** The app starts, guards against a second instance, and shows a
placeholder status item whose menu carries the version and Quit. Nothing reads a
network counter yet. The plan is in the RFP: development Phase 1 is the pure core
plus the checks on real systems, Phase 2 the drawing and the panel, Phase 3 the
release.

## Build & test

- `make build` — compiles the release binary. **Never** run `swift build` for a
  deliverable; the Makefile owns the output location and pins the linked SDK.
- `make build-app` — assembles `dist/NetMeter.app` (Info.plist version from
  `git describe`) and signs it with a Developer ID Application identity.
- `make package` — build-app, then notarize + staple (`nlink-jp-notary` keychain
  profile), and zip to `dist/net-meter-<version>-darwin-arm64.zip`.
- `make verify-release` — gate: `.notarized` marker, `stapler validate`, and the
  linked SDK (run before upload).
- `make brew` — generate the Homebrew cask from the built zip into the local
  `nlink-jp/homebrew-tap` checkout (see `scripts/release-brew.mk`).
- `make test` — `swift test`, then `scripts/test_check_docs.py` and
  `scripts/check_docs.py`.
- `make run` — `swift run` (debug). Quit a running copy first; the single-instance
  guard makes a second one exit.

## Structure

```
Sources/
  NetMeterCore/          Pure, testable logic (no AppKit UI)
    SingleInstance.swift   singleInstanceDecision() — startup duplicate guard (pids in, decision out)
    AppVersion.swift       displayVersion(bundleShortVersion:) — what the user is shown, "dev" outside a bundle
  NetMeter/              Executable (AppKit; SwiftUI arrives with the panel)
    Main.swift             @main enum; single-instance guard, then the accessory-policy app
    AppDelegate.swift      Scaffold shell: placeholder NSStatusItem + version/Quit menu
Tests/NetMeterCoreTests/
scripts/
  codesign-darwin-app.sh notarize-darwin-app.sh gen-brew.sh release-brew.mk cask.rb.tmpl
                         Vendored byte-identical from nlink-jp/.github/templates — never edit here
  make-icns.sh           1024px PNG -> AppIcon.icns
  check_docs.py          Links resolve, en/ja mirrors are paired, no retired name in use
  test_check_docs.py     Shows each of those rules failing on a fixture tree
spikes/                  Measurement code the design rests on. Not part of the package, never shipped
docs/{en,ja}/            RFP; ADRs go in docs/{en,ja}/adr/ (4-digit number + slug)
assets/                  AppIcon-1024.png goes here (absent: the app builds without an icon)
Info.plist               Bundle template at the repo root (${VERSION}, ${BUNDLE_ID}, ${APP_NAME} substituted by `make build-app`)
```

## Non-negotiable rules

- **No permission, no entitlement, no network connection of its own.** No TCC
  grant, no administrator right, Hardened Runtime alone. This is a requirement to
  be maintained, not a current accident — do not add a grant without a deliberate
  scope decision.
- **A byte counter's delta is always taken modulo 2^32.** The `if_data64` fields
  are 64 bits wide, but an unprivileged process is handed the true value modulo
  2^32, floored to 1 KiB (measured on macOS 27; the flooring also on macOS 26).
  Differencing modulo 2^32 is correct in both regimes as long as one sample's
  increase stays below 4 GiB. "The field is 64-bit, so no wrap handling is
  needed" is false.
- **A wrap is not a reset.** A tunnel interface being re-created or a wake from
  sleep restarts the counters. A sample judged to be a reset is discarded and the
  baseline re-established; it must never surface as a multi-gigabyte spike. The
  rule itself is decided from Phase 1 measurements and recorded in an ADR.
- **Rates divide by measured elapsed time** from a monotonic clock. Timers get
  coalesced; never assume the interval was 1 second.
- **"Absent" is a state, not zero.** A selected interface that is gone is shown as
  absent, and the app never silently shows a different interface's numbers under
  a manual selection.
- **The release build pins the linked SDK.** macOS decides which generation of
  window chrome to draw from `LC_BUILD_VERSION`'s sdk field, and the Xcode 27 /
  Swift 6.4 `swift build` stamps it with the deployment target, not the SDK it
  compiled against. `make build` passes `-platform_version macos $(MACOS_MIN)
  $(MACOS_SDK)` (the minimum read from Package.swift, so it is stated once), and
  `make verify-release` fails if the built bundle's sdk is not the current one.
  Signing, notarization and every test pass either way, so the gate is the only
  thing that can catch it.
- **Tests are mandatory.** Logic goes in `NetMeterCore` as pure functions or
  behind injected protocols, so it can be tested without a network interface. The
  AppKit/SwiftUI layer stays thin.
- **Docs in sync.** `README.md` and `README.ja.md`, and every `docs/en` /
  `docs/ja` pair, change in the same commit. Withdrawing a mechanism adds its
  name to `RETIRED` in `scripts/check_docs.py` in that same commit.

## Gotchas

Known before any of the code they constrain is written — each of these cost a
sibling app a defect.

- **The sampling timer must be registered in `.common` run loop mode.**
  `Timer.scheduledTimer` registers in `.default` only, and the run loop leaves
  that mode while a menu or popover is tracking — the display would freeze
  exactly while the user is looking at it. Use the target/selector `Timer` API
  (a `@Sendable` closure trips Swift 6 capture checks) and
  `RunLoop.main.add(_:forMode: .common)`.
- **App Nap freezes a background timer in an `LSUIElement` app.** The numbers are
  right after launch and stale hours later. Hold a
  `ProcessInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep])`
  token for the app's lifetime.
- **Menu bar drawing uses `NSStatusItem`, not `MenuBarExtra`.** A `MenuBarExtra`
  label is a static image updated on state change; it suits neither a custom
  two-line layout nor a per-second redraw.
- **A template image is honoured only in `button.image`.** An image embedded in an
  attributed title is drawn with the colour it was given and ignores the menu
  bar's appearance. The monochrome default depends on this.
- **The status item's width is fixed.** Monospaced, right-aligned digits in a
  fixed-length item; otherwise every change in digit count shifts the
  neighbouring icons.
- **Build the popover's content when it opens and release it in
  `popoverDidClose`.** An eagerly created `NSHostingController` kept laying out a
  hidden panel at ~12% CPU in load-spinner. Set
  `sizingOptions = [.preferredContentSize]`, and call `makeKey()` on the
  popover's window right after showing it.
- **Transient dismissal relies on the app never being activated.** `NSPopover`'s
  outside-click close breaks in an accessory app once `NSApp.activate` has been
  called. Keep settings inside the popover; if a separate window is ever added,
  port status-lens's click monitors in the same change.
- **No SwiftPM resources.** `Bundle.module` does not look inside an assembled
  `.app`, works on the build machine and crashes everywhere else. `resources:`
  stays empty; the icon is copied by the Makefile.
- **SwiftUI's `ColorPicker` does not present from an accessory app.** The colour
  setting is a toggle (monochrome / coloured), not a picker.
- **Verify an SF Symbol name exists before using it.** A missing name yields a nil
  image and an invisible status item; `AppDelegate` falls back to a text title.
- **`NWPathMonitor.availableInterfaces` returns the same interface more than
  once.** De-duplicate before taking "the first physical interface".
- **The macOS 26 verification environment is a VM** with a virtual NIC only — no
  Wi-Fi, no VPN. It can confirm counter behaviour and appearance; interface
  selection and behaviour under a VPN are checked on macOS 27 hardware only.
- **Single instance.** `LSMultipleInstancesProhibited` stops LaunchServices
  launches; `singleInstanceDecision` stops direct exec and `open -n`. Side
  effect: quit the installed copy before running a `dist/` build.

## Design reference

- RFP: `docs/ja/net-meter-rfp.ja.md` (`docs/en/net-meter-rfp.md`) — scope,
  decisions, rejected alternatives, and the measured platform constraints.
- Spikes: `spikes/README.md`.
- Sibling of the same shape: load-spinner (menu bar `NSStatusItem` + SwiftUI
  popover). Read its `AGENTS.md` before building the panel.

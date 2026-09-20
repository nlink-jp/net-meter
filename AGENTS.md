# AGENTS.md — net-meter

## Summary

macOS menu bar app (util-series) that shows the current upstream/downstream rate
of one network interface, as numbers and a graph. Swift 6 (strict concurrency),
Swift Package Manager, AppKit `NSStatusItem` + a SwiftUI popover, macOS 26+,
Apple Silicon. GUI only — there is no CLI. Bundle id `jp.nlink.net-meter`;
the app bundle is `NetMeter.app`, the repository and the cask are `net-meter`.

**Development Phase 2 in progress.** The menu bar item is live: two lines of rates
and a mirrored graph, redrawn every second, with the settings in a menu. That
menu is interim — the RFP's panel (history chart, interface details, peaks,
totals, settings, version) replaces it next, with status-lens as the reference
for popover dismissal. The pure core underneath is in place
— the rate rule (ADR-0001), the meter with per-interface history, interface
resolution and the selection list, rate formatting, graph scaling — and
`NetMeterSystem` asks the OS: counters through `sysctl`, the preference order,
display names and addresses. Phase 1's code is complete. Still open are checks
that need a person at the Mac — a wake from sleep, unplugging an adapter,
switching Wi-Fi/wired, a full-tunnel VPN (a split-tunnel VPN is measured); the
rules are built to fail safe whatever those show. The display is Phase 2, and it
starts with the ADR on the drawing approach. The plan
is in the RFP: Phase 1 is the pure core plus the checks on real systems, Phase 2
the drawing and the panel, Phase 3 the release.

## Build & test

- `make build` — compiles the release binary. **Never** run `swift build` for a
  deliverable; the Makefile owns the output location and pins the linked SDK.
- `make build-app` — assembles `dist/NetMeter.app` (Info.plist version from
  `git describe`) and signs it with a Developer ID Application identity.
  Re-signing replaces the bundle: a copy running from `dist/` has to be quit and
  started again.
- `make package` — build-app, then notarize + staple (`nlink-jp-notary` keychain
  profile), and zip to `dist/net-meter-<version>-darwin-arm64.zip`.
- `make verify-release` — gate: `.notarized` marker, `stapler validate`, and the
  linked SDK (run before upload).
- `make brew` — generate the Homebrew cask from the built zip into the local
  `nlink-jp/homebrew-tap` checkout (see `scripts/release-brew.mk`).
- `make test` — `swift test`, then `scripts/test_check_docs.py`,
  `spikes/test_analyze_watch.py` and `scripts/check_docs.py`.
- `make run` — `swift run` (debug). **Quit a running copy first.** The
  single-instance guard does not cover this path: a bare binary has no bundle
  identifier, so it starts next to a running `.app` and a second menu bar item
  appears (measured 2026-09-20).

## Structure

```
Sources/
  NetMeterCore/          Pure, testable logic (no AppKit UI)
    SingleInstance.swift   singleInstanceDecision() — startup duplicate guard (pids in, decision out)
    AppVersion.swift       displayVersion(bundleShortVersion:) — what the user is shown, "dev" outside a bundle
    SymbolName.swift       Every SF Symbol name the app may ask for; the only place a name is spelled
    SettingsStore.swift    SettingsStore protocol + the in-memory store tests use (UserDefaults store: NetMeterSystem)
    CounterReading.swift   InterfaceCounters (bytes, packets, link speed) and the CounterSource protocol
    RateRule.swift         RateRule.evaluate(previous:current:elapsed:) -> SampleOutcome — ADR-0001, rule by rule
    Meter.swift            Per-interface baseline, history (nil = no value), totals and peaks; time is passed in, never read
    RingBuffer.swift       Fixed-capacity history storage
    GraphScale.swift       Shared up/down full scale with a floor; fraction of full scale
    InterfaceResolver.swift resolveInterface(selection:pathOrder:available:) -> present(name) | absent
    Display.swift          DisplayMode, AppSettings (string-persisted), MeterReading (absent | waiting | rate), GraphWindow columns
    InterfaceCatalog.swift "Ethernet (en0)" labels and the manual selection list (hardware ports first; an absent choice stays listed)
    RateFormatter.swift    bytes/s -> number + unit, number never wider than 3 characters; bytes or bits, SI prefixes
  NetMeterSystem/        The thin layer that asks the OS. No logic worth a unit test lives here
    SysctlCounterSource.swift  CounterSource over sysctl NET_RT_IFLIST2: bytes, packets, link speed per interface
    SystemInterfaceInfoSource.swift  Display names (SystemConfiguration) and numeric addresses (getifaddrs; IPv4 first, no link-local)
    PathOrderMonitor.swift     NWPathMonitor -> [PathInterface], passed on as given (duplicates and tunnels included)
  NetMeterUI/            Drawing and views, as a library so tests can render it offscreen
    StatusRenderer.swift   ADR-0002: (StatusContent, StatusFinish, scale) -> image for button.image; fixed width per mode/unit
    MeterController.swift  Readings -> what is on display; every OS dependency injected; a setting reaches the display at once
    UIStrings.swift        Every user-visible string, one language throughout; also the accessibility value of the item
  NetMeter/              Executable: wiring only
    Main.swift             @main enum; single-instance guard, then the accessory-policy app
    AppDelegate.swift      OS sources, 1 s timer in .common mode, App Nap token, status item rendering, interim settings menu
Tests/NetMeterCoreTests/ Includes SymbolNameTests: every listed symbol resolves, and no app source spells one as a literal
                         ReplayTests is opt-in: NET_METER_REPLAY_LOG=<watch log> replays a recording through the real Meter
Tests/NetMeterSystemTests/ Live: reads this Mac's real counters (takes about a second; needs no traffic, no permission)
Tests/NetMeterUITests/   Offscreen, pixel by pixel: width independent of values, no colour in the template finish,
                         upstream above the centre and downstream below, gaps, dimmed "absent", right-aligned numbers.
                         StatusPreviewTests is opt-in: NET_METER_PREVIEW_DIR=<dir> writes a magnified sheet to look at
scripts/
  codesign-darwin-app.sh notarize-darwin-app.sh gen-brew.sh release-brew.mk cask.rb.tmpl
                         Vendored byte-identical from nlink-jp/.github/templates — never edit here
  make-icns.sh           1024px PNG -> AppIcon.icns
  check_docs.py          Links resolve; en/ja mirrors exist and name the same identifiers; no retired name in use
  test_check_docs.py     Shows each of those rules failing on a fixture tree
spikes/                  Measurement code the design rests on. Not part of the package, never shipped
                         counters.swift (one bracketable reading), watch.swift (per-second JSON log),
                         analyze_watch.py + its tests, path_order.swift
docs/{en,ja}/            RFP; ADRs go in docs/{en,ja}/adr/ (4-digit number + slug, org ADR header with `Binds: net-meter`)
assets/                  AppIcon-1024.png goes here (absent: the app builds without an icon)
Info.plist               Bundle template at the repo root (${VERSION}, ${BUNDLE_ID}, ${APP_NAME} substituted by `make build-app`)
```

## Non-negotiable rules

- **No permission, no entitlement, no network connection of its own.** No TCC
  grant, no administrator right, Hardened Runtime alone. This is a requirement to
  be maintained, not a current accident — do not add a grant without a deliberate
  scope decision.
- **A claim about how the OS behaves is either measured or labelled a
  hypothesis.** A measured claim says where and how many times. The first draft
  of this file said `make run` was covered by the single-instance guard without
  anyone having run it; it is not.
- **A byte counter's delta is always taken modulo 2^32.** The `if_data64` fields
  are 64 bits wide, but an unprivileged process is handed the true value modulo
  2^32, floored to 1 KiB (measured on macOS 27.0 and on macOS 26.6.2, each
  bracketed by `netstat` readings with the true counter past 2^32; counts in
  ADR-0001). Packet counters arrive unaltered. 1024 divides 2^32, so flooring and
  the modulus commute, and differencing modulo 2^32 is correct whether or not an
  OS truncates — as long as one sample's increase stays below 4 GiB. "The field
  is 64-bit, so no wrap handling is needed" is false.
- **A sample whose elapsed time is too long is discarded and the baseline
  re-established, unconditionally.** "Below 4 GiB per sample" only holds while the
  interval is bounded; after a sleep or a stalled timer the delta modulo 2^32 is
  ambiguous. Elapsed time is measured with a clock that keeps running while the
  Mac sleeps (`ContinuousClock`), so that a sleep shows up as a long interval
  instead of hiding inside a normal-looking one. The threshold is 3 seconds
  (ADR-0001).
- **A wrap is not a reset.** Counters can restart — a tunnel interface being
  re-created is the expected case; what a wake from sleep does to them is a
  hypothesis until Phase 1 measures it. A sample judged to be a reset is
  discarded and the baseline re-established; it must never surface as a
  multi-gigabyte spike. **ADR-0001 is the rule**: an interface that vanishes
  loses its baseline; a packet counter that went backwards, or bytes arriving
  without packets to carry them, is a reset. **The reported link speed is never
  used to judge a sample** — measured: a virtual NIC reported 100 Mbps while
  carrying 2.3 Gbps, and another reported 0. Changing a constant or the order of
  the rules means a new ADR, not an edit to `RateRule`.
- **Rates divide by measured elapsed time.** Timers get coalesced; never assume
  the interval was 1 second.
- **Every state has something to show, and "absent" is not zero.** A selected
  interface that is gone, a discarded sample and the first second before a
  baseline exists are states of an enum, not booleans, and each one maps to a
  non-empty display through a pure, tested function. The app never silently
  shows a different interface's numbers under a manual selection, and a manual
  selection that is absent stays listed as the selection in the panel.
- **The version is always on screen somewhere.** A menu bar app has no
  `--version`. The scaffold's menu shows it; the panel that replaces the menu has
  to show it too, verbatim and selectable.
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
  name to `RETIRED` in `scripts/check_docs.py` in that same commit. A design
  document is not rewritten: an addition goes in its Amendments section, a
  withdrawal is struck through with a date and its successor.

## Gotchas

Known before any of the code they constrain is written — each of these cost a
sibling app a defect. Where an entry of the org knowledge base
(`nlink-jp/knowledge`, `docs/{en,ja}/macos-gui.md` unless another file is named)
is the source, its title is given: read the entry, not this summary, before
building the thing it is about.

- **The sampling timer must be registered in `.common` run loop mode.**
  `Timer.scheduledTimer` registers in `.default` only, and the run loop leaves
  that mode while a menu or popover is tracking — the display would freeze
  exactly while the user is looking at it. Use the target/selector `Timer` API
  (a `@Sendable` closure trips Swift 6 capture checks) and
  `RunLoop.main.add(_:forMode: .common)`. (KB: "定期更新の Timer は .common run
  loop モードに登録する")
- **App Nap freezes a background timer in an `LSUIElement` app.** The numbers are
  right after launch and stale hours later. Hold a
  `ProcessInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep])`
  token for the app's lifetime. (KB: "メニューバー常駐アプリは SwiftUI 単体では
  完結しない")
- **Menu bar drawing uses `NSStatusItem`, not `MenuBarExtra`.** A `MenuBarExtra`
  label is a static image updated on state change; it suits neither a custom
  two-line layout nor a per-second redraw. (KB: "連続アニメするメニューバー
  アイコンは NSStatusItem で")
- **Template rendering and colour exclude each other, and the drawing approach is
  not chosen yet.** `isTemplate` is honoured only in `button.image` — an image
  inside an attributed title keeps the colour it was given and ignores the menu
  bar's appearance. A template image follows the menu bar but cannot carry
  colour; with `isTemplate = false` the given colours are baked in and nothing
  follows the appearance any more, the digits included. So the monochrome default
  and the coloured mode cannot share one naive path. Decide the approach in an
  ADR at the start of Phase 2, make the renderer a pure "values → image"
  function, and check both appearances offscreen. (KB: "メニューバーのアイコンは
  `button.image` に入れる")
- **The status item's width is fixed.** Monospaced, right-aligned digits in a
  fixed-length item; otherwise every change in digit count shifts the
  neighbouring icons. A panel's height, by contrast, is never fixed from today's
  content. (KB: "ビューの寸法を「今日の中身」で測って固定しない")
- **`makeKey()` and click monitors come as a pair.** A status item click does not
  activate an accessory app, so a popover that is merely shown is drawn inactive —
  visibly dimmed under Liquid Glass. Call `makeKey()` on the popover's window
  right after `show(relativeTo:)`. That activates the app, and activation breaks
  `NSPopover`'s `.transient` outside-click dismissal, so **dismissal must never
  rely on `.transient`**: install global + local mouse-down monitors while the
  popover is shown and remove them in `popoverDidClose`. The local monitor must
  ignore the status item button's window, or a click on the button closes and
  reopens. Under Swift 6 the handlers are nonisolated — wrap in
  `MainActor.assumeIsolated` and keep the `NSEvent` out of its return value.
  The reference implementation is **status-lens** (`installPopoverClickMonitors`),
  not load-spinner, which calls `makeKey()` without the monitors. (KB:
  "メニューバーの NSPopover は表示直後に makeKey() する")
- **Build the popover's content when it opens and release it in
  `popoverDidClose`.** An eagerly created `NSHostingController` kept laying out a
  hidden panel at ~12% CPU in load-spinner. Set
  `sizingOptions = [.preferredContentSize]`. (KB: "NSPopover 内の SwiftUI パネルは
  開いた時だけ生成する")
- **Borderless icon buttons in the popover need `.focusable(false)`**, or the
  first one takes keyboard focus and draws a focus ring the moment the popover
  opens. (status-lens and load-spinner AGENTS.md)
- **A setting changed in the panel has to reach the menu bar at once.** A change
  to one `ObservableObject` does not reach a view that is not observing it. (KB:
  "別の ObservableObject の変更は、観測していないビューには届かない")
- **Launch at login is system state.** Read and write `SMAppService` directly and
  do not mirror it in `UserDefaults`; gate it on running from a real bundle; and
  do not disable the toggle because the status is `.notFound` — that is what an
  unregistered app reports, not a refusal. (KB: "「いいえ」と「分からない」を
  区別できない status でコントロールを disable しない"; status-lens AGENTS.md)
- **A SwiftUI type named `Settings` collides with the `Settings` scene.**
  (status-lens AGENTS.md)
- **No SwiftPM resources.** `Bundle.module` does not look inside an assembled
  `.app`, works on the build machine and crashes everywhere else. `resources:`
  stays empty; the icon is copied by the Makefile. (KB: "`.app` の中で SwiftPM の
  `Bundle.module` を使わない")
- **SwiftUI's `ColorPicker` does not present from an accessory app.** The colour
  setting is a toggle (monochrome / coloured), not a picker. (load-spinner
  AGENTS.md)
- **SF Symbol names live in `SymbolName` and nowhere else.** A name that does not
  exist yields a nil image with no error. `SymbolNameTests` resolves every listed
  name and fails if an app source spells one as a literal; the fallback for a nil
  image is a visible text title. (KB: "SF Symbol 名は実在を検証してから使う")
- **`NWPathMonitor.availableInterfaces` can list the same interface more than
  once.** Seen in both of two runs (macOS 27.0, wired Ethernet first, no VPN:
  `en0` twice, then Wi-Fi). De-duplicate before taking "the first physical
  interface". With a split-tunnel VPN up the tunnel was appended at the end with
  type `other` and the physical interfaces kept their places (one observation).
  A full-tunnel VPN is unmeasured; if its tunnel does not appear as type `other`,
  or the physical interface drops out of the list, the automatic-selection rule
  is revisited in an ADR.
- **A status item cannot be observed through the window list on macOS 27.**
  `CGWindowListCopyWindowInfo` filtered by the app's pid returned no window (two
  observations, macOS 27.0; in the first the item was confirmed by eye), and the
  total window count was the same before and after launch — no process gained a
  window for it. An empty result there is not evidence that nothing is shown, and
  a probe should print the total count so that "cannot see the window server" is
  not mistaken for "no window". Verify appearance by eye, through the
  accessibility tree with synthetic clicks, or by having the app report its own
  geometry. (KB testing.md: "メニューバーアプリのポップオーバーはスクリプトから
  検証できる")
- **Judge translucent materials from a region capture.** `screencapture -R` keeps
  the background; `-l <windowid>` drops it and makes the panel look falsely dark.
  (KB: the `makeKey()` entry above, where this was measured)
- **Some behaviour only shows after hours.** A frozen timer and a counter wrap do
  not appear in a five-minute check; look at the app after it has run overnight.
  A counter that a drawing callback increments proves nothing in a headless test.
  (KB testing.md)
- **The macOS 26 verification environment is a VM** with a virtual NIC only — no
  Wi-Fi, no VPN. It can confirm counter behaviour and appearance; interface
  selection and behaviour under a VPN are checked on macOS 27 hardware only.
- **Single instance covers the bundle, not the bare binary.**
  `LSMultipleInstancesProhibited` stops LaunchServices launches;
  `singleInstanceDecision` stops direct exec of the bundled binary and `open -n`
  (measured: a second copy exits 0 with one stderr line). A bare binary has no
  bundle identifier and always proceeds. Side effect: quit the installed copy
  before running a `dist/` build.
- **Test stubs must not capture the `XCTestCase` in a `@Sendable` closure.**
  (status-lens AGENTS.md)

## Design reference

- RFP: `docs/ja/net-meter-rfp.ja.md` (`docs/en/net-meter-rfp.md`) — scope,
  decisions, rejected alternatives, the measured platform constraints, and the
  amendments made after the independent design review.
- Spikes: `spikes/README.md`.
- Siblings of the same shape (menu bar `NSStatusItem` + SwiftUI popover):
  **status-lens for the popover** (dismissal, focus, settings reaching the menu
  bar, launch at login), load-spinner for the status item, the lazy panel and the
  release wiring. Read both `AGENTS.md` files in full before building the panel —
  a sibling's code also carries the lessons it has not applied yet.

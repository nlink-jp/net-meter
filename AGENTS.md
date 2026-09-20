# AGENTS.md — net-meter

## Summary

macOS menu bar app (util-series) that shows the current upstream/downstream rate
of one network interface, as numbers and a graph. Swift 6 (strict concurrency),
Swift Package Manager, AppKit `NSStatusItem` + a SwiftUI panel in a non-activating
`NSPanel` (ADR-0003), macOS 26+,
Apple Silicon. GUI only — there is no CLI. Bundle id `jp.nlink.net-meter`;
the app bundle is `NetMeter.app`, the repository and the cask are `net-meter`.

The menu bar item shows two lines of rates and a mirrored graph of the last
minute, redrawn every second. Clicking it opens the panel: a three-minute history
chart, the interface's addresses and reported link speed, peaks, totals since
launch, every setting, launch at login, the version and Quit.

What is decided and why lives in the RFP (with its Amendments) and the ADRs; what
was measured, and how to measure it again, in `spikes/README.md`. This file does
not track progress — `git log` and `CHANGELOG.md` do.

**Not yet measured** (the rules are built to fail safe whatever these show): a
wake from sleep, an adapter being unplugged, a switch between Wi-Fi and wired, a
full-tunnel VPN, a light menu bar with the coloured finish, and a Mac with
displays of mixed scale.

## Build & test

- `make build` — compiles the release binary. **Never** run `swift build` for a
  deliverable; the Makefile owns the output location and pins the linked SDK.
- `make build-app` — assembles `dist/NetMeter.app` (Info.plist version from
  `git describe`, icon from `assets/AppIcon-1024.png`) and signs it with a
  Developer ID Application identity. Re-signing replaces the bundle: a copy
  running from `dist/` has to be quit and started again.
- `make package` — build-app, then notarize + staple (`nlink-jp-notary` keychain
  profile), and zip to `dist/net-meter-<version>-darwin-arm64.zip`.
- `make verify-release` — gate: `.notarized` marker, `stapler validate`, and the
  linked SDK (run before upload).
- `make brew` — generate the Homebrew cask from the built zip into the local
  `nlink-jp/homebrew-tap` checkout (see `scripts/release-brew.mk`).
- `make test` — `swift test`, then `scripts/test_check_docs.py`,
  `spikes/test_analyze_watch.py` and `scripts/check_docs.py`. The
  `NetMeterSystemTests` are live: they read this Mac's counters, addresses and
  interface order, take about a second, and need no traffic and no permission.
- `make run` — `swift run` (debug). **Quit a running copy first.** The
  single-instance guard does not cover this path: a bare binary has no bundle
  identifier, so it starts next to a running `.app` and a second menu bar item
  appears (measured 2026-09-20).
- `swift scripts/gen-icon.swift` — regenerates `assets/AppIcon-1024.png`.

Opt-in tests that produce something to look at rather than a verdict:

- `NET_METER_PREVIEW_DIR=<dir> swift test --filter "StatusPreviewTests|PanelViewTests"`
  writes the menu bar item (every state × finish × mode, magnified) and the panel
  as PNGs. Look at them after any change to drawing or layout: the numeric layout
  tests passed while the picture showed a truncated address and squeezed pickers.
- `NET_METER_REPLAY_LOG=<watch log> swift test --filter ReplayTests` replays a
  recording made by `spikes/watch.swift` through the real `Meter`.

## Structure

```
Sources/
  NetMeterCore/          Pure logic: no AppKit UI, no OS calls, no clock
    CounterReading.swift   InterfaceCounters (bytes, packets, link speed) and the CounterSource protocol
    RateRule.swift         RateRule.evaluate(previous:current:elapsed:) -> SampleOutcome — ADR-0001, rule by rule
    Meter.swift            Per-interface baseline, history (nil = no value), totals, peaks, link speed; time is passed in
    RingBuffer.swift       Fixed-capacity history storage
    InterfaceResolver.swift resolveInterface(selection:pathOrder:available:) -> present(name) | absent
    InterfaceCatalog.swift "Ethernet (en0)" labels and the selection list (hardware ports first; an absent choice stays listed)
    RateFormatter.swift    bytes/s -> number + unit, number never wider than 3 characters; bytes or bits, SI prefixes
    Display.swift          DisplayMode, AppSettings (string-persisted), MeterReading (absent | waiting | rate),
                           GraphWindow: the last 14 samples, one bar each — no time buckets
    GraphScale.swift       Shared up/down full scale with a floor; eased(previous:target:) — up at once, down by 20% a sample
    PanelUpdateGate.swift  Holds panel refreshes while one of the panel's menus is tracking; one is delivered after
    Panel.swift            PanelFormat (byte totals, link speed), PanelHistory chart points,
                           PanelClick.closesPanel, PanelToggle (one click, two handlers, matched by order)
    PanelPlacement.swift   frame(itemFrame:panelSize:visibleFrame:) — below the item, centred, kept on the screen
    StatusItemHit.swift    statusItemOwns(location, itemWindowFrame:) — the measured region, top-left ownership
    LoginItem.swift        LoginItemState: unavailable | off | on | requiresApproval
    SettingsStore.swift    SettingsStore protocol + the in-memory store tests use
    SymbolName.swift       The one place an SF Symbol name may be spelled (empty: the app draws its own arrows)
    SingleInstance.swift   singleInstanceDecision() — startup duplicate guard
    AppVersion.swift       displayVersion(bundleShortVersion:) — verbatim, "dev" outside a bundle
  NetMeterSystem/        The thin layer that asks the OS
    SysctlCounterSource.swift  CounterSource over sysctl NET_RT_IFLIST2. Names are resolved on every read on purpose:
                               caching index -> name would save about 2 ms a second and risk a stale name after an
                               interface is re-created
    SystemInterfaceInfoSource.swift  Display names (SystemConfiguration) and numeric addresses (getifaddrs; IPv4 first, no link-local)
    PathOrderMonitor.swift     NWPathMonitor -> [PathInterface], passed on as given; the first update is always delivered
    UserDefaultsSettingsStore.swift  One string per key
    LoginItemService.swift     SMAppService.mainApp, gated on a real bundle; `.notFound` reads as off, not as unavailable
  NetMeterUI/            Drawing and views, as a library so tests can render it offscreen
    StatusRenderer.swift   ADR-0002: (StatusContent, StatusFinish) -> image with 1x and 2x representations; width by display mode alone
    MeterController.swift  Readings -> what is on display; every OS dependency injected; a setting reaches the display at once
    PanelModel.swift       PanelSnapshot (a value, settings and the last action's error included) + the one ObservableObject
    PanelView.swift        The SwiftUI panel: fixed width, height from content — and it reports that height;
                           Swift Charts history with a fixed window and scale
    PanelWindow.swift      ADR-0003: the `.nonactivatingPanel` NSPanel the panel lives in; key but never main, Esc to
                           the owner, popover material drawn active, no safe area from the hidden title bar
    UIStrings.swift        Every user-visible string, one language throughout; a test requires each to be in use
  NetMeter/              Executable: wiring only
    Main.swift             @main enum; single-instance guard, then the accessory-policy app
    AppDelegate.swift      OS sources, 1 s timer in .common mode, App Nap token, status item rendering, and the panel:
                           content built on open and released on close, one close path, click monitors, placement;
                           a click/action recorder under `#if TRACE` only
Tests/
  NetMeterCoreTests/     Pure. ReplayTests is opt-in
  NetMeterSystemTests/   Live, against this Mac
  NetMeterUITests/       Offscreen: the status item pixel by pixel, the panel through the real layout engine,
                         the controller and the panel snapshot with scripted sources
scripts/
  codesign-darwin-app.sh notarize-darwin-app.sh gen-brew.sh release-brew.mk cask.rb.tmpl
                         Vendored byte-identical from nlink-jp/.github/templates — never edit here
  make-icns.sh           1024px PNG -> AppIcon.icns
  gen-icon.swift         Draws assets/AppIcon-1024.png
  check_docs.py          Links resolve; en/ja mirrors exist and name the same identifiers; no retired name in use
  test_check_docs.py     Shows each of those rules failing on a fixture tree
spikes/                  Measurement code the design rests on. Not part of the package, never shipped:
                         counters.swift, watch.swift, analyze_watch.py + tests, path_order.swift, status_appearance.swift
docs/{en,ja}/            RFP; ADRs in docs/{en,ja}/adr/ (4-digit number + slug, org ADR header with `Binds: net-meter`)
assets/                  AppIcon-1024.png
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
- **The version is always on screen.** A menu bar app has no `--version`. It is
  at the bottom of the panel, verbatim and selectable; whatever replaces the
  panel's footer has to keep it.
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
  that mode while a menu is tracking — the display would freeze
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
- **Template rendering and colour exclude each other; ADR-0002 is how both are
  served.** `isTemplate` is honoured only in `button.image` — an image inside an
  attributed title keeps the colour it was given and ignores the menu bar's
  appearance. A template image follows the menu bar but cannot carry colour; with
  `isTemplate = false` the given colours are baked in and nothing follows the
  appearance any more, the digits included. So one pure renderer has two
  finishes, and the coloured one takes its foreground from the button's
  `effectiveAppearance` — which reports the menu bar's own appearance, not the
  system's (measured once: `VibrantDark` under a light system). (KB: "メニューバーの
  アイコンは `button.image` に入れる")
- **The status item's width depends on the display mode alone.** Monospaced,
  right-aligned digits in a fixed-length item, with room reserved for the widest
  unit label of either unit system; otherwise every change in digit count — or a
  switch between bytes and bits — shifts the neighbouring icons. A panel's height, by contrast, is never fixed from today's
  content. (KB: "ビューの寸法を「今日の中身」で測って固定しない")
- **The panel is a non-activating `NSPanel`, and the app never asks to be
  activated (ADR-0003).** A click inside an ordinary window of an accessory app
  activates the app, and that activation arrives while the pop-up menu the click
  has just opened is tracking — and ends it. Measured twice: 78 ms after the menu
  began with a popover that was only made key, and 71 ms with a popover that
  called `NSApp.activate` on open — *right after launch*, where the OS refused the
  request (frontmost stayed the previous app, no `didBecomeActive`; macOS 14+
  refuses activation for up to ~30 s after launch, and on macOS 27 a status item
  click is received by another process, so the request is not tied to a user
  action). That second design had passed nine opens out of nine in a build started
  from a terminal — a child of the frontmost app — and failed on the first open of
  the signed bundle started by LaunchServices. **Test anything that depends on
  activation from a LaunchServices launch, within the first half minute.** With
  `.nonactivatingPanel` the same first click, 21.8 s after launch, left the menu
  open for 1,906 ms, and no activation happened at all (one run). `PanelWindowTests`
  pins the style bit and scans the sources: `.activate(`, `yieldActivation` and
  `NSPopover(` fail the build's tests. (KB: "メニューバー用 NSPanel の罠 2 件")
- **`NSApp.isActive` reads true while the non-activating panel is key** — with no
  `didBecomeActive` posted and another app still frontmost (measured, one run).
  For "is the app active", ask `NSWorkspace.shared.frontmostApplication`.
- **The panel's rules, all from siblings that paid for them:** `canBecomeKey` true
  (Esc, text selection) and `canBecomeMain` false; never `hidesOnDeactivate` (it
  hides without clearing `isVisible`); whether the panel is open is the app's own
  boolean, set in `showPanel` and `hidePanel` only; **one close path** —
  `hidePanel` — for outside clicks, a click on the item and Esc, and it always
  removes the monitors and releases the content. Nothing tells a non-activating
  panel that the user clicked elsewhere, so global + local mouse-down monitors are
  installed while it is open. The local monitor ignores the status item button's
  window (its action toggles; closing too would reopen) and the panel's own, a
  menu's child window included; that decision is `PanelClick.closesPanel`, pinned
  by a test. Under Swift 6 the handlers are nonisolated: wrap the body in
  `MainActor.assumeIsolated` and read `event.window` outside it.
- **A hidden title bar still has a safe area.** The panel is titled (the window
  server then draws the rounded corners and the shadow) with the title bar hidden,
  and SwiftUI content in it asked for 535 pt instead of 503 — 32 pt of safe area.
  `ignoresSafeArea()` on the view did not change the size asked for;
  `safeAreaRegions = []` on the hosting controller did. A test compares the
  window's answer with the offscreen layout's.
- **The window is sized from what the content reports.** The hosting controller
  has `sizingOptions = []`; `PanelView` takes its ideal height whatever the window
  offers (`fixedSize`) and reports it (`onGeometryChange`), and the app places the
  window from that with `PanelPlacement.frame` — the top edge stays put, so the
  panel grows downwards. Two things sizing one window is how it starts to jump.
- **One click on the status item reaches two handlers, and they are matched by
  order — never by time, and never by what the window says about itself.** On macOS 27 another process
  hosts the menu bar, so a click on our own item reaches the *global* mouse-down
  monitor first and the button's action 5–30 ms later (when the app is active the
  action sometimes never comes — measured in nvme-lens, from which `PanelToggle`
  and `statusItemOwns` are ported). The monitor closes the panel and notes that
  the click was on the item; the next action is that click's and is dropped; with
  no action, the note is void at the next mouse-down, so the monitor outlives the
  panel until then.
  What was tried first and failed on real hardware, when the panel was an
  `NSPopover`: deciding by `isShown` plus a
  0.25 s window. With the default close animation `isShown` stayed true for
  534–546 ms after a close was requested (four measurements), so at two clicks a
  second every other "open" click was read as "close" and nothing opened — which
  is how it was reported. Without the animation the close took 2–18 ms, and the
  order-matching toggle survived 58 clicks at a median of 183 ms apart: 57 of 57
  transitions alternated. The panel is now a window shown and hidden without
  animation, and its state is the app's own boolean.
  **Do not reintroduce a time window, an animation, or a decision on the window's
  own state** — each is this defect again under a different load.
- **The panel is not refreshed while one of its menus is open.** The per-second
  refresh made SwiftUI re-sync the pop-up button to the current value, and the
  item then picked was reported as that old value: the setter received the old
  unit every time a refresh fell inside the tracking (three of three). Refreshes
  are held by `PanelUpdateGate` from `NSMenu.didBeginTracking` to
  `didEndTracking` and one is delivered afterwards — on the next run loop turn,
  after the control's own action. Measured after the fix: seven selections of a
  different value, seven applied; shortest menu 909 ms. The menu bar item itself
  is never held back.
- **Reading a click trace: one click is one event number — and a selection
  arrives before its menu ends.** The binding's setter runs about 190 ms *before*
  `didEndTracking` is posted. A script that looked for the settings change after
  "MENU end" called five good selections lost. That was the second time in one
  day a working fix was declared broken by the analysis rather than by the app:
  when a trace and the person who used the app disagree, read the raw lines
  before believing the script. `make build-app SWIFT_FLAGS="-Xswiftc -DTRACE"
  DIST_DIR=dist/trace` builds a signed bundle with a recorder
  (`NET_METER_TRACE=<file>`) of every mouse-down, mouse-up and action; start it
  with `open --env NET_METER_TRACE=<file> dist/trace/NetMeter.app`, because how
  the app is launched is part of what is being measured. It is never part of a
  release: `make package` refuses a non-empty `SWIFT_FLAGS`, and `make
  verify-release` counts the recorder's symbols in the binary itself —
  `nm <binary> | grep -ci trace` gave 0 for the release and 25 for the diagnostic
  build. `strings` cannot tell them apart: Swift stores string
  literals of 15 bytes or fewer inline in the code, and they show up nowhere.
  The recorder's own global monitor runs *after* the app's, so its
  line for a closing click already says `shown=false`. Read naively, that made a
  working fix look broken: half the clicks seemed to do nothing. Group lines by
  event number and judge a click by the state its mouse-up line reports.
- **Build the panel's content when it opens and release it when it closes.** An
  eagerly created `NSHostingController` kept laying out a hidden panel at ~12% CPU
  in load-spinner. (KB: "NSPopover 内の SwiftUI パネルは開いた時だけ生成する" — the
  same holds for a panel window.)
- **Borderless icon buttons in the panel need `.focusable(false)`**, or the first
  one takes keyboard focus and draws a focus ring the moment the panel opens.
  (status-lens and load-spinner AGENTS.md)
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
  exist yields a nil image with no error. The app draws its own arrows and uses no
  symbol today, so the list is empty; `SymbolNameTests` resolves whatever is
  listed and fails if an app source spells a name as a literal in any of the
  three spellings (`systemSymbolName:`, `systemName:`, `systemImage:`). (KB: "SF
  Symbol 名は実在を検証してから使う")
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
  (KB: "メニューバーの NSPopover は表示直後に makeKey() する", where this was measured)
- **Some behaviour only shows after hours.** A frozen timer and a counter wrap do
  not appear in a five-minute check; look at the app after it has run overnight.
  A counter that a drawing callback increments proves nothing in a headless test.
  (KB testing.md)
- **The macOS 26 verification environment is a VM** with a virtual NIC only — no
  Wi-Fi, no VPN. It can confirm counter behaviour and appearance; interface
  selection and behaviour under a VPN are checked on macOS 27 hardware only.
- **The answer to an action and the polled state are different fields.** Launch
  at login is re-read from the OS every second; an error stored alongside it
  would be wiped before anyone could read it. `PanelSnapshot.loginItemError` is
  held by the app delegate until the next attempt or until the panel closes, and
  shown where the toggle is. A toggle that springs back without a word is the
  worst outcome. (KB: "操作の返事とポーリングの結果を同じフィールドに置かない")
- **Replacing a piece of UI means sweeping what it left behind, in the same
  commit.** The interim settings menu was replaced by the panel and left three
  strings, a symbol and a catalogue field unused; a reviewer found them, not a
  test. `UIStringsTests` now fails for a string nothing uses, and a withdrawn
  mechanism's name goes into `RETIRED` in `scripts/check_docs.py`.
- **A graph bar is a sample, not a time bucket.** Buckets were tried twice and
  looked wrong in motion both times. Measured back from `now`, each sample
  crossed a bucket edge at a moment set by its own phase, so two bursts drifted
  apart and together. Fixed to absolute five-second slots, the graph stood still
  for seconds and then jumped, and the newest bar kept changing height — which is
  what a person watching the menu bar reported. One-second slots would lose and
  merge samples whenever a jittery timer straddles a slot edge. Counting samples
  has no edges. **Look at motion as a filmstrip**
  (`NET_METER_PREVIEW_DIR=<dir> swift test --filter StatusFilmstripTests`): a
  single rendered frame cannot show any of this, and neither could the tests.
- **The graph's scale is eased, and by the controller, not the renderer.** When a
  peak scrolls out, every remaining bar would otherwise jump taller at once. The
  scale grows immediately (a bar is never clipped), comes down by 20% per sample,
  moves only when a new sample arrives (a settings change must not speed it up),
  and starts fresh when the displayed interface changes.
- **Converting an unbounded `Double` to `Int` traps.** Compare or clamp as a
  `Double` first. No real rate gets there; a test with an absurd input does.
- **Things that must look aligned are placed from one source, and the alignment
  is measured in ink.** The arrows had their own constants ("two to ten points
  above the row's bottom") while the digits sat where the font put them: the
  upstream arrow happened to match, the downstream one was a whole pixel high at
  1x — reported by eye, confirmed as +1.00 pt by comparing the vertical middle of
  each one's ink. Arrows now span the digits' band, derived from the font's
  baseline and cap height; `StatusAlignmentTests` holds both rows within half a
  point at 1x and 2x.
- **Size a field for the longest real value, measured — not for the sample data.**
  The panel was laid out with `2001:db8::10` in a table cell 158 pt wide; a real
  IPv6 address needs up to 265 pt and was cut in the middle. Addresses now get
  the panel's full width in a monospaced font, and a test measures the 39-character
  worst case against the width. The previews and tests use that address too.
- **Place the panel again when the item's width changes.** Display mode is changed
  from inside the panel, which resizes the very item the panel hangs from. The
  item's window has not moved yet when its length is set, so the placement waits
  for the next turn of the run loop.
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
- Siblings of the same shape (menu bar `NSStatusItem` + a SwiftUI panel):
  **task-clock-gui and instant-translate for the non-activating panel** (the
  window, the one close path, placement), status-lens for dismissal, focus,
  settings reaching the menu bar and launch at login, load-spinner for the status
  item, the lazy content and the release wiring, nvme-lens for `PanelToggle`. Read
  their `AGENTS.md` files in full before changing the panel — a sibling's code
  also carries the lessons it has not applied yet.

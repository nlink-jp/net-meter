import AppKit
import NetMeterCore
import NetMeterSystem
import NetMeterUI
import SwiftUI

/// Wiring only: the OS sources, the one-second timer, and the state the menu bar
/// item and the panel show. The item and the panel's window are SwiftUI's
/// `MenuBarExtra` (ADR-0004); this object never touches either directly.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller: MeterController
    private let pathMonitor = PathOrderMonitor()
    private let infoSource = SystemInterfaceInfoSource()
    private let loginItem = LoginItemService()
    private var timer: Timer?
    /// Held for the app's lifetime: App Nap would otherwise freeze the timer of
    /// an app with no visible window, hours after launch.
    private var activity: NSObjectProtocol?
    private let now: () -> Double

    /// What the item shows; `StatusLabel` draws it (ADR-0002). An object of its
    /// own, so that the once-a-second change reaches the label and nothing else.
    let statusModel: StatusModel

    /// One model for the app's lifetime, pushed to only while the panel is open:
    /// the window's content is built by `MenuBarExtra`, not here.
    let panelModel: PanelModel
    /// Whether the panel is open is this boolean, set when its content appears
    /// and disappears and nowhere else.
    private(set) var panelOpen = false
    /// Refreshes wait while one of the panel's menus is open; see PanelUpdateGate.
    private var updateGate = PanelUpdateGate()
    /// Why launch at login could not be changed; shown until the next attempt or
    /// until the panel closes.
    private var loginItemError: String?

    override init() {
        // Seconds on a clock that keeps running during sleep (ADR-0001).
        let clock = ContinuousClock()
        let start = clock.now
        let now: () -> Double = {
            let elapsed = clock.now - start
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
        self.now = now
        let pathMonitor = self.pathMonitor
        let controller = MeterController(
            counters: SysctlCounterSource(),
            pathOrder: { pathMonitor.current },
            now: now,
            store: UserDefaultsSettingsStore()
        )
        self.controller = controller
        statusModel = StatusModel(
            status: controller.content,
            coloured: controller.settings.coloured,
            spoken: UIStrings.spoken(controller.content.reading, unit: controller.content.unit)
        )
        // A placeholder for the few moments before launch finishes, replaced with
        // real values right after the first tick (`applicationDidFinishLaunching`).
        panelModel = PanelModel(snapshot: controller.panelSnapshot(
            info: [:], pathOrder: [], loginItem: .off,
            version: displayVersion(bundleShortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String),
            now: now()
        ))
        super.init()
        panelModel.changeSettings = { [weak self] in
            #if TRACE
            Trace.log("SETTINGS unit=\($0.unit) mode=\($0.displayMode) selection=\($0.selection) coloured=\($0.coloured)")
            #endif
            self?.controller.settings = $0
        }
        panelModel.setLoginItem = { [weak self] on in
            guard let self else { return }
            #if TRACE
            Trace.log("LOGINITEM set=\(on)")
            #endif
            do {
                try self.loginItem.set(on)
                self.loginItemError = nil
            } catch {
                self.loginItemError = error.localizedDescription
            }
            self.panelModel.snapshot = self.snapshot()
        }
        panelModel.quit = { NSApp.terminate(nil) }
        controller.onChange = { [weak self] in self?.render() }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // LSUIElement already makes the bundle an accessory; a bare binary
        // (`make run`) has no Info.plist, and without this it would get a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        #if TRACE
        Trace.install(self)
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Sampling network interface counters once a second"
        )

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)

        pathMonitor.start { [weak self] _ in
            Task { @MainActor in self?.controller.refresh() }
        }

        // `.common`, not the default mode: the run loop leaves the default mode
        // while a menu or a control in the panel is tracking, and the display
        // would freeze exactly while someone is looking at it.
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
        // The content is built on the first open, from whatever the model holds
        // then; let that be the real interface list and login state, not the
        // placeholder from `init`.
        panelModel.snapshot = snapshot()
    }

    @objc private func tick() {
        controller.tick()
    }

    private func render() {
        let content = controller.content
        statusModel.status = content
        statusModel.coloured = controller.settings.coloured
        statusModel.spoken = UIStrings.spoken(content.reading, unit: content.unit)
        #if TRACE
        if panelOpen { Trace.log("PUSH    unit=\(controller.settings.unit) mode=\(controller.settings.displayMode) held=\(updateGate.trackingDepth > 0)") }
        #endif
        pushPanelUpdate()
    }

    // MARK: the panel

    /// From the panel content's `onAppear`: the snapshot is brought up to date,
    /// then kept so once a second. Whether this lands before the window's first
    /// frame is not measured; by hand, no stale frame was seen.
    func panelDidOpen() {
        #if TRACE
        Trace.log("OPEN    active=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
        #endif
        panelOpen = true
        panelModel.snapshot = snapshot()
    }

    /// From the panel content's `onDisappear`, however the window was closed.
    func panelDidClose() {
        #if TRACE
        Trace.log("CLOSE")
        #endif
        panelOpen = false
        loginItemError = nil
        updateGate.reset()
        // The content is kept while closed. Leave it holding a current snapshot
        // without the cleared error, so a reopen does not start from an old one.
        panelModel.snapshot = snapshot()
    }

    private func pushPanelUpdate() {
        guard panelOpen, updateGate.shouldDeliverUpdate() else { return }
        panelModel.snapshot = snapshot()
    }

    @objc private func menuDidBeginTracking() {
        guard panelOpen else { return }
        updateGate.menuDidBeginTracking()
    }

    @objc private func menuDidEndTracking() {
        guard panelOpen, updateGate.menuDidEndTracking() else { return }
        // The selection itself arrived before this notification (about 190 ms
        // before it, measured); the held refresh goes out on the next turn of the
        // run loop, after the pop-up button has finished with its own update.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panelOpen else { return }
            self.pushPanelUpdate()
        }
    }

    private func snapshot() -> PanelSnapshot {
        controller.panelSnapshot(
            info: infoSource.info(),
            pathOrder: pathMonitor.current,
            loginItem: loginItem.state,
            loginItemError: loginItemError,
            version: displayVersion(
                bundleShortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ),
            now: now()
        )
    }
}

/// The menu bar item's state, observed by `StatusLabel` only.
@MainActor
final class StatusModel: ObservableObject {
    @Published var status: StatusContent
    @Published var coloured: Bool
    @Published var spoken: String

    init(status: StatusContent, coloured: Bool, spoken: String) {
        self.status = status
        self.coloured = coloured
        self.spoken = spoken
    }
}

#if TRACE
/// Diagnostic build only (`make build-app SWIFT_FLAGS="-Xswiftc -DTRACE" DIST_DIR=dist/trace`):
/// records mouse-downs, menu tracking, activation, key windows and the panel's
/// opening and closing. Never compiled into a release; `make verify-release`
/// looks for these symbols in the binary.
@MainActor
enum Trace {
    private static var handle: FileHandle?
    private static let start = ContinuousClock().now
    private static var monitors: [Any] = []
    private static var observers: [Any] = []

    static func install(_ delegate: AppDelegate) {
        let path = ProcessInfo.processInfo.environment["NET_METER_TRACE"] ?? "/tmp/net-meter-trace.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
        log("START pid=\(ProcessInfo.processInfo.processIdentifier) bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundlePath.hasSuffix(".app") ? "app bundle" : "bare binary") policy=\(NSApp.activationPolicy().rawValue)")
        let center = NotificationCenter.default
        for (name, label) in [(NSMenu.didBeginTrackingNotification, "MENU    begin"), (NSMenu.didEndTrackingNotification, "MENU    end"),
                              (NSApplication.didBecomeActiveNotification, "APP     active"), (NSApplication.didResignActiveNotification, "APP     inactive"),
                              (NSWindow.didBecomeKeyNotification, "WINDOW  key"), (NSWindow.didResignKeyNotification, "WINDOW  resign-key")] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                var detail = (note.object as? NSWindow).map { " \(type(of: $0))" } ?? ""
                if let menu = note.object as? NSMenu {
                    let items = menu.items.map { ($0.state == .on ? "*" : "") + $0.title }.joined(separator: "|")
                    detail += " highlighted=\(menu.highlightedItem?.title ?? "nil") items=[\(items)]"
                }
                MainActor.assumeIsolated { log(label + detail) }
            })
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseUp]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak delegate] event in
            let location = event.locationInWindow, type = event.type.rawValue, number = event.eventNumber
            MainActor.assumeIsolated {
                log("GLOBAL type=\(type == 1 ? "down" : "up")#\(number) at=(\(Int(location.x)),\(Int(location.y))) active=\(NSApp.isActive) open=\(delegate?.panelOpen ?? false)")
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak delegate] event in
            let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
            let kind = event.type.rawValue, number = event.eventNumber
            let window = event.window.map { String(describing: Swift.type(of: $0)) } ?? "nil"
            MainActor.assumeIsolated {
                log("LOCAL  type=\(kind == 1 ? "down" : "up")#\(number) at=(\(Int(location.x)),\(Int(location.y))) window=\(window) active=\(NSApp.isActive) open=\(delegate?.panelOpen ?? false)")
            }
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    static func log(_ message: String) {
        let elapsed = ContinuousClock().now - start
        let ms = Int(elapsed.components.seconds) * 1000 + Int(elapsed.components.attoseconds / 1_000_000_000_000_000)
        handle?.write(Data("\(ms) \(message)\n".utf8))
    }
}
#endif

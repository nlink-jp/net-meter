import AppKit
import NetMeterCore
import NetMeterSystem
import NetMeterUI
import SwiftUI

/// Wiring only: the OS sources, the one-second timer, the status item and the
/// panel's popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var controller: MeterController?
    private let pathMonitor = PathOrderMonitor()
    private let infoSource = SystemInterfaceInfoSource()
    private let loginItem = LoginItemService()
    private var timer: Timer?
    /// Held for the app's lifetime: App Nap would otherwise freeze the timer of
    /// an app with no visible window, hours after launch.
    private var activity: NSObjectProtocol?
    private var now: () -> Double = { 0 }

    private let popover = NSPopover()
    #if TRACE
    var traceItemFrame: CGRect? { statusItem?.button?.window?.frame }
    var tracePanelShown: Bool { popover.isShown }
    #endif
    /// Exists only while the panel is open.
    private var panelModel: PanelModel?
    private var clickMonitors: [Any] = []
    /// One click on the status item reaches two handlers; see PanelToggle.
    private var panelToggle = PanelToggle()
    /// Refreshes wait while one of the panel's menus is open; see PanelUpdateGate.
    private var updateGate = PanelUpdateGate()
    /// Whoever was frontmost before the panel took activation, to hand it back.
    private var previousApp: NSRunningApplication?
    /// Why launch at login could not be changed; shown until the next attempt or
    /// until the panel closes.
    private var loginItemError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Sampling network interface counters once a second"
        )

        // Seconds on a clock that keeps running during sleep (ADR-0001).
        let clock = ContinuousClock()
        let start = clock.now
        now = {
            let elapsed = clock.now - start
            return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }

        let controller = MeterController(
            counters: SysctlCounterSource(),
            pathOrder: { [pathMonitor] in pathMonitor.current },
            now: now,
            store: UserDefaultsSettingsStore()
        )
        controller.onChange = { [weak self] in self?.render() }
        self.controller = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self
        // Not animated, on purpose: with the default animation `isShown` stayed
        // true for about 540 ms after a close was requested (measured), and a
        // click in that window was read as "close" when the user meant "open".
        popover.animates = false

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(menuDidBeginTracking), name: NSMenu.didBeginTrackingNotification, object: nil)
        center.addObserver(self, selector: #selector(menuDidEndTracking), name: NSMenu.didEndTrackingNotification, object: nil)

        pathMonitor.start { [weak self] _ in
            Task { @MainActor in self?.controller?.refresh() }
        }

        // `.common`, not the default mode: the run loop leaves the default mode
        // while a menu or a control in the panel is tracking, and the display
        // would freeze exactly while someone is looking at it.
        let timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
        #if TRACE
        Trace.install(self)
        #endif
    }

    @objc private func tick() {
        controller?.tick()
    }

    private func render() {
        guard let controller, let item = statusItem, let button = item.button else { return }
        let content = controller.content
        let width = StatusRenderer.size(mode: content.mode).width
        if item.length != width {
            item.length = width
            // Changing the display mode from inside the panel resizes the item the
            // panel is anchored to; re-anchor so the arrow keeps pointing at it.
            if popover.isShown { popover.positioningRect = button.bounds }
        }

        // ADR-0002: the button reports the menu bar's own appearance, which can
        // differ from the system's.
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let finish: StatusFinish = controller.settings.coloured ? .coloured(darkMenuBar: dark) : .template
        button.image = StatusRenderer.image(content: content, finish: finish)
        button.setAccessibilityLabel("net-meter")
        button.setAccessibilityValue(UIStrings.spoken(content.reading, unit: content.unit))

        // The panel is only kept up to date while it is open.
        #if TRACE
        if panelModel != nil { Trace.log("PUSH    unit=\(controller.settings.unit) mode=\(controller.settings.displayMode) held=\(updateGate.trackingDepth > 0)") }
        #endif
        pushPanelUpdate()
    }

    // MARK: the panel

    private func pushPanelUpdate() {
        guard let panelModel, updateGate.shouldDeliverUpdate() else { return }
        panelModel.snapshot = snapshot()
    }

    @objc private func menuDidBeginTracking() {
        guard popover.isShown else { return }
        updateGate.menuDidBeginTracking()
    }

    @objc private func menuDidEndTracking() {
        guard popover.isShown, updateGate.menuDidEndTracking() else { return }
        // Not here and now: the pop-up button sends its action after this
        // notification, and the refresh must not get in before the selection.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.pushPanelUpdate()
        }
    }

    private func snapshot() -> PanelSnapshot {
        guard let controller else { fatalError("the controller exists before anything asks for a snapshot") }
        return controller.panelSnapshot(
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

    @objc private func togglePanel() {
        #if TRACE
        Trace.log("ACTION  event=\(NSApp.currentEvent.map { "\($0.type.rawValue)#\($0.eventNumber)" } ?? "nil") active=\(NSApp.isActive) shown=\(popover.isShown) awaiting=\(panelToggle.awaitingActionOfClosingClick)")
        #endif
        switch panelToggle.statusItemAction(panelShown: popover.isShown) {
        case .open: showPanel()
        case .close: closePanel()
        case .none: syncClickMonitors()
        }
    }

    private func closePanel() {
        popover.performClose(nil)
        syncClickMonitors()
    }

    private func showPanel() {
        guard let button = statusItem?.button, controller != nil else { return }

        // Built on open and released on close: a SwiftUI tree that exists while
        // hidden keeps laying out.
        let model = PanelModel(snapshot: snapshot())
        model.changeSettings = { [weak self] in
            #if TRACE
            Trace.log("SETTINGS unit=\($0.unit) mode=\($0.displayMode) selection=\($0.selection) coloured=\($0.coloured)")
            #endif
            self?.controller?.settings = $0
        }
        model.setLoginItem = { [weak self] on in
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
            self.panelModel?.snapshot = self.snapshot()
        }
        model.quit = { NSApp.terminate(nil) }
        panelModel = model

        let hosting = NSHostingController(rootView: PanelView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // A status item click does not activate an accessory app, so the panel
        // opens without key status and its material is drawn inactive — visibly
        // dimmed. Taking key status brightens it. This is about drawing only; it
        // is not why the click monitors exist.
        hosting.view.window?.makeKey()
        // The panel has controls, so the app is activated now rather than by the
        // first click inside it: that click's activation arrived while the pop-up
        // menu it had just opened was tracking, and ended the menu 78 ms after it
        // began (measured). `makeKey()` alone does not activate the app.
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = frontmost
        }
        NSApp.activate(ignoringOtherApps: true)
        syncClickMonitors()
        #if TRACE
        Trace.log("SHOW    active=\(NSApp.isActive) key=\(hosting.view.window?.isKeyWindow ?? false)")
        #endif
    }

    /// `.transient` closes the panel only when the outside click lands in a window
    /// that takes activation. A click on an empty stretch of the menu bar, or on
    /// another app's non-activating panel, is missed — so outside clicks are
    /// watched explicitly. The monitors live while the panel is shown and, after
    /// a click on the item closed it, until that click's action has been dealt with.
    private func syncClickMonitors() {
        let needed = panelToggle.needsMonitor(panelShown: popover.isShown)
        if needed, clickMonitors.isEmpty {
            let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
            let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] event in
                // A global monitor's location is already in screen coordinates.
                // The event is not Sendable: read what is needed out here.
                let location = event.locationInWindow
                MainActor.assumeIsolated { self?.globalMouseDown(at: location) }
            }
            let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                let window = event.window, location = event.locationInWindow
                MainActor.assumeIsolated { self?.localMouseDown(in: window, at: location) }
                return event
            }
            clickMonitors = [global, local].compactMap { $0 }
        } else if !needed, !clickMonitors.isEmpty {
            clickMonitors.forEach(NSEvent.removeMonitor)
            clickMonitors = []
        }
    }

    /// Anything outside the app — which on macOS 27 includes our own status item,
    /// because another process hosts the menu bar.
    private func globalMouseDown(at location: CGPoint) {
        // The frame is read now: the item's width changes with the display mode.
        let onItem = statusItemOwns(location, itemWindowFrame: statusItem?.button?.window?.frame)
        #if TRACE
        Trace.log("GMON    onItem=\(onItem) shown=\(popover.isShown)")
        #endif
        if panelToggle.globalMouseDown(panelShown: popover.isShown, onStatusItem: onItem) == .close {
            popover.performClose(nil)
        }
        syncClickMonitors()
    }

    /// A mouse-down inside the app.
    private func localMouseDown(in window: NSWindow?, at location: NSPoint) {
        let click: PopoverClick
        if window === statusItem?.button?.window {
            click = .statusButton
        } else if let window, window === popover.contentViewController?.view.window
                    || window.parent === popover.contentViewController?.view.window {
            // The panel itself, or a menu one of its pickers opened.
            click = .insidePanel
        } else {
            click = .elsewhere
        }
        #if TRACE
        let hit = window?.contentView?.superview?.hitTest(location) ?? window?.contentView?.hitTest(location)
        Trace.log("LMON    click=\(click) key=\(window?.isKeyWindow ?? false) active=\(NSApp.isActive) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil") at=(\(Int(location.x)),\(Int(location.y))) window=\(window.map { String(describing: type(of: $0)) } ?? "nil")")
        #endif
        if click.closesPanel, popover.isShown { closePanel() }
    }

    func popoverDidClose(_ notification: Notification) {
        #if TRACE
        Trace.log("DIDCLOSE")
        #endif
        popover.contentViewController = nil
        panelModel = nil
        loginItemError = nil
        updateGate.reset()
        // An accessory app that stays active with no window leaves the user's
        // keystrokes going nowhere. If closing the panel did not activate
        // something else, hand activation back to whoever had it.
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        previousApp = nil
        // Also reached when `.transient` closed the panel on its own.
        syncClickMonitors()
    }
}

#if TRACE
/// Diagnostic build only (`swift build -Xswiftc -DTRACE`): records every mouse-down
/// and every button action, to find out which clicks never produce an action.
/// Never compiled into a release.
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
        log("START pid=\(ProcessInfo.processInfo.processIdentifier)")
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
            MainActor.assumeIsolated { delegate?.traceMouse("GLOBAL", type: type, number: number, location: location) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak delegate] event in
            let location = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
            let type = event.type.rawValue, number = event.eventNumber
            MainActor.assumeIsolated { delegate?.traceMouse("LOCAL ", type: type, number: number, location: location) }
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

extension AppDelegate {
    func traceMouse(_ source: String, type: UInt, number: Int, location: CGPoint) {
        let frame = traceItemFrame
        let onItem = statusItemOwns(location, itemWindowFrame: frame)
        Trace.log("\(source) type=\(type == 1 ? "down" : "up")#\(number) onItem=\(onItem) active=\(NSApp.isActive) shown=\(tracePanelShown)")
    }
}
#endif

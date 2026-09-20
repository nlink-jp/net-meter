import AppKit
import NetMeterCore
import NetMeterSystem
import NetMeterUI
import SwiftUI

/// Wiring only: the OS sources, the one-second timer, the status item and the
/// panel's window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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

    /// A non-activating panel (ADR-0003). The app never asks to be activated.
    private let panel = PanelWindow()
    /// Whether the panel is open is this boolean, set in `showPanel` and
    /// `hidePanel` and nowhere else — not something read back from the window.
    private var panelOpen = false
    #if TRACE
    var traceItemFrame: CGRect? { statusItem?.button?.window?.frame }
    var tracePanelShown: Bool { panelOpen }
    #endif
    /// Exists only while the panel is open.
    private var panelModel: PanelModel?
    /// What the content last said it needs; the window is placed from it.
    private var panelContentSize = CGSize(width: PanelView.width, height: 400)
    private var clickMonitors: [Any] = []
    /// One click on the status item reaches two handlers; see PanelToggle.
    private var panelToggle = PanelToggle()
    /// Refreshes wait while one of the panel's menus is open; see PanelUpdateGate.
    private var updateGate = PanelUpdateGate()
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

        panel.onCancel = { [weak self] in self?.hidePanel() }

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
            // panel hangs from. The item's window has not moved yet at this point,
            // so the panel is placed again on the next turn of the run loop.
            if panelOpen {
                DispatchQueue.main.async { [weak self] in self?.placePanel() }
            }
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
        if panelModel != nil { Trace.log("PUSH    unit=\(controller.settings.unit) mode=\(controller.settings.displayMode) held=\(updateGate.trackingDepth > 0) content=\(Int(panelContentSize.width))x\(Int(panelContentSize.height)) active=\(NSApp.isActive)") }
        #endif
        pushPanelUpdate()
    }

    // MARK: the panel

    private func pushPanelUpdate() {
        guard let panelModel, updateGate.shouldDeliverUpdate() else { return }
        panelModel.snapshot = snapshot()
    }

    @objc private func menuDidBeginTracking() {
        guard panelOpen else { return }
        updateGate.menuDidBeginTracking()
    }

    @objc private func menuDidEndTracking() {
        guard panelOpen, updateGate.menuDidEndTracking() else { return }
        // Not here and now: the pop-up button sends its action after this
        // notification, and the refresh must not get in before the selection.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panelOpen else { return }
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
        Trace.log("ACTION  event=\(NSApp.currentEvent.map { "\($0.type.rawValue)#\($0.eventNumber)" } ?? "nil") active=\(NSApp.isActive) shown=\(panelOpen) awaiting=\(panelToggle.awaitingActionOfClosingClick)")
        #endif
        switch panelToggle.statusItemAction(panelShown: panelOpen) {
        case .open: showPanel()
        case .close: hidePanel()
        case .none: syncClickMonitors()
        }
    }

    /// The one way the panel closes: a click elsewhere, a click on the item, Esc.
    /// Everything that was set up on open is undone here, so none of it can be
    /// skipped. Safe to call when the panel is already closed.
    private func hidePanel() {
        #if TRACE
        if panelOpen { Trace.log("HIDE") }
        #endif
        if panelOpen {
            panelOpen = false
            panel.orderOut(nil)
            panel.clearContent()
            panelModel = nil
            loginItemError = nil
            updateGate.reset()
        }
        syncClickMonitors()
    }

    /// Below the status item, within the screen the item is on.
    private func placePanel() {
        guard let button = statusItem?.button, let itemWindow = button.window else { return }
        let itemFrame = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = (itemWindow.screen ?? NSScreen.main)?.visibleFrame ?? itemFrame
        let frame = PanelPlacement.frame(itemFrame: itemFrame, panelSize: panelContentSize, visibleFrame: visible)
        if frame != panel.frame {
            panel.setFrame(frame, display: true)
            #if TRACE
            Trace.log("PLACE   frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
            #endif
        }
    }

    private func showPanel() {
        guard statusItem?.button != nil, controller != nil else { return }

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
        model.contentSizeChanged = { [weak self] size in
            guard let self, self.panelOpen, size != self.panelContentSize else { return }
            self.panelContentSize = size
            self.placePanel()
        }
        panelModel = model

        panelContentSize = panel.setContent(PanelView(model: model))
        placePanel()
        panelOpen = true
        // Key, so that Esc and text selection work — and nothing more than key:
        // the app is not activated and does not ask to be (ADR-0003). The first
        // release asked, and right after launch the OS refused; the first click in
        // the panel then activated the app and ended the menu it had just opened.
        panel.makeKeyAndOrderFront(nil)
        syncClickMonitors()
        #if TRACE
        Trace.log("SHOW    active=\(NSApp.isActive) key=\(panel.isKeyWindow) visible=\(panel.isVisible) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil")")
        #endif
    }

    /// Nothing tells a non-activating panel that the user clicked somewhere else,
    /// so outside clicks are watched explicitly. The monitors live while the panel
    /// is open and, after a click on the item closed it, until that click's action
    /// has been dealt with.
    private func syncClickMonitors() {
        let needed = panelToggle.needsMonitor(panelShown: panelOpen)
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
        Trace.log("GMON    onItem=\(onItem) shown=\(panelOpen)")
        #endif
        if panelToggle.globalMouseDown(panelShown: panelOpen, onStatusItem: onItem) == .close {
            hidePanel()
        } else {
            syncClickMonitors()
        }
    }

    /// A mouse-down inside the app.
    private func localMouseDown(in window: NSWindow?, at location: NSPoint) {
        let click: PanelClick
        if window === statusItem?.button?.window {
            click = .statusButton
        } else if let window, window === panel || window.parent === panel {
            // The panel itself, or a menu one of its pickers opened.
            click = .insidePanel
        } else {
            click = .elsewhere
        }
        #if TRACE
        let hit = window?.contentView?.superview?.hitTest(location) ?? window?.contentView?.hitTest(location)
        Trace.log("LMON    click=\(click) key=\(window?.isKeyWindow ?? false) active=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil") content=\(Int(panelContentSize.width))x\(Int(panelContentSize.height)) hit=\(hit.map { String(describing: type(of: $0)) } ?? "nil") at=(\(Int(location.x)),\(Int(location.y))) window=\(window.map { String(describing: type(of: $0)) } ?? "nil")")
        #endif
        if click.closesPanel, panelOpen { hidePanel() }
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

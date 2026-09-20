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
    /// Exists only while the panel is open.
    private var panelModel: PanelModel?
    private var clickMonitors: [Any] = []

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
    }

    @objc private func tick() {
        controller?.tick()
    }

    private func render() {
        guard let controller, let item = statusItem, let button = item.button else { return }
        let content = controller.content
        item.length = StatusRenderer.size(mode: content.mode, unit: content.unit).width

        // ADR-0002: the button reports the menu bar's own appearance, which can
        // differ from the system's.
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let finish: StatusFinish = controller.settings.coloured ? .coloured(darkMenuBar: dark) : .template
        let scale = button.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        button.image = StatusRenderer.image(content: content, finish: finish, scale: scale)
        button.setAccessibilityLabel("net-meter")
        button.setAccessibilityValue(UIStrings.spoken(content.reading, unit: content.unit))

        // The panel is only kept up to date while it is open.
        panelModel?.snapshot = snapshot()
    }

    // MARK: the panel

    private func snapshot() -> PanelSnapshot {
        guard let controller else { fatalError("the controller exists before anything asks for a snapshot") }
        return controller.panelSnapshot(
            info: infoSource.info(),
            pathOrder: pathMonitor.current,
            loginItem: loginItem.state,
            version: displayVersion(
                bundleShortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ),
            now: now()
        )
    }

    @objc private func togglePanel() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem?.button, controller != nil else { return }

        // Built on open and released on close: a SwiftUI tree that exists while
        // hidden keeps laying out.
        let model = PanelModel(snapshot: snapshot())
        model.changeSettings = { [weak self] in self?.controller?.settings = $0 }
        model.setLoginItem = { [weak self] on in
            guard let self else { return }
            do {
                try self.loginItem.set(on)
            } catch {
                NSLog("net-meter: launch at login could not be changed: \(error.localizedDescription)")
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
        installClickMonitors()
    }

    /// `.transient` closes the panel only when the outside click lands in a window
    /// that takes activation. A click on an empty stretch of the menu bar, or on
    /// another app's non-activating panel, is missed — so outside clicks are
    /// watched explicitly for as long as the panel is shown.
    private func installClickMonitors() {
        removeClickMonitors()
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        let global = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleClick(.elsewhere)
            }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            // The event is not Sendable: read what is needed out here.
            let window = event.window
            MainActor.assumeIsolated {
                guard let self else { return }
                let click: PopoverClick
                if window === self.statusItem?.button?.window {
                    click = .statusButton
                } else if let window, window === self.popover.contentViewController?.view.window
                            || window.parent === self.popover.contentViewController?.view.window {
                    // The panel itself, or a menu one of its pickers opened.
                    click = .insidePanel
                } else {
                    click = .elsewhere
                }
                self.handleClick(click)
            }
            return event
        }
        clickMonitors = [global, local].compactMap { $0 }
    }

    private func handleClick(_ click: PopoverClick) {
        if click.closesPanel, popover.isShown {
            popover.performClose(nil)
        }
    }

    private func removeClickMonitors() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    func popoverDidClose(_ notification: Notification) {
        removeClickMonitors()
        popover.contentViewController = nil
        panelModel = nil
    }
}

import AppKit
import NetMeterCore
import NetMeterSystem
import NetMeterUI

/// Wiring only: the OS sources, the one-second timer, the status item, and —
/// until the panel replaces it — a menu for the settings. The version stays
/// visible in whatever takes the menu's place.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var controller: MeterController?
    private let pathMonitor = PathOrderMonitor()
    private let infoSource = SystemInterfaceInfoSource()
    private var timer: Timer?
    /// Held for the app's lifetime: App Nap would otherwise freeze the timer of
    /// an app with no visible window, hours after launch.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Sampling network interface counters once a second"
        )

        // Seconds on a clock that keeps running during sleep (ADR-0001).
        let clock = ContinuousClock()
        let start = clock.now
        let controller = MeterController(
            counters: SysctlCounterSource(),
            pathOrder: { [pathMonitor] in pathMonitor.current },
            now: {
                let elapsed = clock.now - start
                return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            },
            store: UserDefaultsSettingsStore()
        )
        controller.onChange = { [weak self] in self?.render() }
        self.controller = controller

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        pathMonitor.start { [weak self] _ in
            Task { @MainActor in self?.controller?.refresh() }
        }

        // `.common`, not the default mode: the run loop leaves the default mode
        // while a menu is tracking, and the display would freeze exactly while
        // someone is looking at it.
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
    }

    // MARK: the interim settings menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let controller else { return }
        menu.removeAllItems()
        let settings = controller.settings
        let info = infoSource.info()
        let entries = InterfaceCatalog.entries(
            available: controller.meter.availableInterfaces,
            info: info,
            pathOrder: pathMonitor.current,
            selection: settings.selection
        )

        // What is on display right now.
        let heading: String
        switch controller.resolved {
        case .present(let name):
            let label = InterfaceCatalog.label(name: name, displayName: info[name]?.displayName)
            heading = settings.selection == .automatic ? UIStrings.automaticChoice(label) : label
        case .absent:
            if case .manual(let name) = settings.selection {
                heading = UIStrings.absent(InterfaceCatalog.label(name: name, displayName: info[name]?.displayName))
            } else {
                heading = UIStrings.noInterface
            }
        }
        menu.addItem(disabled(heading))
        menu.addItem(.separator())

        let interfaces = NSMenu()
        interfaces.addItem(choice(UIStrings.automatic, on: settings.selection == .automatic) { $0.selection = .automatic })
        interfaces.addItem(.separator())
        let others = NSMenu()
        for entry in entries {
            let title = entry.isAvailable ? entry.label : UIStrings.absent(entry.label)
            let item = choice(title, on: settings.selection == .manual(entry.name)) { $0.selection = .manual(entry.name) }
            (entry.isHardwarePort || !entry.isAvailable ? interfaces : others).addItem(item)
        }
        if others.numberOfItems > 0 {
            interfaces.addItem(.separator())
            interfaces.addItem(submenu(UIStrings.otherInterfaces, others))
        }
        menu.addItem(submenu(UIStrings.interface, interfaces))

        let display = NSMenu()
        for mode in DisplayMode.allCases {
            display.addItem(choice(UIStrings.displayMode(mode), on: settings.displayMode == mode) { $0.displayMode = mode })
        }
        menu.addItem(submenu(UIStrings.display, display))

        let units = NSMenu()
        for unit in RateUnit.allCases {
            units.addItem(choice(UIStrings.unit(unit), on: settings.unit == unit) { $0.unit = unit })
        }
        menu.addItem(submenu(UIStrings.unit, units))

        menu.addItem(choice(UIStrings.colour, on: settings.coloured) { $0.coloured.toggle() })

        menu.addItem(.separator())
        let version = displayVersion(
            bundleShortVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        )
        menu.addItem(disabled(UIStrings.version(version)))
        menu.addItem(NSMenuItem(title: UIStrings.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func choice(_ title: String, on: Bool, change: @escaping (inout AppSettings) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(applyChoice(_:)), keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        item.representedObject = SettingsChange(apply: change)
        return item
    }

    @objc private func applyChoice(_ sender: NSMenuItem) {
        guard let change = sender.representedObject as? SettingsChange, let controller else { return }
        var settings = controller.settings
        change.apply(&settings)
        controller.settings = settings
    }
}

/// A menu item's effect on the settings, boxed so it can ride in `representedObject`.
private final class SettingsChange {
    let apply: (inout AppSettings) -> Void
    init(apply: @escaping (inout AppSettings) -> Void) { self.apply = apply }
}

import AppKit
import NetMeterCore

/// Scaffold shell: a status item with a placeholder symbol and a menu that shows
/// the version and quits. The meter drawing and the panel replace this menu; the
/// version must stay visible somewhere when they do.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // The symbol goes in `button.image`: `isTemplate` is honoured only
            // there, and it is what makes the icon follow the menu bar's colour.
            if let image = NSImage(
                systemSymbolName: "arrow.up.arrow.down",
                accessibilityDescription: "net-meter"
            ) {
                image.isTemplate = true
                button.image = image
            } else {
                // A missing symbol must not leave an invisible item.
                button.title = "net-meter"
            }
        }
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let version = displayVersion(
            bundleShortVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String
        )
        let versionItem = NSMenuItem(title: "net-meter \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit net-meter",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        return menu
    }
}

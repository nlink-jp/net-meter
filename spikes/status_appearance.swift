// Spike: what a status item's button can tell the app about the menu bar it sits in.
//
// The coloured display mode cannot use a template image, so it has to pick a
// foreground colour itself. This prints what the button reports: its effective
// appearance, whether it has a window, and its size — next to the system-wide
// appearance. Creates a status item for two seconds, prints, and quits.
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let item = NSStatusBar.system.statusItem(withLength: 60)
item.button?.title = "probe"

DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    let button = item.button
    let match = button?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? "nil"
    print("system AppleInterfaceStyle : \(UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "(unset = light)")")
    print("NSApp.effectiveAppearance  : \(app.effectiveAppearance.name.rawValue)")
    print("button.effectiveAppearance : \(button?.effectiveAppearance.name.rawValue ?? "nil")  bestMatch=\(match)")
    print("button.window              : \(button?.window == nil ? "nil" : "present") frame=\(button?.window?.frame ?? .zero)")
    print("button.bounds              : \(button?.bounds ?? .zero)  statusBar.thickness=\(NSStatusBar.system.thickness)")
    print("backingScaleFactor         : \(button?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 0)")
    NSStatusBar.system.removeStatusItem(item)
    exit(0)
}
app.run()

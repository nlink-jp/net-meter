import AppKit
import SwiftUI

/// The window the panel lives in (ADR-0003).
///
/// `.nonactivatingPanel` is the point of this type. A click inside an ordinary
/// window of an accessory app activates the app, and that activation arrives while
/// the pop-up menu the click has just opened is tracking — and ends it (measured:
/// 71–78 ms after it began). Asking for activation beforehand is not an answer:
/// right after launch the OS refuses the request. A non-activating panel takes
/// clicks and key status while the app stays inactive, so there is nothing to
/// interrupt the menu and nothing to ask for.
public final class PanelWindow: NSPanel {
    /// Esc. Wired to the one close path by whoever owns the panel.
    public var onCancel: () -> Void = {}

    private var hosting: NSViewController?

    public init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelView.width, height: 400),
            // Titled with a hidden title bar, rather than borderless: the window
            // server then supplies the rounded corners and the shadow.
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovable = false
        isFloatingPanel = true
        level = .floating
        // Never `hidesOnDeactivate`: it hides the window without clearing
        // `isVisible`, and the app is not active to begin with.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Shown and hidden at once. Whether the panel is open is the owner's own
        // boolean; an animation would only put a gap between that and the screen.
        animationBehavior = .none
        // Over a full-screen app too, and on whichever Space the click happened in.
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
    }

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { false }

    override public func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// Puts `view` in the panel, on the popover material drawn as active — the app
    /// stays inactive, and a material that followed the window would look sunken.
    /// - Returns: the size the content wants at the panel's width.
    @discardableResult
    public func setContent<Content: View>(_ view: Content) -> CGSize {
        let controller = NSHostingController(rootView: view)
        // The title bar is hidden but still there, and it gives the content a safe
        // area 32 pt down from the top (measured: the content asked for 535 pt
        // instead of 503). The content starts at the window's top edge.
        // `ignoresSafeArea()` on the view does not do it: the size asked for
        // stayed at 535 pt (measured).
        controller.safeAreaRegions = []
        // The owner sizes the window from what the content reports; a hosting view
        // that also resized the window by itself would make two of them.
        controller.sizingOptions = []

        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active

        controller.view.frame = material.bounds
        controller.view.autoresizingMask = [.width, .height]
        material.addSubview(controller.view)

        contentView = material
        hosting = controller
        return controller.sizeThatFits(in: CGSize(width: PanelView.width, height: .greatestFiniteMagnitude))
    }

    /// Releases the content: a SwiftUI tree that exists while hidden keeps laying out.
    public func clearContent() {
        contentView = nil
        hosting = nil
    }

    public var hasContent: Bool { hosting != nil }
}

import CoreGraphics
import Foundation

/// Where the panel goes: directly below the status item, centred on it, and kept
/// inside the screen. All rectangles are in screen coordinates (bottom-left origin).
public enum PanelPlacement {
    /// Space between the menu bar and the panel.
    public static let gap: CGFloat = 6
    /// Space kept to the edges of the screen's visible frame.
    public static let margin: CGFloat = 8

    /// - Parameters:
    ///   - itemFrame: the status item button's frame on screen.
    ///   - panelSize: the size the panel wants.
    ///   - visibleFrame: the screen's visible frame — below the menu bar, clear of the Dock.
    /// - Returns: the panel's frame. Its size is reduced only if the screen is smaller.
    public static func frame(itemFrame: CGRect, panelSize: CGSize, visibleFrame: CGRect) -> CGRect {
        let width = min(panelSize.width, max(0, visibleFrame.width - margin * 2))
        let height = min(panelSize.height, max(0, visibleFrame.height - margin * 2))

        var x = itemFrame.midX - width / 2
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - margin - width)

        // Hang from just below the item; never poke out of the visible frame.
        var y = itemFrame.minY - gap - height
        y = min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - margin - height)

        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }
}

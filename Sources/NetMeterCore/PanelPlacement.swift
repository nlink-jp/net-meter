import CoreGraphics
import Foundation

/// Where the panel goes: directly below the status item, centred on it, and kept
/// inside the screen. All rectangles are in screen coordinates (bottom-left origin).
public enum PanelPlacement {
    /// Space between the item and the panel, and to the edges of the screen's
    /// visible frame. One number: the item's bottom edge *is* the visible frame's
    /// top edge, so two different distances there would mean only one ever applies.
    public static let margin: CGFloat = 8

    /// - Parameters:
    ///   - itemFrame: the status item button's frame on screen.
    ///   - panelSize: the size the panel wants.
    ///   - visibleFrame: the screen's visible frame — below the menu bar, clear of the Dock.
    /// - Returns: the panel's frame. Its size is reduced only if the screen is smaller.
    public static func frame(itemFrame: CGRect, panelSize: CGSize, visibleFrame: CGRect) -> CGRect {
        // Whole points, rounded up: a fractional height must not clip the last line.
        let width = min(panelSize.width.rounded(.up), max(0, (visibleFrame.width - margin * 2).rounded(.down)))
        let height = min(panelSize.height.rounded(.up), max(0, (visibleFrame.height - margin * 2).rounded(.down)))

        var x = itemFrame.midX - width / 2
        x = min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - margin - width)

        // The top edge is what is decided — and rounded — so that it stays where
        // it is when only the height changes. The panel hangs from it.
        let top = min(itemFrame.minY, visibleFrame.maxY) - margin
        let y = max(top.rounded() - height, visibleFrame.minY + margin)

        return CGRect(x: x.rounded(), y: y, width: width, height: height)
    }
}

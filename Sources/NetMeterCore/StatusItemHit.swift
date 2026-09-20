import CoreGraphics
import Foundation

/// Whether a mouse-down at `location` landed on the status item.
///
/// Both arguments are in screen coordinates (bottom-left origin): the location a
/// global event monitor is handed, and the frame of the status item button's
/// *window*, read at the time of the click — the item's width changes with the
/// display mode, so a frame read earlier may be stale.
///
/// The region is the one a sibling app measured on macOS 27.0: the item owns the
/// pixels of that window and nothing else, with the top-left convention the
/// pointer uses. The screen's top row — where a pointer pushed against the edge
/// sits, and which is exactly `frame.maxY` — belongs to the item; `frame.minY` is
/// the first row below the menu bar and `frame.maxX` the first column of the
/// neighbouring item. `CGRect.contains` gets both vertical edges the wrong way
/// round.
public func statusItemOwns(_ location: CGPoint, itemWindowFrame frame: CGRect?) -> Bool {
    guard let frame, !frame.isNull, !frame.isEmpty else { return false }
    let fromLeft = location.x - frame.minX
    let fromTop = frame.maxY - location.y
    return fromLeft >= 0 && fromLeft < frame.width && fromTop >= 0 && fromTop < frame.height
}

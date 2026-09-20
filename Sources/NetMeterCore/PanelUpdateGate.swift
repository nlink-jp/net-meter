/// Holds back updates to the panel while one of its menus is open.
///
/// The panel is refreshed once a second. A refresh that lands while a picker's
/// menu is tracking makes SwiftUI re-sync the pop-up button to the *current*
/// value, and the item the user then picks is reported as that old value: the
/// selection silently does not take (measured: the setter received the old unit
/// every time a refresh fell inside the tracking, three times out of three). So
/// refreshes wait until tracking ends, and one refresh is delivered then.
public struct PanelUpdateGate: Equatable, Sendable {
    public private(set) var trackingDepth = 0
    public private(set) var updatePending = false

    public init() {}

    public mutating func menuDidBeginTracking() {
        trackingDepth += 1
    }

    /// - Returns: whether a held-back update should be delivered now.
    public mutating func menuDidEndTracking() -> Bool {
        trackingDepth = max(0, trackingDepth - 1)
        guard trackingDepth == 0, updatePending else { return false }
        updatePending = false
        return true
    }

    /// - Returns: whether an update may be delivered now. If not, it is remembered.
    public mutating func shouldDeliverUpdate() -> Bool {
        guard trackingDepth > 0 else { return true }
        updatePending = true
        return false
    }

    /// The panel closed: nothing is tracking and nothing is owed any more.
    public mutating func reset() {
        self = PanelUpdateGate()
    }
}

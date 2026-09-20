/// Numbers as the panel shows them.
public enum PanelFormat {
    /// A byte total with SI prefixes: "0 KB", "12.3 MB", "1.23 GB".
    public static func bytes(_ total: UInt64) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(total) / 1_000
        var index = 0
        while value >= 999.5 && index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        if index == 0 { return "\(Int(value.rounded())) KB" }
        let digits = value < 9.995 ? 2 : (value < 99.95 ? 1 : 0)
        return "\(fixed(value, digits)) \(units[index])"
    }

    /// What an interface reports as its speed. Zero means it reports none — a
    /// virtual interface, typically — and that is shown as unknown, not as "0".
    /// The figure is what the interface says, not a ceiling on what it carries.
    public static func linkSpeed(_ bitsPerSecond: UInt64) -> String {
        guard bitsPerSecond > 0 else { return "—" }
        let units = ["kbps", "Mbps", "Gbps"]
        var value = Double(bitsPerSecond) / 1_000
        var index = 0
        while value >= 999.5 && index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        let rounded = (value * 10).rounded() / 10
        let digits = rounded == rounded.rounded() ? 0 : 1
        return "\(fixed(value, digits)) \(units[index])"
    }

    private static func fixed(_ value: Double, _ digits: Int) -> String {
        var scale = 1.0
        for _ in 0..<digits { scale *= 10 }
        let scaled = Int((value * scale).rounded())
        guard digits > 0 else { return String(scaled) }
        let whole = scaled / Int(scale), fraction = scaled % Int(scale)
        let padded = String(repeating: "0", count: digits - String(fraction).count) + String(fraction)
        return "\(whole).\(padded)"
    }
}

/// One bar of the panel's history chart. A second without a value has no bar.
public struct ChartPoint: Equatable, Sendable, Identifiable {
    /// Seconds before now, as a negative number: the chart's x position.
    public var offset: Double
    public var down: Double
    public var up: Double
    public var id: Double { offset }

    public init(offset: Double, down: Double, up: Double) {
        self.offset = offset
        self.down = down
        self.up = up
    }
}

public enum PanelHistory {
    /// Three minutes: fixed, so the chart never compresses as samples accumulate.
    public static let window = 180.0

    public static func points(from history: [HistoryPoint], now: Double, window: Double = PanelHistory.window) -> [ChartPoint] {
        history.compactMap { point in
            guard let rate = point.rate else { return nil }
            let offset = point.time - now
            guard offset <= 0, offset >= -window else { return nil }
            return ChartPoint(offset: offset, down: rate.downBytesPerSecond, up: rate.upBytesPerSecond)
        }
    }
}

/// Where a mouse-down landed while the panel is open, and whether that closes it.
///
/// The panel is a non-activating window (ADR-0003), so nothing tells the app that
/// the user has clicked somewhere else: the app watches mouse-downs itself. The
/// decision is kept here, away from AppKit, so it can be pinned by a test.
public enum PanelClick: Equatable, Sendable {
    /// The status item's own button: its action toggles the panel, so closing
    /// here as well would turn one click into close-then-reopen.
    case statusButton
    case insidePanel
    /// Another window of this app, or anything outside the app.
    case elsewhere

    public var closesPanel: Bool { self == .elsewhere }
}

/// Arbitrates between the two things that react to one click on the status item.
///
/// On macOS 27 the menu bar is hosted by another process, so a click on the app's
/// own status item reaches the *global* mouse-down monitor first and the button's
/// action a few tens of milliseconds later — or, when the app is active, sometimes
/// never (measured in a sibling app, nvme-lens, from which this type is ported).
/// Letting both act closes the panel and opens it again.
///
/// The two events cannot be matched by identity — the action runs under a
/// synthesized event whose number is always 0 — and they must not be matched by
/// time or by the window's own idea of being shown. Both were tried here, when the
/// panel was an `NSPopover`, and both failed on real hardware: with the default
/// close animation `isShown` stayed true for about 540 ms after
/// the close was requested, so at two clicks a second every other "open" click
/// was read as "close" and nothing opened. So they are matched by order: the
/// monitor closes the panel and notes that the click was on the item, and the
/// next action is that click's and is dropped. If no action comes, the note is
/// void as soon as another mouse-down is seen — which is why the monitor outlives
/// the panel until then.
///
/// Where a click on the item never reaches a global monitor, the note is never
/// taken and this is a plain toggle.
public struct PanelToggle: Equatable, Sendable {
    /// A mouse-down on the status item closed the panel, and that click's action
    /// has not arrived yet.
    public private(set) var awaitingActionOfClosingClick = false

    public enum Effect: Equatable, Sendable {
        case open
        case close
        case none
    }

    public init() {}

    /// A mouse-down seen by the global monitor.
    public mutating func globalMouseDown(panelShown: Bool, onStatusItem: Bool) -> Effect {
        guard panelShown else {
            // The monitor is only still here because an action was awaited, and a
            // new click has begun: that action is not coming any more.
            awaitingActionOfClosingClick = false
            return .none
        }
        awaitingActionOfClosingClick = onStatusItem
        return .close
    }

    /// The status item button's action.
    public mutating func statusItemAction(panelShown: Bool) -> Effect {
        if awaitingActionOfClosingClick {
            awaitingActionOfClosingClick = false
            return .none
        }
        return panelShown ? .close : .open
    }

    /// The monitor is needed while the panel is shown, and afterwards for as long
    /// as a closing click's action may still arrive.
    public func needsMonitor(panelShown: Bool) -> Bool {
        panelShown || awaitingActionOfClosingClick
    }
}

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

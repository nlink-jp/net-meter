/// Whether rates are shown in bytes or bits per second.
public enum RateUnit: String, Equatable, Sendable, CaseIterable {
    case bytes
    case bits
}

/// A rate ready to be drawn: the number and the unit are separate so the number
/// can be right-aligned in a fixed-width field.
public struct FormattedRate: Equatable, Sendable {
    /// At most `RateFormatter.numberWidth` characters.
    public var number: String
    public var unit: String

    public var text: String { "\(number) \(unit)" }

    public init(number: String, unit: String) {
        self.number = number
        self.unit = unit
    }
}

public enum RateFormatter {
    /// The widest number ever produced ("999", "9.9"). The status item's width
    /// is fixed from this, so the neighbouring icons never move.
    public static let numberWidth = 3

    /// What is drawn when there is no value: an absent interface, a discarded
    /// sample, the first second before a baseline exists.
    public static let noValue = "—"

    /// Every unit label `format` can produce for `unit`, smallest first. The
    /// status item reserves room for the widest of them.
    public static func units(for unit: RateUnit) -> [String] {
        switch unit {
        case .bytes: return ["KB/s", "MB/s", "GB/s"]
        case .bits: return ["kbps", "Mbps", "Gbps"]
        }
    }

    /// SI prefixes (1 MB = 1000 KB), matching Finder and Activity Monitor. The
    /// smallest unit is kilo: the byte counters are floored to 1 KiB, so
    /// anything finer would be invented precision.
    public static func format(bytesPerSecond: Double, unit: RateUnit) -> FormattedRate {
        let units = units(for: unit)
        var value = (unit == .bits ? bytesPerSecond * 8 : bytesPerSecond) / 1_000
        guard value.isFinite, value > 0 else { return FormattedRate(number: "0", unit: units[0]) }

        var index = 0
        // 999.5 would round to "1000", which is four characters: move up a unit first.
        while value >= 999.5 && index < units.count - 1 {
            value /= 1_000
            index += 1
        }
        return FormattedRate(number: number(value, allowDecimal: index > 0), unit: units[index])
    }

    private static func number(_ value: Double, allowDecimal: Bool) -> String {
        if allowDecimal && value < 9.95 {
            let tenths = Int((value * 10).rounded())
            return "\(tenths / 10).\(tenths % 10)"
        }
        // The top unit has nowhere further to go; keep the field width anyway.
        // Clamped as a Double: converting an unbounded Double to Int traps.
        return String(Int(min(value, 999).rounded()))
    }
}

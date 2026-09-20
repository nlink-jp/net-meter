/// What the menu bar item shows.
public enum DisplayMode: String, Equatable, Sendable, CaseIterable {
    case numbersAndGraph
    case numbersOnly
    case graphOnly

    public var showsNumbers: Bool { self != .graphOnly }
    public var showsGraph: Bool { self != .numbersOnly }
}

/// Everything the user can set. Persisted as plain strings so that a value this
/// build does not know — written by a newer one — falls back to the default
/// instead of failing the load.
public struct AppSettings: Equatable, Sendable {
    public var selection: InterfaceSelection = .automatic
    public var displayMode: DisplayMode = .numbersAndGraph
    public var unit: RateUnit = .bytes
    public var coloured = false

    public init() {}

    public enum Key {
        public static let interface = "interface"
        public static let displayMode = "displayMode"
        public static let unit = "unit"
        public static let coloured = "coloured"
    }

    public init(values: [String: String]) {
        selection = InterfaceSelection(storedValue: values[Key.interface])
        displayMode = values[Key.displayMode].flatMap(DisplayMode.init(rawValue:)) ?? .numbersAndGraph
        unit = values[Key.unit].flatMap(RateUnit.init(rawValue:)) ?? .bytes
        coloured = values[Key.coloured] == "true"
    }

    public var values: [String: String] {
        [
            Key.interface: selection.storedValue,
            Key.displayMode: displayMode.rawValue,
            Key.unit: unit.rawValue,
            Key.coloured: coloured ? "true" : "false",
        ]
    }
}

/// What there is to show for the interface on display. Three cases, not a rate
/// plus booleans: each one has to look different, and none of them is zero.
public enum MeterReading: Equatable, Sendable {
    /// The selected interface is not there (or automatic selection found none).
    case absent
    /// The interface is there but this second has no value: the first reading,
    /// or a sample that ADR-0001 discarded.
    case waiting
    case rate(down: Double, up: Double)
}

public func meterReading(resolved: ResolvedInterface, latest: SampleOutcome?) -> MeterReading {
    guard case .present = resolved else { return .absent }
    guard case .rate(let rate)? = latest else { return .waiting }
    return .rate(down: rate.downBytesPerSecond, up: rate.upBytesPerSecond)
}

/// One column of the menu bar graph.
public struct GraphColumn: Equatable, Sendable {
    public var down: Double
    public var up: Double

    public init(down: Double, up: Double) {
        self.down = down
        self.up = up
    }
}

public enum GraphWindow {
    /// 12 columns of 5 seconds: the "about 60 seconds" of the RFP, in bars wide
    /// enough to read at a glance on a 1x display.
    public static let columns = 12
    public static let secondsPerColumn = 5.0

    /// Buckets a history into columns, oldest first, the newest column ending at
    /// `now`. A column takes the highest rate in its bucket — a one-second burst
    /// must not be averaged away. A bucket with no valued sample is nil, so the
    /// graph leaves a gap instead of drawing zero.
    public static func columns(
        from history: [HistoryPoint],
        now: Double,
        count: Int = GraphWindow.columns,
        secondsPerColumn: Double = GraphWindow.secondsPerColumn
    ) -> [GraphColumn?] {
        var result = [GraphColumn?](repeating: nil, count: count)
        for point in history {
            guard let rate = point.rate else { continue }
            let age = now - point.time
            guard age >= 0 else { continue }
            let fromRight = Int(age / secondsPerColumn)
            guard fromRight < count else { continue }
            let index = count - 1 - fromRight
            let existing = result[index] ?? GraphColumn(down: 0, up: 0)
            result[index] = GraphColumn(
                down: max(existing.down, rate.downBytesPerSecond),
                up: max(existing.up, rate.upBytesPerSecond)
            )
        }
        return result
    }

    /// The scale for a set of columns: shared by both directions, with the floor.
    public static func fullScale(of columns: [GraphColumn?]) -> Double {
        let valued = columns.compactMap { $0 }
        return GraphScale.fullScale(down: valued.map(\.down), up: valued.map(\.up))
    }
}

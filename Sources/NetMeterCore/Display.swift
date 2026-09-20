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
    /// One bar per sample, fourteen of them: the graph moves left by exactly one
    /// bar every second, and a bar never changes once it is drawn. The three-minute
    /// view is the panel's job.
    ///
    /// Bars used to be time buckets — first measured back from `now`, then fixed to
    /// absolute five-second slots. Both looked wrong in motion: the graph stood
    /// still for seconds and then jumped, the newest bar kept changing height, and
    /// with one-second slots a jittery timer would leave holes and merge samples at
    /// slot edges. Counting samples has no edges to fall across.
    public static let columns = 14

    /// The last `count` history points, oldest first, padded on the left. A point
    /// without a value stays nil, so the graph leaves a gap instead of drawing zero.
    public static func columns(from history: [HistoryPoint], count: Int = GraphWindow.columns) -> [GraphColumn?] {
        let recent = history.suffix(count).map { point in
            point.rate.map { GraphColumn(down: $0.downBytesPerSecond, up: $0.upBytesPerSecond) }
        }
        return [GraphColumn?](repeating: nil, count: max(0, count - recent.count)) + recent
    }

    /// The scale for a set of columns: shared by both directions, with the floor.
    public static func fullScale(of columns: [GraphColumn?]) -> Double {
        let valued = columns.compactMap { $0 }
        return GraphScale.fullScale(down: valued.map(\.down), up: valued.map(\.up))
    }
}

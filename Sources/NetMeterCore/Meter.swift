/// One point of an interface's history. `rate` is nil where there was no value —
/// a first reading or a discarded sample — so a graph can leave a gap there
/// instead of drawing zero.
public struct HistoryPoint: Equatable, Sendable {
    public var time: Double
    public var rate: Rate?

    public init(time: Double, rate: Rate?) {
        self.time = time
        self.rate = rate
    }
}

/// Bytes moved since launch, summed from accepted samples only.
public struct TransferTotals: Equatable, Sendable {
    public var downBytes: UInt64 = 0
    public var upBytes: UInt64 = 0

    public init(downBytes: UInt64 = 0, upBytes: UInt64 = 0) {
        self.downBytes = downBytes
        self.upBytes = upBytes
    }
}

/// Keeps a baseline, a history and running totals for every interface, so that
/// switching the displayed interface shows real history at once.
///
/// Time is a number of seconds supplied by the caller, from a clock that keeps
/// running during sleep; the meter never reads a clock itself.
public struct Meter: Sendable {
    /// Three minutes at one sample per second: the panel's history window.
    public static let defaultHistoryCapacity = 180

    private struct Track: Sendable {
        var baseline: InterfaceCounters?
        var baselineTime = 0.0
        var history: RingBuffer<HistoryPoint>
        var totals = TransferTotals()
        var latest: SampleOutcome?
    }

    private var tracks: [String: Track] = [:]
    private let historyCapacity: Int

    public init(historyCapacity: Int = Meter.defaultHistoryCapacity) {
        self.historyCapacity = historyCapacity
    }

    /// Feeds one reading of every interface.
    /// - Returns: the outcome per interface present in the reading.
    @discardableResult
    public mutating func ingest(_ reading: [String: InterfaceCounters], at time: Double) -> [String: SampleOutcome] {
        // An empty reading is a failed read, not "every interface vanished".
        guard !reading.isEmpty else { return [:] }

        // An interface that is gone loses its baseline: when it comes back —
        // a tunnel re-created, an adapter replugged — it starts from rule 1.
        for name in tracks.keys where reading[name] == nil {
            tracks[name]?.baseline = nil
            tracks[name]?.latest = nil
        }

        var outcomes: [String: SampleOutcome] = [:]
        for (name, counters) in reading {
            var track = tracks[name] ?? Track(history: RingBuffer(capacity: historyCapacity))
            let outcome = RateRule.evaluate(
                previous: track.baseline,
                current: counters,
                elapsed: time - track.baselineTime
            )
            if outcome.movesBaseline {
                track.baseline = counters
                track.baselineTime = time
            }
            switch outcome {
            case .tooSoon:
                break  // nothing happened as far as the history is concerned
            case .rate(let rate):
                track.totals.downBytes += rate.downBytes
                track.totals.upBytes += rate.upBytes
                track.history.append(HistoryPoint(time: time, rate: rate))
                track.latest = outcome
            case .baseline, .discarded:
                track.history.append(HistoryPoint(time: time, rate: nil))
                track.latest = outcome
            }
            tracks[name] = track
            outcomes[name] = outcome
        }
        return outcomes
    }

    /// The most recent outcome, or nil for an interface that is not there.
    public func latest(for name: String) -> SampleOutcome? { tracks[name]?.latest }

    /// Oldest first.
    public func history(for name: String) -> [HistoryPoint] { tracks[name]?.history.elements ?? [] }

    public func totals(for name: String) -> TransferTotals { tracks[name]?.totals ?? TransferTotals() }

    /// The highest rates among the history points newer than `since`.
    public func peak(for name: String, since: Double = -.infinity) -> (down: Double, up: Double) {
        let rates = history(for: name).filter { $0.time >= since }.compactMap(\.rate)
        return (rates.map(\.downBytesPerSecond).max() ?? 0, rates.map(\.upBytesPerSecond).max() ?? 0)
    }

    /// What the interface reports as its speed, in bits per second; 0 when it
    /// reports none or is not there.
    public func linkSpeed(for name: String) -> UInt64 { tracks[name]?.baseline?.linkSpeed ?? 0 }

    /// Interfaces that had counters in the last reading.
    public var availableInterfaces: Set<String> {
        Set(tracks.filter { $0.value.baseline != nil }.keys)
    }
}

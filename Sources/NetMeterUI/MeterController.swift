import NetMeterCore

/// Turns readings into what is on display. Everything it needs from the OS is
/// passed in, so it runs in a test exactly as it runs in the app.
@MainActor
public final class MeterController {
    private let counters: CounterSource
    private let pathOrder: () -> [PathInterface]
    private let now: () -> Double
    private let store: SettingsStore

    public private(set) var meter = Meter()
    public private(set) var resolved: ResolvedInterface = .absent
    public private(set) var content: StatusContent
    /// The scale the graph was last drawn with, and for which interface.
    private var graphScale = GraphScale.defaultFloor
    private var graphScaleInterface: String?

    /// Called whenever `content` may have changed: after a tick, and at once
    /// after a settings change — a setting must not wait for the next tick to
    /// reach the menu bar.
    public var onChange: (() -> Void)?

    public var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            store.save(settings)
            refresh()
        }
    }

    /// - Parameters:
    ///   - pathOrder: the OS interface preference order, as it is right now.
    ///   - now: seconds on a clock that keeps running during sleep.
    public init(
        counters: CounterSource,
        pathOrder: @escaping () -> [PathInterface],
        now: @escaping () -> Double,
        store: SettingsStore
    ) {
        self.counters = counters
        self.pathOrder = pathOrder
        self.now = now
        self.store = store
        let loaded = store.load()
        settings = loaded
        content = StatusContent(reading: .absent, columns: [], mode: loaded.displayMode, unit: loaded.unit)
    }

    /// One reading of every interface. Call once a second.
    public func tick() {
        meter.ingest(counters.read(), at: now())
        refresh(newSample: true)
    }

    /// Recomputes what is on display from what is already known. Also called
    /// when the interface preference order changes.
    public func refresh() {
        refresh(newSample: false)
    }

    private func refresh(newSample: Bool) {
        resolved = resolveInterface(
            selection: settings.selection,
            pathOrder: pathOrder(),
            available: meter.availableInterfaces
        )
        var columns: [GraphColumn?] = []
        var latest: SampleOutcome?
        var interface: String?
        if case .present(let name) = resolved {
            interface = name
            latest = meter.latest(for: name)
            columns = GraphWindow.columns(from: meter.history(for: name))
        }
        let target = GraphWindow.fullScale(of: columns)
        if interface != graphScaleInterface {
            // Another interface: its graph is not judged by the last one's peaks.
            graphScale = target
            graphScaleInterface = interface
        } else if newSample {
            // Eased once per sample, not once per redraw: a settings change must
            // not speed the scale up.
            graphScale = GraphScale.eased(previous: graphScale, target: target)
        } else {
            graphScale = max(graphScale, target)
        }
        content = StatusContent(
            reading: meterReading(resolved: resolved, latest: latest),
            columns: columns,
            fullScale: graphScale,
            mode: settings.displayMode,
            unit: settings.unit
        )
        onChange?()
    }
}

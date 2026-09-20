import Combine
import NetMeterCore

/// Everything the panel shows at one moment, as a value.
public struct PanelSnapshot: Equatable, Sendable {
    public var heading: String
    public var isAutomatic: Bool
    public var reading: MeterReading
    public var addresses: [String]
    public var linkSpeed: String
    public var peakDown: Double
    public var peakUp: Double
    public var totals: TransferTotals
    public var points: [ChartPoint]
    public var fullScale: Double
    public var settings: AppSettings
    public var entries: [InterfaceListEntry]
    public var loginItem: LoginItemState
    public var version: String

    public init(heading: String, isAutomatic: Bool, reading: MeterReading, addresses: [String], linkSpeed: String,
                peakDown: Double, peakUp: Double, totals: TransferTotals, points: [ChartPoint], fullScale: Double,
                settings: AppSettings, entries: [InterfaceListEntry], loginItem: LoginItemState, version: String) {
        self.heading = heading
        self.isAutomatic = isAutomatic
        self.reading = reading
        self.addresses = addresses
        self.linkSpeed = linkSpeed
        self.peakDown = peakDown
        self.peakUp = peakUp
        self.totals = totals
        self.points = points
        self.fullScale = fullScale
        self.settings = settings
        self.entries = entries
        self.loginItem = loginItem
        self.version = version
    }
}

/// The one object the panel observes. The settings are part of the snapshot on
/// purpose: a view that observed the values and the settings through two
/// different objects would miss changes to the one it was not watching.
@MainActor
public final class PanelModel: ObservableObject {
    @Published public var snapshot: PanelSnapshot
    public var changeSettings: (AppSettings) -> Void = { _ in }
    public var setLoginItem: (Bool) -> Void = { _ in }
    public var quit: () -> Void = {}

    public init(snapshot: PanelSnapshot) {
        self.snapshot = snapshot
    }
}

extension MeterController {
    /// - Parameters:
    ///   - info: display names and addresses, read by the caller.
    ///   - pathOrder: the same order the controller resolves against.
    public func panelSnapshot(
        info: [String: InterfaceInfo],
        pathOrder: [PathInterface],
        loginItem: LoginItemState,
        version: String,
        now: Double
    ) -> PanelSnapshot {
        var heading = UIStrings.noInterface
        var addresses: [String] = []
        var linkSpeed = UIStrings.none
        var peak = (down: 0.0, up: 0.0)
        var totals = TransferTotals()
        var points: [ChartPoint] = []

        switch resolved {
        case .present(let name):
            heading = InterfaceCatalog.label(name: name, displayName: info[name]?.displayName)
            addresses = info[name]?.addresses ?? []
            linkSpeed = PanelFormat.linkSpeed(meter.linkSpeed(for: name))
            peak = meter.peak(for: name, since: now - PanelHistory.window)
            totals = meter.totals(for: name)
            points = PanelHistory.points(from: meter.history(for: name), now: now)
        case .absent:
            if case .manual(let name) = settings.selection {
                heading = UIStrings.absent(InterfaceCatalog.label(name: name, displayName: info[name]?.displayName))
            }
        }
        return PanelSnapshot(
            heading: heading,
            isAutomatic: settings.selection == .automatic,
            reading: content.reading,
            addresses: addresses,
            linkSpeed: linkSpeed,
            peakDown: peak.down,
            peakUp: peak.up,
            totals: totals,
            points: points,
            fullScale: GraphScale.fullScale(down: points.map(\.down), up: points.map(\.up)),
            settings: settings,
            entries: InterfaceCatalog.entries(available: meter.availableInterfaces, info: info,
                                              pathOrder: pathOrder, selection: settings.selection),
            loginItem: loginItem,
            version: version
        )
    }
}

import Charts
import NetMeterCore
import SwiftUI

/// The panel behind the menu bar item. Its width is fixed; its height is whatever
/// the content needs, and the window is sized to it.
public struct PanelView: View {
    /// Wide enough for an IPv6 address that has no run of zeros to compress — 39
    /// characters — on one line in `addressFontSize` monospaced, with room to
    /// spare. A test measures it.
    public static let width: CGFloat = 320
    public static let padding: CGFloat = 14
    public static let addressFontSize: CGFloat = 11
    /// More than this many addresses are summarised as "+N more".
    public static let addressLimit = 4

    @ObservedObject var model: PanelModel

    public init(model: PanelModel) {
        self.model = model
    }

    private var snapshot: PanelSnapshot { model.snapshot }
    private static let upColour = Color(red: 0.86, green: 0.30, blue: 0.30)
    private static let downColour = Color(red: 0.18, green: 0.64, blue: 0.40)

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            current
            chart
            addresses
            details
            Divider()
            settings
            Divider()
            footer
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        // The height the content needs, whatever height the window offers:
        // `MenuBarExtra` sizes its window to the content's ideal size (ADR-0004).
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: sections

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(snapshot.heading)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(snapshot.isAutomatic ? UIStrings.automatic : UIStrings.manual)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var current: some View {
        HStack(spacing: 16) {
            currentValue("↑", colour: Self.upColour, value: upText)
            currentValue("↓", colour: Self.downColour, value: downText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func currentValue(_ arrow: String, colour: Color, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(arrow).foregroundStyle(colour).font(.title3.weight(.semibold))
            Text(value).font(.title3.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var upText: String {
        if case .rate(_, let up) = snapshot.reading { return rate(up) }
        return snapshot.reading == .waiting ? UIStrings.measuring : UIStrings.none
    }

    private var downText: String {
        if case .rate(let down, _) = snapshot.reading { return rate(down) }
        return UIStrings.none
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        RateFormatter.format(bytesPerSecond: bytesPerSecond, unit: snapshot.settings.unit).text
    }

    private var chart: some View {
        let full = snapshot.fullScale
        return Chart {
            ForEach(snapshot.points) { point in
                BarMark(x: .value("t", point.offset), y: .value("up", point.up), width: .fixed(1.3))
                    .foregroundStyle(Self.upColour)
                BarMark(x: .value("t", point.offset), y: .value("down", -point.down), width: .fixed(1.3))
                    .foregroundStyle(Self.downColour)
            }
            RuleMark(y: .value("zero", 0))
                .foregroundStyle(Color.secondary.opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 0.5))
        }
        // A fixed window and a fixed, shared scale: the chart never compresses as
        // samples accumulate, and the two directions stay comparable.
        .chartXScale(domain: -PanelHistory.window...0)
        .chartYScale(domain: -full...full)
        .chartXAxis {
            AxisMarks(values: [-180.0, -120.0, -60.0, 0.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(seconds == 0 ? UIStrings.chartNow : UIStrings.minutesAgo(Int(-seconds / 60)))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [-full, 0, full]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let y = value.as(Double.self), y != 0 { Text(rate(abs(y))) }
                }
            }
        }
        .frame(height: 96)
        .opacity(snapshot.reading == .absent ? 0.35 : 1)
    }

    /// Addresses get the panel's full width, not a cell of the table below: next
    /// to the label column an IPv6 address had 158 pt and needs up to 265.
    private var addresses: some View {
        VStack(alignment: .leading, spacing: 2) {
            label(UIStrings.address)
            // One Text per address: a joined string was laid out as a single
            // truncated line.
            ForEach(snapshot.addresses.isEmpty ? [UIStrings.none] : Array(snapshot.addresses.prefix(Self.addressLimit)), id: \.self) {
                Text($0)
                    .font(.system(size: Self.addressFontSize, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            if snapshot.addresses.count > Self.addressLimit {
                Text(UIStrings.moreAddresses(snapshot.addresses.count - Self.addressLimit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var details: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                label(UIStrings.linkSpeed)
                Text(snapshot.linkSpeed).font(.callout.monospacedDigit())
            }
            GridRow {
                label(UIStrings.peak)
                Text("↑ \(rate(snapshot.peakUp))   ↓ \(rate(snapshot.peakDown))").font(.callout.monospacedDigit())
            }
            GridRow {
                label(UIStrings.total)
                Text("↑ \(PanelFormat.bytes(snapshot.totals.upBytes))   ↓ \(PanelFormat.bytes(snapshot.totals.downBytes))")
                    .font(.callout.monospacedDigit())
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    /// One width for every settings label, so the controls line up.
    private static let settingsLabelWidth: CGFloat = 62

    private func settingsRow<Control: View>(_ title: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            label(title).frame(width: Self.settingsLabelWidth, alignment: .leading)
            // The control gets the rest of the row, so a menu button is as wide
            // as its longest choice instead of being squeezed and truncated.
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            settingsRow(UIStrings.interface) {
                Picker("", selection: binding(\.selection.storedValue) { $0.selection = InterfaceSelection(storedValue: $1) }) {
                    Text(UIStrings.automatic).tag("")
                    Divider()
                    // Hardware ports first — and an absent manual choice with them, so
                    // it is never buried; tunnels, bridges and the like in their own section.
                    ForEach(snapshot.entries.filter { $0.isHardwarePort || !$0.isAvailable }, id: \.name) { entry in
                        Text(entry.isAvailable ? entry.label : UIStrings.absent(entry.label)).tag(entry.name)
                    }
                    let others = snapshot.entries.filter { !$0.isHardwarePort && $0.isAvailable }
                    if !others.isEmpty {
                        Section(UIStrings.otherInterfaces) {
                            ForEach(others, id: \.name) { entry in
                                Text(entry.label).tag(entry.name)
                            }
                        }
                    }
                }
                .labelsHidden()
            }
            settingsRow(UIStrings.display) {
                Picker("", selection: binding(\.displayMode) { $0.displayMode = $1 }) {
                    ForEach(DisplayMode.allCases, id: \.self) { Text(UIStrings.displayMode($0)).tag($0) }
                }
                .labelsHidden()
            }
            settingsRow(UIStrings.unit) {
                Picker("", selection: binding(\.unit) { $0.unit = $1 }) {
                    ForEach(RateUnit.allCases, id: \.self) { Text(UIStrings.unit($0)).tag($0) }
                }
                .labelsHidden()
            }
            settingsRow("") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(UIStrings.colour, isOn: binding(\.coloured) { $0.coloured = $1 })
                    Toggle(UIStrings.launchAtLogin, isOn: Binding(
                        get: { snapshot.loginItem.isOn },
                        set: { model.setLoginItem($0) }
                    ))
                    // "Not registered yet" is not "cannot": only a missing bundle disables this.
                    .disabled(snapshot.loginItem == .unavailable)
                    // A toggle that springs back without a word is the worst outcome:
                    // say why, here, where it happened.
                    if let error = snapshot.loginItemError {
                        Text(UIStrings.loginItemFailed(error)).font(.caption).foregroundStyle(.red)
                    }
                    if snapshot.loginItem == .requiresApproval {
                        Text(UIStrings.approveLoginItem).font(.caption).foregroundStyle(.secondary)
                    } else if snapshot.loginItem == .unavailable {
                        Text(UIStrings.loginItemUnavailable).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        }
        .pickerStyle(.menu)
    }

    /// A binding that reads from the snapshot and writes a whole new settings
    /// value back, so a change takes effect at once and in one place.
    private func binding<Value>(_ keyPath: KeyPath<AppSettings, Value>,
                                _ change: @escaping (inout AppSettings, Value) -> Void) -> Binding<Value> {
        Binding(
            get: { snapshot.settings[keyPath: keyPath] },
            set: { newValue in
                var settings = snapshot.settings
                change(&settings, newValue)
                model.changeSettings(settings)
            }
        )
    }

    private var footer: some View {
        HStack {
            // Verbatim and selectable: a bug report has to be able to name the build.
            Text(UIStrings.version(snapshot.version))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
            Button(UIStrings.quitShort) { model.quit() }
                .controlSize(.small)
                .focusable(false)
        }
    }
}

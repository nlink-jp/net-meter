import NetMeterCore

/// Every string the user can read, in one place. One language throughout — a UI
/// that mixes languages is a defect, and a second language would be added here as
/// a complete second catalogue with a test that both sides have every key.
public enum UIStrings {
    public static let automatic = "Automatic"
    public static let interface = "Interface"
    public static let display = "Display"
    public static let unit = "Unit"
    public static let colour = "Colour up and down"
    public static let otherInterfaces = "Other interfaces"
    public static let noInterface = "No network interface"

    public static func displayMode(_ mode: DisplayMode) -> String {
        switch mode {
        case .numbersAndGraph: return "Numbers and Graph"
        case .numbersOnly: return "Numbers Only"
        case .graphOnly: return "Graph Only"
        }
    }

    public static func unit(_ unit: RateUnit) -> String {
        switch unit {
        case .bytes: return "Bytes (MB/s)"
        case .bits: return "Bits (Mbps)"
        }
    }

    public static func absent(_ label: String) -> String { "\(label) — not connected" }
    public static func version(_ version: String) -> String { "net-meter \(version)" }

    // The panel
    public static let manual = "Manual"
    public static let address = "Address"
    public static func moreAddresses(_ count: Int) -> String { "+\(count) more" }
    public static let linkSpeed = "Link speed"
    public static let peak = "Peak, last 3 min"
    public static let total = "Total since launch"
    public static let launchAtLogin = "Launch at login"
    public static let approveLoginItem = "Approve in System Settings › Login Items"
    public static let loginItemUnavailable = "Available when running from the app bundle"
    public static func loginItemFailed(_ reason: String) -> String { "Could not change it: \(reason)" }
    public static let quitShort = "Quit"
    public static let none = "—"
    public static let measuring = "Measuring…"
    public static let chartNow = "now"
    public static func minutesAgo(_ minutes: Int) -> String { "\(minutes) min" }

    /// What VoiceOver reads, and what a script can read from the accessibility tree.
    public static func spoken(_ reading: MeterReading, unit: RateUnit) -> String {
        switch reading {
        case .absent: return "No network interface"
        case .waiting: return "Measuring"
        case .rate(let down, let up):
            let u = RateFormatter.format(bytesPerSecond: up, unit: unit).text
            let d = RateFormatter.format(bytesPerSecond: down, unit: unit).text
            return "Up \(u), down \(d)"
        }
    }
}

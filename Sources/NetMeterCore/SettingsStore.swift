/// Where settings are kept. The real store is `UserDefaults`; tests use the
/// in-memory one.
public protocol SettingsStore: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: String]

    public init(_ settings: AppSettings = AppSettings()) {
        values = settings.values
    }

    public func load() -> AppSettings { AppSettings(values: values) }
    public func save(_ settings: AppSettings) { values = settings.values }
}

import Foundation
import NetMeterCore

/// Settings in `UserDefaults`, one string per key. There is no configuration file.
public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private static let keys = [
        AppSettings.Key.interface, AppSettings.Key.displayMode, AppSettings.Key.unit, AppSettings.Key.coloured,
    ]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        var values: [String: String] = [:]
        for key in Self.keys {
            values[key] = defaults.string(forKey: key)
        }
        return AppSettings(values: values)
    }

    public func save(_ settings: AppSettings) {
        for (key, value) in settings.values {
            defaults.set(value, forKey: key)
        }
    }
}

import Foundation
import NetMeterCore
import NetMeterSystem
import XCTest

final class UserDefaultsSettingsStoreTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "jp.nlink.net-meter.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testAFreshDomainLoadsTheDefaults() {
        XCTAssertEqual(UserDefaultsSettingsStore(defaults: defaults).load(), AppSettings())
    }

    func testSettingsSurviveARoundTripThroughANewStore() {
        var settings = AppSettings()
        settings.selection = .manual("en1")
        settings.displayMode = .graphOnly
        settings.unit = .bits
        settings.coloured = true
        UserDefaultsSettingsStore(defaults: defaults).save(settings)
        XCTAssertEqual(UserDefaultsSettingsStore(defaults: defaults).load(), settings)
    }

    func testAValueFromANewerBuildFallsBackInsteadOfFailingTheLoad() {
        defaults.set("hologram", forKey: AppSettings.Key.displayMode)
        defaults.set(42, forKey: AppSettings.Key.unit)  // not even a string
        XCTAssertEqual(UserDefaultsSettingsStore(defaults: defaults).load(), AppSettings())
    }
}

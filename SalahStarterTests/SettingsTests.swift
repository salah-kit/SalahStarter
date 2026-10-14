import Foundation
import SalahCalculation
import SalahTimes
import SalahUI
import SalahWidgets
import Testing
import os

@testable import SalahStarter

/// The settings the app shares with the widget, and the App Group they travel through.
@MainActor
@Suite("Settings and the App Group")
struct SettingsTests {
  /// The widget kinds each save asked WidgetKit to reload.
  nonisolated final class Reloads: Sendable {
    private let kinds = OSAllocatedUnfairLock<[[String]]>(initialState: [])

    var all: [[String]] { kinds.withLock { $0 } }

    func record(_ widgetKinds: [String]) {
      kinds.withLock { $0.append(widgetKinds) }
    }
  }

  /// A shared value under a key of its own, in the real App Group, that records reloads.
  static func sharedValue(_ reloads: Reloads) -> SharedValue<PrayerSettings> {
    SharedValue(
      appGroup: AppIdentity.appGroup, key: "test.\(UUID().uuidString)",
      reloadTimelines: { reloads.record($0) })
  }

  /// A model on a test value, with alerts on a center that records everything.
  static func model(_ shared: SharedValue<PrayerSettings>) -> AppModel {
    let options = SharedValue<AlertOptions>(
      appGroup: AppIdentity.appGroup, key: "test.\(UUID().uuidString)")
    return AppModel(
      shared: shared,
      alerts: AlertCoordinator(shared: options, center: FakeCenter(), permissions: .never))
  }

  @Test("the App Group comes from the build, and the app is entitled to it")
  func appGroup() throws {
    // Config/Identity.xcconfig's APP_GROUP_IDENTIFIER, through the Info.plist.
    #expect(AppIdentity.appGroup.hasPrefix("group."))
    // Only an app whose entitlements name the group gets its container.
    #expect(
      FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppIdentity.appGroup) != nil)
    #expect(UserDefaults(suiteName: AppIdentity.appGroup) != nil)
  }

  @Test("choosing a place saves the settings and reloads the widget; the same choice doesn't")
  func reloadGating() async throws {
    let reloads = Reloads()
    let shared = Self.sharedValue(reloads)
    defer { _ = try? shared.save(nil) }
    let model = Self.model(shared)
    #expect(model.settings == nil)

    await model.choose(.istanbul).value
    #expect(shared.load() == model.settings)
    #expect(model.settings?.place == .istanbul)
    #expect(reloads.all == [[AppIdentity.widgetKind]])

    // The same place again: nothing changed, nothing to reload.
    await model.choose(.istanbul).value
    #expect(reloads.all.count == 1)

    await model.choose(.hanafi).value
    #expect(shared.load()?.madhab == .hanafi)
    #expect(reloads.all.count == 2)
    #expect(model.saveError == nil)

    // A new launch reads what the last one saved.
    #expect(Self.model(shared).settings == model.settings)
  }

  @Test("a place brings its suggested method, and a method keeps the madhab")
  func methods() {
    var settings = PrayerSettings(place: .istanbul)
    #expect(settings.method == .diyanet)
    #expect(settings.calculation == CalculationSettings(method: .diyanet))
    settings.madhab = .hanafi
    settings.choose(.muslimWorldLeague)
    #expect(
      settings.calculation == CalculationSettings(method: .muslimWorldLeague, madhab: .hanafi))
    settings.move(to: .makkah)
    #expect(settings.method == .ummAlQura)
    #expect(settings.madhab == .hanafi)
    // Every preset has a country, so a suggestion or the Muslim World League's method.
    for place in Place.presets {
      #expect(place.location.countryCode != nil)
      #expect(PrayerSettings(place: place).schedule.day(containing: TimelineTests.start).day != nil)
    }
  }

  @Test("the stored settings keep every calculation parameter")
  func codable() throws {
    var settings = PrayerSettings(place: .london, method: .moonsightingCommittee)
    settings.calculation.parameters.fajr = .angle(16)
    let data = try JSONEncoder().encode(settings)
    #expect(try JSONDecoder().decode(PrayerSettings.self, from: data) == settings)
  }

  @Test("every text color passes SalahUI's contrast check, in light and dark")
  func palette() {
    for palette in [Palette.light, Palette.dark] {
      // Body text and the countdown: WCAG's 4.5:1 for text.
      let text = ContrastCheck(minimumContrast: 4.5)
      for ink in [palette.ink, palette.secondaryInk, palette.accent] {
        #expect(text.problems(foreground: ink, background: palette.surface, reserved: []).isEmpty)
      }
    }
  }

  @Test("the widget's words and the place names are translated into Arabic")
  func arabic() throws {
    let path = try #require(Bundle.main.path(forResource: "ar", ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    let arabic = Locale(identifier: "ar")
    #expect(String(localized: "Choose a place", bundle: bundle, locale: arabic) == "اختر مكانًا")
    #expect(String(localized: "Makkah", bundle: bundle, locale: arabic) == "مكة المكرمة")
  }
}

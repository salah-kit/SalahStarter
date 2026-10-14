import Foundation
import SalahCalculation
import SalahCore
import SalahTimes
import SalahWidgets

/// Everything the widget needs, saved by the app and read by the widget extension.
///
/// The extension builds its own schedule from these inputs whenever WidgetKit asks for a
/// timeline, so the widget stays right on the days the app isn't opened. Keep the value small
/// and limited to what the widget needs: the app saves it on every change, and a changed value
/// reloads the widget.
nonisolated struct PrayerSettings: Codable, Hashable, Sendable {
  /// Where to calculate.
  var place: Place
  /// The published method the calculation started from, which the method picker shows.
  var method: CalculationMethod
  /// Every calculation parameter, passed to SalahTimes unchanged. Change any of them, such as
  /// an angle or the minutes added to a prayer, and the widget follows.
  var calculation: CalculationSettings

  /// Settings for a place, with a method's parameters and a madhab.
  init(place: Place, method: CalculationMethod, madhab: Madhab = .shafi) {
    self.place = place
    self.method = method
    calculation = CalculationSettings(method: method, madhab: madhab)
  }

  /// Settings for a place, with the method SalahTimes suggests for its country.
  init(place: Place) {
    self.init(place: place, method: Self.suggestedMethod(for: place))
  }

  /// The method SalahTimes suggests for the place's country, or the Muslim World League's.
  ///
  /// A suggestion is a starting point, not a ruling: let your users change it.
  static func suggestedMethod(for place: Place) -> CalculationMethod {
    CalculationMethod.suggested(for: place.location) ?? .muslimWorldLeague
  }

  /// The school that sets Asr's shadow length.
  var madhab: Madhab {
    get { calculation.parameters.madhab }
    set { calculation.parameters.madhab = newValue }
  }

  /// Switches to another published method and its parameters, keeping the madhab.
  mutating func choose(_ method: CalculationMethod) {
    let madhab = self.madhab
    self.method = method
    calculation = CalculationSettings(method: method, madhab: madhab)
  }

  /// Moves to another place, with the method suggested for it and the same madhab.
  mutating func move(to place: Place) {
    self.place = place
    choose(Self.suggestedMethod(for: place))
  }

  /// The schedule these settings calculate.
  var schedule: PrayerSchedule {
    PrayerSchedule(source: CalculationSource(calculation), location: place.location)
  }
}

nonisolated extension SharedValue where Value == PrayerSettings {
  /// The settings in the App Group. The app is the only writer; the extension reads them.
  ///
  /// The key carries a version. When the settings' shape changes, change the key: a stored
  /// value that no longer decodes reads as no settings, which the widget shows as setup
  /// required.
  static var prayerSettings: Self {
    SharedValue(appGroup: AppIdentity.appGroup, key: "prayerSettings.v1")
  }
}

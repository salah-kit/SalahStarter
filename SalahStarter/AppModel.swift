import Foundation
import Observation
import SalahTimes
import SalahWidgets

/// The app's state: the prayer settings it shares with the widget, and its alerts.
///
/// Every change saves the settings to the App Group with `SharedValue`, which asks WidgetKit
/// to reload the widget only when the stored value changed, then replans the alerts.
@MainActor
@Observable
final class AppModel {
  /// The settings, or `nil` before the person chooses a place.
  private(set) var settings: PrayerSettings?
  /// Why the last save failed, such as an App Group the app isn't entitled to; `nil` when it
  /// succeeded.
  private(set) var saveError: String?
  /// The prayer alerts.
  let alerts: AlertCoordinator

  @ObservationIgnored private let shared: SharedValue<PrayerSettings>

  init(shared: SharedValue<PrayerSettings> = .prayerSettings, alerts: AlertCoordinator) {
    self.shared = shared
    self.alerts = alerts
    settings = shared.load()
  }

  /// The model the app runs with: the App Group's settings and the system's notification center.
  ///
  /// `-resetSettings` removes the stored settings and alert options first, as on a fresh
  /// install. The UI tests launch with it.
  static func live(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
    if arguments.contains("-resetSettings") {
      _ = try? SharedValue.prayerSettings.save(nil, reloading: [AppIdentity.widgetKind])
      _ = try? SharedValue.alertOptions.save(nil)
    }
    return AppModel(alerts: AlertCoordinator())
  }

  /// Moves to a place, with the method suggested for its country.
  @discardableResult
  func choose(_ place: Place) -> Task<Void, Never> {
    var next = settings ?? PrayerSettings(place: place)
    next.move(to: place)
    return save(next)
  }

  /// Switches to a published method.
  @discardableResult
  func choose(_ method: CalculationMethod) -> Task<Void, Never> {
    update { $0.choose(method) }
  }

  /// Sets the school that sets Asr's time.
  @discardableResult
  func choose(_ madhab: Madhab) -> Task<Void, Never> {
    update { $0.madhab = madhab }
  }

  private func update(_ change: (inout PrayerSettings) -> Void) -> Task<Void, Never> {
    guard var next = settings else { return Task {} }
    change(&next)
    return save(next)
  }

  /// Saves the settings for the widget, then replans the alerts. The returned task finishes
  /// when the alerts are replanned.
  private func save(_ value: PrayerSettings) -> Task<Void, Never> {
    do {
      try shared.save(value, reloading: [AppIdentity.widgetKind])
      saveError = nil
    } catch {
      saveError = String(describing: error)
    }
    settings = value
    return Task { await alerts.replan(settings: value) }
  }
}

import Foundation
import Observation
import SalahAlerts
import SalahCore
import SalahWidgets
import UserNotifications

/// The alerts the person chose: an alert at each of the five prayers, and an optional reminder
/// before each one.
nonisolated struct AlertOptions: Codable, Hashable, Sendable {
  /// Whether the five prayers get alerts.
  var isOn = false
  /// How many minutes before each prayer its reminder fires, or `nil` for none.
  var reminderMinutes: Int?

  /// The reminders the app offers.
  static let reminderChoices: [Int?] = [nil, 5, 10, 15, 30]
  /// The longest reminder the app offers. The planner rejects a longer one.
  static let maximumReminder = Duration.seconds(30 * 60)

  /// The alerts of one prayer, or `nil` for none: never sunrise, which isn't a prayer.
  func settings(for subject: AlertSubject) -> AlertSettings? {
    guard isOn, subject.prayer.isPrayer else { return nil }
    return AlertSettings(before: reminderMinutes.map { .seconds($0 * 60) })
  }
}

nonisolated extension SharedValue where Value == AlertOptions {
  /// The alert options, next to the prayer settings in the App Group. No widget reads them, so
  /// saving them reloads nothing.
  static var alertOptions: Self {
    SharedValue(appGroup: AppIdentity.appGroup, key: "alertOptions.v1")
  }
}

/// How the app plans its alerts: one namespace, two weeks ahead, the default budget of 60
/// pending requests.
nonisolated enum AlertPlanning {
  /// The namespace of the app's prayer alerts.
  static let namespace = "prayers"
  /// How far ahead the app plans.
  static let range: TimeInterval = 14 * 86_400

  /// The notification plan for the settings and options at `now`.
  static func plan(
    settings: PrayerSettings, options: AlertOptions, at now: Date
  ) throws(AlertPlanningError) -> NotificationPlan {
    let planner = AlertPlanner()
    let alerts = try planner.schedule(
      settings.schedule, namespace: namespace, from: now, to: now.addingTimeInterval(range),
      maximumReminderOffset: AlertOptions.maximumReminder, settings: options.settings(for:))
    return planner.notificationPlan(alerts, from: now)
  }
}

/// The text and the interruption level of the app's notifications.
nonisolated struct AlertContent: Sendable {
  /// The prayer names, in the app's language.
  var names: PrayerNames
  /// The place's time zone, which the times are shown in.
  var timeZone: TimeZone
  /// The locale the times are written in.
  var locale: Locale = .autoupdatingCurrent

  /// The notification content for an alert.
  ///
  /// The alert at a prayer's time is Time Sensitive: with the Time Sensitive capability, and
  /// unless the person turns it off in Settings, it comes through Focus and the scheduled
  /// summary. Reminders are active, so a reminder never breaks through.
  func make(_ alert: PlannedAlert) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    let name = names.name(of: alert.event)
    content.title = name
    switch alert.kind {
    case .atTime:
      let time = alert.event.time.formatted(
        Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
      content.body = String(localized: "It's time for \(name) (\(time)).")
      content.interruptionLevel = .timeSensitive
    case .before:
      content.body = String(localized: "\(name) in \(duration(alert)).")
      content.interruptionLevel = .active
    case .after:
      content.body = String(localized: "\(name) began \(duration(alert)) ago.")
      content.interruptionLevel = .active
    }
    content.sound = alert.sound.notificationSound
    return content
  }

  /// How far the alert is from its prayer, in words: "10 minutes".
  private func duration(_ alert: PlannedAlert) -> String {
    PrayerDurationFormat.string(
      abs(alert.event.time.timeIntervalSince(alert.fireDate)), width: .spoken,
      locale: names.locale)
  }
}

/// What the coordinator asks the system for besides `AlertNotificationCenter`. Tests replace it,
/// so they never ask the real notification center for permission.
nonisolated struct NotificationPermissions: Sendable {
  /// Asks the person for permission to show alerts and play sounds.
  var request: @Sendable () async -> Void
  /// Whether the app's notifications may be Time Sensitive.
  var timeSensitiveSetting: @Sendable () async -> UNNotificationSetting

  /// The system's.
  static let system = NotificationPermissions(
    request: {
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
    },
    timeSensitiveSetting: {
      await UNUserNotificationCenter.current().notificationSettings().timeSensitiveSetting
    })
}

/// Plans the prayer alerts and installs them with SalahAlerts' `NotificationScheduler`.
///
/// The app replans when it becomes active and whenever the settings or the options change.
/// It asks for notification permission itself, when the person turns alerts on; SalahKit never
/// asks.
@MainActor
@Observable
final class AlertCoordinator {
  /// The person's choices, saved in the App Group.
  private(set) var options: AlertOptions
  /// The app's notification authorization at the last replan.
  private(set) var authorization: UNAuthorizationStatus?
  /// Whether alerts may be Time Sensitive: `.enabled` when the app has the capability and the
  /// person hasn't turned it off.
  private(set) var timeSensitive: UNNotificationSetting?
  /// What the last replan confirmed, or `nil` before the first.
  private(set) var report: NotificationApplyReport?

  @ObservationIgnored private let shared: SharedValue<AlertOptions>
  @ObservationIgnored private let center: any AlertNotificationCenter
  @ObservationIgnored private let permissions: NotificationPermissions
  @ObservationIgnored private let scheduler: NotificationScheduler
  @ObservationIgnored private var generation = 0

  /// Creates a coordinator on the system's notification center, or the given one.
  init(
    shared: SharedValue<AlertOptions> = .alertOptions,
    center: (any AlertNotificationCenter)? = nil,
    permissions: NotificationPermissions = .system
  ) {
    let center = center ?? UNUserNotificationCenter.current()
    self.shared = shared
    self.center = center
    self.permissions = permissions
    options = shared.load() ?? AlertOptions()
    scheduler = NotificationScheduler(
      // The bundle identifier keeps the requests apart from any other code's in the app.
      identifierPrefix: "\(Bundle.main.bundleIdentifier ?? "app").",
      namespace: AlertPlanning.namespace, threadIdentifier: AlertPlanning.namespace,
      center: center)
  }

  /// Turns the alerts on or off, asks for permission the first time they're turned on, and
  /// replans.
  func setAlerts(on isOn: Bool, settings: PrayerSettings?) async {
    options.isOn = isOn
    saveOptions()
    if isOn, await center.authorizationStatus() == .notDetermined {
      await permissions.request()
    }
    await replan(settings: settings)
  }

  /// Sets the reminder before each prayer and replans.
  func setReminder(minutes: Int?, settings: PrayerSettings?) async {
    options.reminderMinutes = minutes
    saveOptions()
    await replan(settings: settings)
  }

  /// Plans the alerts of `settings` from `now`, installs the plan and reads it back.
  ///
  /// With alerts off the plan is empty, which removes the app's pending requests. A later call
  /// supersedes one still in flight, as the scheduler itself does; only the latest call's
  /// results are kept.
  func replan(settings: PrayerSettings?, now: Date = Date()) async {
    generation += 1
    let mine = generation
    let authorization = await center.authorizationStatus()
    let timeSensitive = await permissions.timeSensitiveSetting()
    guard mine == generation else { return }
    self.authorization = authorization
    self.timeSensitive = timeSensitive
    let plan: NotificationPlan
    if let settings {
      // The options are bounded, so planning can't fail; if it did, the requests would stay.
      guard let planned = try? AlertPlanning.plan(settings: settings, options: options, at: now)
      else { return }
      plan = planned
    } else {
      // Before setup there's nothing to alert for: an empty plan removes any old requests.
      plan = NotificationPlan(
        namespace: AlertPlanning.namespace, effectiveRange: DateInterval(start: now, end: now),
        alerts: [], coveredUntil: now, coverageByKind: [:])
    }
    let content = AlertContent(
      names: AppLanguage.names, timeZone: settings?.place.location.timeZone ?? .current)
    let report = try? await scheduler.apply(plan) { content.make($0) }
    guard mine == generation else { return }
    self.report = report
  }

  private func saveOptions() {
    // Nothing to reload: no widget reads the options. A failure leaves them for this session.
    _ = try? shared.save(options)
  }
}

/// Shows the app's notifications while it's in front, as banners with their sound.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }
}

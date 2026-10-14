import Foundation
import SalahAlerts
import SalahCore
import SalahWidgets
import Testing
import UserNotifications

@testable import SalahStarter

/// A notification center that keeps requests in memory. The tests never touch the real one, so
/// they never ask for permission.
nonisolated final class FakeCenter: AlertNotificationCenter, @unchecked Sendable {
  // @unchecked: every stored property is read and written while holding `lock`, and the
  // requests it keeps are immutable once created.
  private let lock = NSLock()
  private var currentStatus: UNAuthorizationStatus
  private var requests: [String: UNNotificationRequest] = [:]

  init(status: UNAuthorizationStatus = .notDetermined) {
    currentStatus = status
  }

  var status: UNAuthorizationStatus {
    get { lock.withLock { currentStatus } }
    set { lock.withLock { currentStatus = newValue } }
  }

  /// The pending requests, by fire date.
  var pending: [UNNotificationRequest] {
    lock.withLock { Array(requests.values) }
      .sorted { ($0.fireDate ?? .distantPast) < ($1.fireDate ?? .distantPast) }
  }

  func authorizationStatus() async -> UNAuthorizationStatus { status }

  func pendingNotificationRequests() async throws -> [UNNotificationRequest] {
    lock.withLock { Array(requests.values) }
  }

  func add(_ request: UNNotificationRequest) async throws {
    lock.withLock { requests[request.identifier] = request }
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) async {
    lock.withLock {
      for identifier in identifiers { requests[identifier] = nil }
    }
  }

  func deliveredNotificationRecords() async -> [DeliveredNotificationRecord] { [] }

  func removeDeliveredNotifications(withIdentifiers identifiers: [String]) async {}
}

extension UNNotificationRequest {
  /// The instant the request's calendar trigger names.
  nonisolated var fireDate: Date? {
    (trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
  }
}

extension NotificationPermissions {
  /// Never asked: the tests that use it don't turn alerts on.
  nonisolated static let never = NotificationPermissions(
    request: { Issue.record("asked for permission") },
    timeSensitiveSetting: { .notSupported })

  /// A person who answers the prompt, and the time-sensitive setting the system reports.
  nonisolated static func answering(
    _ answer: UNAuthorizationStatus, on center: FakeCenter, asked: Asked,
    timeSensitive: UNNotificationSetting = .enabled
  ) -> NotificationPermissions {
    NotificationPermissions(
      request: {
        asked.count()
        center.status = answer
      },
      timeSensitiveSetting: { timeSensitive })
  }

  /// How many times the app asked.
  nonisolated final class Asked: @unchecked Sendable {
    // @unchecked: `value` is read and written while holding `lock`.
    private let lock = NSLock()
    private var value = 0
    var times: Int { lock.withLock { value } }
    func count() { lock.withLock { value += 1 } }
  }
}

@MainActor
@Suite("Prayer alerts")
struct AlertTests {
  static let makkah = PrayerSettings(place: .makkah)

  static func coordinator(
    _ center: FakeCenter, permissions: NotificationPermissions
  ) -> (AlertCoordinator, SharedValue<AlertOptions>) {
    let options = SharedValue<AlertOptions>(
      appGroup: AppIdentity.appGroup, key: "test.\(UUID().uuidString)")
    return (AlertCoordinator(shared: options, center: center, permissions: permissions), options)
  }

  @Test("alerts for the five prayers, never sunrise, with the chosen reminder")
  func options() {
    let subject = { (prayer: PrayerKind) in
      AlertSubject(scheduleDay: CivilDay(year: 2026, month: 10, day: 14), prayer: prayer)
    }
    #expect(AlertOptions().settings(for: subject(.dhuhr)) == nil)
    let on = AlertOptions(isOn: true, reminderMinutes: 10)
    #expect(on.settings(for: subject(.sunrise)) == nil)
    #expect(on.settings(for: subject(.dhuhr)) == AlertSettings(before: .seconds(600)))
    #expect(
      AlertOptions(isOn: true).settings(for: subject(.isha)) == AlertSettings(atTime: true))
  }

  @Test("the plan covers two complete days first, within the budget")
  func plan() throws {
    let now = TimelineTests.start
    let plan = try AlertPlanning.plan(
      settings: Self.makkah, options: AlertOptions(isOn: true, reminderMinutes: 10), at: now)
    #expect(plan.alerts.count == 60)
    #expect(plan.coveredUntil > now.addingTimeInterval(2 * 86_400))
    #expect(plan.alerts.allSatisfy { $0.event.kind.isPrayer && $0.fireDate > now })
    let off = try AlertPlanning.plan(settings: Self.makkah, options: AlertOptions(), at: now)
    #expect(off.alerts.isEmpty)
  }

  @Test("the alert at a prayer's time is Time Sensitive; reminders are active")
  func content() throws {
    let now = TimelineTests.start
    let plan = try AlertPlanning.plan(
      settings: Self.makkah, options: AlertOptions(isOn: true, reminderMinutes: 10), at: now)
    let content = AlertContent(
      names: PrayerNames(locale: Locale(identifier: "en")),
      timeZone: Place.makkah.location.timeZone,
      locale: Locale(identifier: "en_US_POSIX"))
    // Noon in Makkah: Dhuhr is the next prayer, a few minutes later.
    let atTime = try #require(plan.alerts.first { $0.kind == .atTime })
    let made = content.make(atTime)
    #expect(made.interruptionLevel == .timeSensitive)
    #expect(made.title == "Dhuhr")
    // In Makkah's time zone, whatever the device's: 12-something, not 9 (UTC).
    #expect(made.body.hasPrefix("It's time for Dhuhr (12:"))
    #expect(made.body.hasSuffix(")."))
    #expect(made.sound == .default)
    let before = try #require(plan.alerts.first { $0.kind == .before })
    #expect(content.make(before).interruptionLevel == .active)
    // Dhuhr's reminder came before noon, so the first one is Asr's.
    #expect(content.make(before).body == "Asr in 10 minutes.")
  }

  @Test("turning alerts on asks once, then installs and confirms the plan")
  func turningOn() async throws {
    let center = FakeCenter()
    let asked = NotificationPermissions.Asked()
    let (alerts, stored) = Self.coordinator(
      center, permissions: .answering(.authorized, on: center, asked: asked))
    defer { _ = try? stored.save(nil) }

    await alerts.setAlerts(on: true, settings: Self.makkah)
    #expect(asked.times == 1)
    #expect(stored.load()?.isOn == true)
    #expect(alerts.authorization == .authorized)
    #expect(alerts.timeSensitive == .enabled)
    #expect(center.pending.count == 60)
    let report = try #require(alerts.report)
    #expect(report.failures.isEmpty)
    #expect(report.confirmed.count == 60)
    #expect(report.confirmedCoveredUntil != nil)
    // Every at-time request is Time Sensitive, under the app's own prefix.
    let atTime = center.pending.filter { $0.identifier.hasSuffix("/atTime") }
    #expect(!atTime.isEmpty)
    #expect(atTime.allSatisfy { $0.content.interruptionLevel == .timeSensitive })
    #expect(
      center.pending.allSatisfy {
        $0.identifier.hasPrefix("\(Bundle.main.bundleIdentifier ?? "").prayers/")
      })

    // A reminder adds requests; already asked, so no second prompt.
    await alerts.setReminder(minutes: 15, settings: Self.makkah)
    #expect(asked.times == 1)
    #expect(center.pending.contains { $0.identifier.hasSuffix("/before") })

    // Off removes every request.
    await alerts.setAlerts(on: false, settings: Self.makkah)
    #expect(center.pending.isEmpty)
    #expect(asked.times == 1)
  }

  @Test("denied permission installs nothing and says so")
  func denied() async throws {
    let center = FakeCenter()
    let asked = NotificationPermissions.Asked()
    let (alerts, stored) = Self.coordinator(
      center, permissions: .answering(.denied, on: center, asked: asked, timeSensitive: .disabled))
    defer { _ = try? stored.save(nil) }

    await alerts.setAlerts(on: true, settings: Self.makkah)
    #expect(asked.times == 1)
    #expect(alerts.authorization == .denied)
    #expect(alerts.timeSensitive == .disabled)
    #expect(center.pending.isEmpty)
    #expect(alerts.report?.confirmed.isEmpty == true)
    #expect(alerts.report?.failures.values.allSatisfy { $0 == .notAuthorized } == true)
  }

  @Test("before setup there is nothing to alert for, and old requests go")
  func beforeSetup() async throws {
    let center = FakeCenter(status: .authorized)
    let (alerts, stored) = Self.coordinator(center, permissions: .never)
    defer { _ = try? stored.save(nil) }
    try await center.add(
      UNNotificationRequest(
        identifier: "\(Bundle.main.bundleIdentifier ?? "").prayers/2026-10-14/dhuhr/atTime",
        content: UNMutableNotificationContent(),
        trigger: UNCalendarNotificationTrigger(
          dateMatching: DateComponents(year: 2030, month: 1, day: 1), repeats: false)))

    await alerts.replan(settings: nil)
    #expect(center.pending.isEmpty)
  }
}

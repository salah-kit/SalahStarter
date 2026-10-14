import Foundation
import SalahCore
import SalahWidgets
import Testing

@testable import SalahStarter

/// A model of how WidgetKit uses the widget's timelines, for fixed-clock tests.
///
/// It asks for a timeline at the start, then at each timeline's reload date plus a chosen
/// delay, or earlier when the app saves settings and asks for a reload; a timeline that never
/// reloads waits for the app. Between requests it shows the latest timeline's last entry whose
/// date has passed. This is the contract WidgetKit documents, not its actual scheduling.
struct WidgetHost {
  struct Request {
    var date: Date
    var settings: PrayerSettings?
    var timeline: PrayerWidgetTimeline
  }

  private(set) var requests: [Request] = []

  /// Runs the widget from `start` until `end`.
  ///
  /// - Parameters:
  ///   - delays: Extra seconds after a timeline's reload date, by the index of the request
  ///     that made the timeline.
  ///   - appReloads: Dates at which the app saves changed settings and asks for a reload.
  ///   - settings: The settings in the App Group at a date.
  init(
    from start: Date, until end: Date, delays: [Int: TimeInterval] = [:],
    appReloads: [Date] = [], settings: (Date) -> PrayerSettings?
  ) {
    var date = start
    while date < end {
      let stored = settings(date)
      let timeline = PrayerWidgetTimeline(settings: stored, now: date)
      requests.append(Request(date: date, settings: stored, timeline: timeline))
      var next: Date
      switch timeline.reload {
      case .never: next = .distantFuture
      case .after(let reload): next = reload.addingTimeInterval(delays[requests.count - 1] ?? 0)
      }
      if let reload = appReloads.filter({ $0 > date && $0 < next }).min() {
        next = reload
      }
      guard next > date else {
        Issue.record("the next request, \(next), isn't after the one at \(date)")
        break
      }
      date = next
    }
  }

  /// The entry showing at `date`, and the request that supplied it.
  func shown(at date: Date) -> (request: Request, entry: PrayerEntry)? {
    guard let request = requests.last(where: { $0.date <= date }),
      let entry = request.timeline.entries.last(where: { $0.date <= date })
    else { return nil }
    return (request, entry)
  }
}

/// The widget's timelines over a week with a fixed clock: what WidgetKit would show at every
/// moment, against what the schedule says at that moment.
@Suite("The widget's timelines")
struct TimelineTests {
  /// 2026-10-13 12:00 in Makkah.
  static let start = Date(timeIntervalSince1970: 1_791_882_000)
  static let week: TimeInterval = 7 * 86_400
  static let makkah = PrayerSettings(place: .makkah)

  @Test("a week in Makkah: every prayer in turn, a reload a day, a new day at each midnight")
  func aWeek() throws {
    let host = WidgetHost(from: Self.start, until: Self.start + Self.week) { _ in Self.makkah }
    let shown = check(host, from: Self.start, through: Self.start + Self.week)

    #expect(shown.expired.isEmpty)
    #expect(host.requests.count == 7)
    for request in host.requests {
      let planned = try #require(request.timeline.planned)
      #expect(planned.isTruncated == false)
      #expect(request.timeline.reload == .after(request.date.addingTimeInterval(24 * 3_600)))
      // The last entry says the times need refreshing, from the end of the validity.
      let last = try #require(request.timeline.entries.last)
      #expect(last.date == planned.validUntil)
      #expect(PrayerDisplay(last.content) == .expired)
    }
    // Every prayer of the week became the next prayer, in order.
    let prayers = Self.makkah.schedule
      .events(from: Self.start, through: Self.start + Self.week + 86_400).events
      .filter { $0.kind.isPrayer && $0.time > Self.start }.map(\.id)
    #expect(shown.nextPrayers.count >= 35)
    #expect(shown.nextPrayers == Array(prayers.prefix(shown.nextPrayers.count)))
    // The listed day turned over at each of the seven midnights.
    #expect(shown.days.count == 8)
    #expect(shown.days.first == CivilDay(year: 2026, month: 10, day: 13))
  }

  @Test("a request later than the timeline's validity shows the expired entry until it comes")
  func lateRequest() throws {
    // Request 2's timeline asks for a reload after 24 hours and is valid for 48; the next
    // request comes 30 hours after the reload date, 6 hours past the validity.
    let host = WidgetHost(
      from: Self.start, until: Self.start + Self.week, delays: [2: 30 * 3_600]
    ) { _ in Self.makkah }
    try #require(host.requests.count >= 4)
    let validUntil = try #require(host.requests[2].timeline.planned?.validUntil)
    let shown = check(host, from: Self.start, through: Self.start + Self.week)

    #expect(host.requests[3].date == validUntil.addingTimeInterval(6 * 3_600))
    #expect(shown.expired.contains(validUntil))
    #expect(shown.expired.allSatisfy { $0 >= validUntil && $0 < host.requests[3].date })
    let entry = try #require(host.shown(at: validUntil.addingTimeInterval(3_600))?.entry)
    #expect(PrayerDisplay(entry.content) == .expired)
  }

  @Test("no settings: setup required, with no reload, until the app saves and asks for one")
  func setUpLater() throws {
    let saved = Self.start.addingTimeInterval(5 * 3_600)
    let host = WidgetHost(
      from: Self.start, until: Self.start + 3 * 86_400, appReloads: [saved]
    ) { date in date < saved ? nil : Self.makkah }

    try #require(host.requests.count >= 2)
    #expect(host.requests[0].timeline.reload == .never)
    #expect(host.requests[0].timeline.entries.count == 1)
    #expect(host.requests.map(\.date).prefix(2) == [Self.start, saved])
    for minutes in stride(from: 0, to: 300, by: 15) {
      let entry = host.shown(at: Self.start.addingTimeInterval(TimeInterval(minutes * 60)))
      #expect(entry.map { PrayerDisplay($0.entry.content) } == .setupRequired)
    }
    #expect(check(host, from: saved, through: Self.start + 3 * 86_400).expired.isEmpty)
    // 17:00 in Makkah: Asr has passed, Maghrib is next.
    let after = try #require(host.shown(at: saved)?.entry)
    guard case .times(let times) = PrayerDisplay(after.content) else {
      Issue.record("after the save: \(after.content)")
      return
    }
    #expect(times.state.latestPrayer?.kind == .asr)
    #expect(times.state.nextPrayer?.kind == .maghrib)
  }

  @Test("an entry at each midnight keeps the state and lists the new day")
  func midnights() throws {
    let timeline = PrayerWidgetTimeline(settings: Self.makkah, now: Self.start)
    let zone = Place.makkah.location.timeZone
    for offset in 1...2 {
      let midnight = CivilDay(containing: Self.start, in: zone).adding(days: offset).start(in: zone)
      let index = try #require(timeline.entries.firstIndex { $0.date == midnight })
      guard case .timeline(let state, _, let day) = timeline.entries[index].content,
        case .timeline(let before, _, _) = timeline.entries[index - 1].content
      else {
        Issue.record("no timeline entries around \(midnight)")
        continue
      }
      #expect(state == before)
      #expect(day.day?.day == CivilDay(containing: midnight, in: zone))
    }
    #expect(timeline.entries.map(\.date) == timeline.entries.map(\.date).sorted())
  }

  @Test("the widget words every display, and the times show no notice")
  func wording() {
    #expect(DisplayWording(.setupRequired).title == "Choose a place")
    #expect(DisplayWording(.expired).title == "Times need refreshing")
    #expect(
      DisplayWording(.unavailable(.invalidInput)).message
        == "The place or the settings aren't valid.")
    let entry = PrayerWidgetTimeline(settings: Self.makkah, now: Self.start).entries[0]
    guard case .times(let times) = PrayerDisplay(entry.content) else {
      Issue.record("Makkah at noon: \(entry.content)")
      return
    }
    #expect(DisplayWording(.times(times)).message == nil)
    #expect(times.missingKinds.isEmpty)
  }

  // MARK: Checking what a host shows

  struct Shown {
    var expired: [Date] = []
    var nextPrayers: [String] = []
    /// The days the entries on show listed, in order, without repeats.
    var days: [CivilDay] = []
  }

  /// Checks the host every five minutes and one second either side of every entry and event:
  /// an entry shows what the schedule says at that instant and lists the instant's own day,
  /// never after its timeline's validity; an expired entry shows only after it.
  func check(_ host: WidgetHost, from start: Date, through end: Date) -> Shown {
    var samples = Set(stride(from: start, through: end, by: 300))
    for request in host.requests {
      for entry in request.timeline.entries {
        samples.formUnion([entry.date, entry.date - 1, entry.date + 1])
      }
      if let settings = request.settings {
        for event in settings.schedule.events(from: start, through: end).events {
          samples.formUnion([event.time - 1, event.time, event.time + 1])
        }
      }
    }
    var shown = Shown()
    for date in samples.sorted() where date >= start && date <= end {
      guard let (request, entry) = host.shown(at: date) else {
        Issue.record("nothing shown at \(date)")
        continue
      }
      guard let settings = request.settings, let planned = request.timeline.planned else {
        continue
      }
      let zone = settings.place.location.timeZone
      guard case .timeline(let state, _, let day) = entry.content else {
        Issue.record("setup required at \(date), with settings")
        continue
      }
      switch state {
      case .schedule(let scheduleState):
        if date >= planned.validUntil {
          Issue.record("a schedule state at \(date), after the validity \(planned.validUntil)")
        }
        let lookahead = CivilDay(containing: planned.horizon.end, in: zone).adding(days: 2)
          .start(in: zone)
        let expected = settings.schedule.state(at: date, through: lookahead)
        if scheduleState.prayerState?.nextPrayer?.id != expected.prayerState?.nextPrayer?.id
          || scheduleState.prayerState?.latestPrayer?.id
            != expected.prayerState?.latestPrayer?.id
        {
          Issue.record("at \(date): \(scheduleState), expected \(expected)")
        }
        let today = CivilDay(containing: date, in: zone)
        if day.day?.day != today {
          Issue.record("at \(date): lists \(day), expected \(today)")
        }
        if let listed = day.day?.day, shown.days.last != listed {
          shown.days.append(listed)
        }
        if let next = scheduleState.prayerState?.nextPrayer?.id, shown.nextPrayers.last != next {
          shown.nextPrayers.append(next)
        }
      case .expired(let knownThrough):
        if knownThrough != planned.validUntil || date < knownThrough {
          Issue.record("expired through \(knownThrough) shown at \(date)")
        }
        shown.expired.append(date)
      }
    }
    return shown
  }
}

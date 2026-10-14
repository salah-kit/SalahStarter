import Foundation
import SalahCore
import SalahWidgets
import WidgetKit

/// One widget entry: when it starts and what it shows.
nonisolated struct PrayerEntry: TimelineEntry, Hashable, Sendable {
  /// What an entry shows.
  enum Content: Hashable, Sendable {
    /// No settings in the App Group yet: the app hasn't been set up.
    case setupRequired
    /// A state of the timeline, with the place and the day the entry lists: the place's
    /// civil date at the entry's date.
    case timeline(PrayerTimelineState, place: Place, day: PrayerDayAvailability)
  }

  var date: Date
  var content: Content
}

/// The widget's timeline, as plain values a test can inspect.
nonisolated struct PrayerWidgetTimeline: Hashable, Sendable {
  /// When WidgetKit should ask for the next timeline.
  enum Reload: Hashable, Sendable {
    /// Only when the app asks: the widget waits for setup.
    case never
    /// At this date.
    case after(Date)
  }

  /// The entries, in date order.
  var entries: [PrayerEntry]
  /// When to ask for the next timeline.
  var reload: Reload
  /// SalahWidgets' timeline the entries came from, or `nil` when the widget waits for setup.
  var planned: PrayerTimeline?

  /// Builds the timeline from the settings at `now`.
  ///
  /// Without settings, one setup entry that never reloads: the app's first save asks for a
  /// reload. With settings, SalahWidgets' 48-hour timeline: an entry wherever the state
  /// changes, an expired entry where its validity ends, and a reload halfway there. The
  /// widget lists the day's times, which change at midnight while the state doesn't, so an
  /// entry at each midnight in the place's zone keeps the state that holds and lists the new
  /// day.
  ///
  /// - Parameters:
  ///   - settings: The settings from the App Group, or `nil` when there are none.
  ///   - now: The moment WidgetKit asked for the timeline.
  ///   - horizon: How far the timeline reaches.
  init(
    settings: PrayerSettings?, now: Date,
    horizon: Duration = PrayerTimelineBuilder.defaultHorizon
  ) {
    guard let settings else {
      self.init(entries: [PrayerEntry(date: now, content: .setupRequired)], reload: .never)
      return
    }
    let schedule = settings.schedule
    let zone = settings.place.location.timeZone
    func entry(_ date: Date, _ state: PrayerTimelineState) -> PrayerEntry {
      PrayerEntry(
        date: date,
        content: .timeline(state, place: settings.place, day: schedule.day(containing: date)))
    }

    let planned: PrayerTimeline
    do {
      planned = try PrayerTimelineBuilder(schedule: schedule).timeline(from: now, horizon: horizon)
    } catch {
      // Only an invalid horizon fails. Say the times need refreshing until the app reloads.
      self.init(entries: [entry(now, .expired(knownThrough: now))], reload: .never)
      return
    }

    var entries: [PrayerEntry] = []
    for (index, planEntry) in planned.entries.enumerated() {
      entries.append(entry(planEntry.date, planEntry.state))
      // Midnights before the next entry: the state still holds, the listed day changes.
      guard index + 1 < planned.entries.count, case .schedule = planEntry.state else { continue }
      let end = planned.entries[index + 1].date
      var midnight = CivilDay(containing: planEntry.date, in: zone).adding(days: 1).start(in: zone)
      while midnight < end {
        entries.append(entry(midnight, planEntry.state))
        midnight = CivilDay(containing: midnight, in: zone).adding(days: 1).start(in: zone)
      }
    }
    self.init(entries: entries, reload: .after(planned.reloadDate), planned: planned)
  }

  init(entries: [PrayerEntry], reload: Reload, planned: PrayerTimeline? = nil) {
    self.entries = entries
    self.reload = reload
    self.planned = planned
  }

  /// The timeline for WidgetKit.
  var widgetKitTimeline: Timeline<PrayerEntry> {
    switch reload {
    case .never: Timeline(entries: entries, policy: .never)
    case .after(let date): Timeline(entries: entries, policy: .after(date))
    }
  }
}

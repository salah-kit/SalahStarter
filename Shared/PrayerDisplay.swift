import Foundation
import SalahCore
import SalahWidgets

/// What the app or a widget entry shows, decided before any view draws it.
///
/// Each case answers a different question and has its own words:
/// - ``setupRequired``: the app hasn't saved settings yet.
/// - ``times(_:)``: the schedule knows the state. A partial day keeps its known times and says
///   which aren't known; an unknown next prayer gets no countdown.
/// - ``unavailable(_:)``: the schedule knows nothing usable at this moment, and why.
/// - ``expired``: the widget's timeline ran out before WidgetKit asked for a new one. The
///   times need refreshing; there is no countdown.
nonisolated enum PrayerDisplay: Hashable, Sendable {
  case setupRequired
  case times(TimesDisplay)
  case unavailable(UnavailableReason)
  case expired

  /// The display of a widget entry.
  init(_ content: PrayerEntry.Content) {
    switch content {
    case .setupRequired:
      self = .setupRequired
    case .timeline(.expired, _, _):
      self = .expired
    case .timeline(.schedule(let state), _, let day):
      self.init(state, day: day)
    }
  }

  /// The display of a schedule's state and the day it lists.
  init(_ state: ScheduleState, day: PrayerDayAvailability) {
    switch state {
    case .unavailable(let coverage, _):
      self = .unavailable(UnavailableReason(coverage.gaps.map(\.reason)))
    case .available(let state, _):
      self = .times(TimesDisplay(state: state, day: day))
    }
  }
}

/// A known state, the day it lists, and what that day lacks.
nonisolated struct TimesDisplay: Hashable, Sendable {
  /// The state; its next prayer is `nil` when the schedule can't name it.
  var state: PrayerState
  /// The listed day, or `nil` when the whole day is unavailable.
  var day: PrayerDay?
  /// The listed day's kinds that the source can't produce, in order.
  var missingKinds: [PrayerKind]

  init(state: PrayerState, day availability: PrayerDayAvailability) {
    self.state = state
    switch availability {
    case .available(let day, .complete):
      self.day = day
      missingKinds = []
    case .available(let day, .partial(let missing)):
      self.day = day
      missingKinds = missing.keys.sorted()
    case .unavailable:
      day = nil
      missingKinds = PrayerKind.allCases
    }
  }

  /// Whether the schedule can't name the next prayer.
  var nextIsUnknown: Bool { state.nextPrayer == nil }
}

/// Why there are no times, in the app's own terms.
nonisolated enum UnavailableReason: Hashable, Sendable {
  /// The calculation can't produce the times here today, such as Isha in a polar summer.
  case cannotCalculate
  /// The place or the settings aren't valid.
  case invalidInput
  /// The source has no data. A calculation always has data; a published timetable may not.
  case noData

  /// The most telling of a gap's reasons: invalid input first, because nothing works until it's
  /// fixed, then a calculation that can't produce the times.
  init(_ reasons: [ScheduleGapReason]) {
    if reasons.contains(.invalidData) {
      self = .invalidInput
    } else if reasons.contains(.calculationUnavailable) {
      self = .cannotCalculate
    } else {
      self = .noData
    }
  }
}

/// The words for a display, in the app's language.
nonisolated struct DisplayWording: Hashable, Sendable {
  /// The headline, such as "Choose a place"; `nil` while times show.
  var title: String?
  /// The explanation, or a note on what a partial day lacks; `nil` for a complete day.
  var message: String?
  /// A word or two for the smallest Lock Screen widgets.
  var short: String?

  init(_ display: PrayerDisplay, names: PrayerNames = AppLanguage.names) {
    switch display {
    case .setupRequired:
      title = String(localized: "Choose a place")
      message = String(localized: "Open the app to choose a place.")
      short = String(localized: "Set up")
    case .expired:
      title = String(localized: "Times need refreshing")
      message = String(localized: "Open the app to refresh the prayer times.")
      short = String(localized: "Refresh")
    case .unavailable(let reason):
      title = String(localized: "No prayer times")
      switch reason {
      case .cannotCalculate:
        message = String(localized: "Prayer times can't be calculated here today.")
        short = String(localized: "Can't calculate")
      case .invalidInput:
        message = String(localized: "The place or the settings aren't valid.")
        short = String(localized: "Invalid place")
      case .noData:
        message = String(localized: "No prayer times are available.")
        short = String(localized: "No times")
      }
    case .times(let times):
      title = nil
      short = times.nextIsUnknown ? String(localized: "Unknown") : nil
      var notes: [String] = []
      if times.nextIsUnknown {
        notes.append(String(localized: "The next prayer isn't known."))
      }
      if !times.missingKinds.isEmpty {
        let kinds = times.missingKinds.map { names.name(of: $0) }
          .formatted(.list(type: .and).locale(names.locale))
        notes.append(String(localized: "\(kinds): no time today."))
      }
      message = notes.isEmpty ? nil : notes.joined(separator: " ")
    }
  }
}

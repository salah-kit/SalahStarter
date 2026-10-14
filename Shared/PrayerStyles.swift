import SalahCore
import SalahUI
import SwiftUI

// The app's look, as SalahUI styles. SalahUI decides what to show: which prayer is next, which
// rows have passed, whether a countdown can be shown. These styles decide how it looks.

/// The next prayer as a card: the prayer that just started, the next prayer's name and time,
/// and the countdown.
struct CardStyle: NextPrayerStyle {
  var palette: Palette
  /// A smaller layout for the small widget.
  var compact = false

  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      if let justStarted = configuration.justStarted {
        justStarted
          .font(.caption)
          .foregroundStyle(palette.secondaryInk.color)
          .lineLimit(1)
      }
      if let name = configuration.name, let time = configuration.time {
        HStack(alignment: .firstTextBaseline) {
          name
            .font(compact ? .headline : .title2.bold())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Spacer(minLength: 4)
          time
            .font(compact ? .subheadline : .title3)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
        }
        .foregroundStyle(palette.ink.color)
      } else {
        Text("Next prayer unknown")
          .font(.headline)
          .foregroundStyle(palette.ink.color)
      }
      if let countdown = configuration.countdown {
        countdown
          .font(compact ? .title3.bold() : .largeTitle.bold())
          .monospacedDigit()
          .foregroundStyle(palette.accent.color)
          .lineLimit(1)
          .minimumScaleFactor(0.5)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// A row of the day's list: the next prayer in the accent color, passed ones in the secondary
/// color.
struct RowStyle: PrayerRowStyle {
  var palette: Palette

  func makeBody(configuration: Configuration) -> some View {
    let color: ThemeColor
    let emphasized: Bool
    switch configuration.status {
    case .next?:
      color = palette.accent
      emphasized = true
    case .justStarted?:
      color = palette.ink
      emphasized = true
    case .passed?:
      color = palette.secondaryInk
      emphasized = false
    case .upcoming?, nil:
      color = palette.ink
      emphasized = false
    }
    return HStack(alignment: .firstTextBaseline, spacing: 6) {
      configuration.name
        .lineLimit(1)
      Spacer(minLength: 6)
      configuration.time
        .monospacedDigit()
        .fixedSize()
      if let offset = configuration.dayOffsetText {
        offset.font(.caption2)
      }
    }
    .fontWeight(emphasized ? .semibold : .regular)
    .foregroundStyle(color.color)
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("prayer.\(configuration.kind.rawValue)")
  }
}

/// The circular Lock Screen widget: the next prayer's abbreviation over its countdown.
/// VoiceOver reads the abbreviation as the full name.
struct CircularStyle: NextPrayerStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(spacing: 0) {
      (configuration.abbreviation ?? Text(verbatim: "–"))
        .font(.headline)
        .widgetAccentable()
      configuration.countdown?
        .font(.caption2)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
    .accessibilityElement(children: .combine)
  }
}

/// The rectangular Lock Screen widget: the next prayer and its time, then the countdown.
struct RectangularStyle: NextPrayerStyle {
  func makeBody(configuration: Configuration) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      if let name = configuration.name, let time = configuration.time {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          name.font(.headline).widgetAccentable()
          time.monospacedDigit()
        }
        .lineLimit(1)
      } else {
        Text("Next prayer unknown").font(.headline)
      }
      configuration.countdown?
        .monospacedDigit()
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}

/// The inline Lock Screen widget: the next prayer and its time on one line.
struct InlineStyle: NextPrayerStyle {
  func makeBody(configuration: Configuration) -> some View {
    if let name = configuration.name, let time = configuration.time {
      Text("\(name) \(time)")
    } else {
      Text("Next prayer unknown")
    }
  }
}

import SalahCore
import SalahUI
import SwiftUI
import WidgetKit

/// A widget entry in one family.
struct PrayerWidgetView: View {
  let entry: PrayerEntry
  let family: WidgetFamily
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = Palette.of(colorScheme)
    content(palette: palette)
      .containerBackground(for: .widget) {
        switch family {
        case .accessoryCircular: AccessoryWidgetBackground()
        case .accessoryRectangular, .accessoryInline: Color.clear
        default: palette.surface.color
        }
      }
  }

  @ViewBuilder
  private func content(palette: Palette) -> some View {
    let display = PrayerDisplay(entry.content)
    let wording = DisplayWording(display)
    if case .times(let times) = display, case .timeline(_, let place, _) = entry.content {
      TimesWidget(times: times, place: place, wording: wording, family: family, palette: palette)
    } else {
      NoticeWidget(
        display: display, wording: wording, place: entry.content.place, family: family,
        palette: palette)
    }
  }
}

extension PrayerEntry.Content {
  /// The entry's place, when it has one.
  nonisolated var place: Place? {
    if case .timeline(_, let place, _) = self { return place }
    return nil
  }
}

/// Known times: SalahUI's `NextPrayerView` and, in the medium widget, its `PrayerTimesList`.
private struct TimesWidget: View {
  let times: TimesDisplay
  let place: Place
  let wording: DisplayWording
  let family: WidgetFamily
  let palette: Palette

  var body: some View {
    let next = NextPrayerView(
      state: times.state, names: AppLanguage.names, timeZone: place.location.timeZone)
    switch family {
    case .accessoryInline:
      next.nextPrayerStyle(InlineStyle())
    case .accessoryCircular:
      next.nextPrayerStyle(CircularStyle())
    case .accessoryRectangular:
      next.nextPrayerStyle(RectangularStyle())
    case .systemMedium, .systemLarge:
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          placeLine
          next.nextPrayerStyle(CardStyle(palette: palette, compact: true))
          Spacer(minLength: 0)
          note
        }
        if let day = times.day {
          PrayerTimesList(day: day, state: times.state, names: AppLanguage.names)
            .prayerRowStyle(RowStyle(palette: palette))
            .font(.caption)
        }
      }
    default:
      VStack(alignment: .leading, spacing: 4) {
        placeLine
        next.nextPrayerStyle(CardStyle(palette: palette, compact: true))
        Spacer(minLength: 0)
        note
      }
    }
  }

  private var placeLine: some View {
    Text(verbatim: place.displayName)
      .font(.caption.weight(.semibold))
      .foregroundStyle(palette.secondaryInk.color)
      .lineLimit(1)
      .accessibilityIdentifier("widget.place")
  }

  @ViewBuilder
  private var note: some View {
    if let message = wording.message {
      Text(verbatim: message)
        .font(.caption2)
        .foregroundStyle(palette.secondaryInk.color)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
    }
  }
}

/// Setup required, no times, or times that need refreshing: a symbol and the app's words, never a
/// time or a countdown.
private struct NoticeWidget: View {
  let display: PrayerDisplay
  let wording: DisplayWording
  let place: Place?
  let family: WidgetFamily
  let palette: Palette

  private var symbol: String {
    switch display {
    case .setupRequired: "mappin.and.ellipse"
    case .expired: "clock.arrow.circlepath"
    case .unavailable, .times: "exclamationmark.triangle"
    }
  }

  var body: some View {
    switch family {
    case .accessoryInline:
      Label {
        Text(verbatim: wording.short ?? "")
      } icon: {
        Image(systemName: symbol)
      }
    case .accessoryCircular:
      VStack(spacing: 2) {
        Image(systemName: symbol)
          .font(.title3)
          .widgetAccentable()
          .accessibilityHidden(true)
        Text(verbatim: wording.short ?? "")
          .font(.caption2)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.6)
      }
      .accessibilityElement(children: .combine)
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: wording.title ?? "")
          .font(.headline)
          .widgetAccentable()
        Text(verbatim: wording.message ?? "")
          .font(.caption)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    default:
      VStack(alignment: .leading, spacing: 6) {
        Image(systemName: symbol)
          .font(.title2)
          .foregroundStyle(palette.accent.color)
          .accessibilityHidden(true)
        Text(verbatim: wording.title ?? "")
          .font(.headline)
          .foregroundStyle(palette.ink.color)
          .accessibilityIdentifier("widget.title")
        Text(verbatim: wording.message ?? "")
          .font(.caption)
          .foregroundStyle(palette.secondaryInk.color)
          .minimumScaleFactor(0.7)
          .accessibilityIdentifier("widget.message")
        Spacer(minLength: 0)
        if let place {
          Text(verbatim: place.displayName)
            .font(.caption2)
            .foregroundStyle(palette.secondaryInk.color)
            .accessibilityIdentifier("widget.place")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }
}

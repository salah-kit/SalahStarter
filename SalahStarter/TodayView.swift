import SalahCore
import SalahUI
import SwiftUI

/// Today's prayer times at the chosen place, or the places to choose from.
struct TodayView: View {
  let model: AppModel

  var body: some View {
    Group {
      if let settings = model.settings {
        // The state changes at prayer times, which fall on whole minutes.
        TimelineView(.everyMinute) { context in
          TodayContent(settings: settings, now: context.date)
        }
      } else {
        SetupView(model: model)
      }
    }
    .navigationTitle(Text("Prayer Times"))
    .toolbar {
      if model.settings != nil {
        NavigationLink {
          SettingsView(model: model)
        } label: {
          Label {
            Text("Settings")
          } icon: {
            Image(systemName: "gearshape")
          }
        }
        .accessibilityIdentifier("open.settings")
      }
    }
  }
}

/// The places to choose from, before the app is set up.
private struct SetupView: View {
  let model: AppModel

  var body: some View {
    List {
      Section {
        ForEach(Place.presets) { place in
          Button {
            model.choose(place)
          } label: {
            Text(verbatim: place.displayName)
          }
          .accessibilityIdentifier("setup.\(place.id)")
        }
      } header: {
        Text("Choose a place")
      } footer: {
        Text("The widget shows the place's prayer times once you choose it.")
      }
    }
    .accessibilityIdentifier("setup")
  }
}

/// The place, the next prayer and the day's times.
private struct TodayContent: View {
  let settings: PrayerSettings
  let now: Date
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    let palette = Palette.of(colorScheme)
    let schedule = settings.schedule
    let zone = settings.place.location.timeZone
    // Look two days ahead, so the state after Isha still knows the next Fajr.
    let bound = CivilDay(containing: now, in: zone).adding(days: 2).start(in: zone)
    let display = PrayerDisplay(
      schedule.state(at: now, through: bound), day: schedule.day(containing: now))
    let wording = DisplayWording(display)
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: settings.place.displayName)
            .font(.title3.bold())
            .accessibilityIdentifier("today.place")
          Text(verbatim: methodName(settings.method))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("today.method")
        }
        switch display {
        case .times(let times):
          NextPrayerView(state: times.state, names: AppLanguage.names, timeZone: zone)
            .nextPrayerStyle(CardStyle(palette: palette))
            .padding()
            .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityIdentifier("today.next")
          if let day = times.day {
            PrayerTimesList(day: day, state: times.state, names: AppLanguage.names)
              .prayerRowStyle(RowStyle(palette: palette))
              .padding()
              .background(palette.surface.color, in: RoundedRectangle(cornerRadius: 16))
          }
          if let message = wording.message {
            Text(verbatim: message)
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
        case .setupRequired, .unavailable, .expired:
          VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: wording.title ?? "")
              .font(.headline)
            Text(verbatim: wording.message ?? "")
              .foregroundStyle(.secondary)
          }
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("today.notice")
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()
    }
  }
}

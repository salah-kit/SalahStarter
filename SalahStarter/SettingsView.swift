import SalahAlerts
import SalahCore
import SalahTimes
import SwiftUI
import UserNotifications

/// The place, the calculation and the alerts. Every change is saved at once.
struct SettingsView: View {
  let model: AppModel

  var body: some View {
    Form {
      if let settings = model.settings {
        Section {
          Picker(selection: binding(settings.place, model.choose)) {
            ForEach(Place.presets) { place in
              Text(verbatim: place.displayName).tag(place)
            }
          } label: {
            Text("Place")
          }
          .pickerStyle(.navigationLink)
          .accessibilityIdentifier("settings.place")
        } footer: {
          Text("Choosing a place selects the method suggested for its country.")
        }
        Section {
          Picker(selection: binding(settings.method, model.choose)) {
            ForEach(CalculationMethod.allCases, id: \.self) { method in
              Text(verbatim: methodName(method)).tag(method)
            }
          } label: {
            Text("Method")
          }
          .pickerStyle(.navigationLink)
          .accessibilityIdentifier("settings.method")
          Picker(selection: binding(settings.madhab, model.choose)) {
            Text("Standard (Shafi'i, Maliki, Hanbali)").tag(Madhab.shafi)
            Text("Hanafi").tag(Madhab.hanafi)
          } label: {
            Text("Asr")
          }
          .accessibilityIdentifier("settings.madhab")
        } header: {
          Text("Calculation")
        } footer: {
          Text("Mosques and communities in one country often follow different methods.")
        }
        AlertsSection(model: model, settings: settings)
        if let error = model.saveError {
          Section {
            Text("The widget's settings couldn't be saved: \(error)")
              .accessibilityIdentifier("settings.saveError")
          }
        }
      }
    }
    .navigationTitle(Text("Settings"))
  }

  /// A binding that shows `value` and hands a new choice to `choose`.
  private func binding<Value>(
    _ value: Value, _ choose: @escaping (Value) -> Task<Void, Never>
  ) -> Binding<Value> {
    Binding {
      value
    } set: { newValue in
      _ = choose(newValue)
    }
  }
}

/// The alert switch, the reminder, and what the system allows and confirmed.
private struct AlertsSection: View {
  let model: AppModel
  let settings: PrayerSettings

  private var alerts: AlertCoordinator { model.alerts }

  var body: some View {
    Section {
      Toggle(isOn: isOn) {
        Text("Prayer alerts")
      }
      .accessibilityIdentifier("alerts.toggle")
      if alerts.options.isOn {
        Picker(selection: reminder) {
          ForEach(AlertOptions.reminderChoices, id: \.self) { minutes in
            reminderText(minutes).tag(minutes)
          }
        } label: {
          Text("Reminder")
        }
        .accessibilityIdentifier("alerts.reminder")
        status
      }
    } header: {
      Text("Alerts")
    } footer: {
      Text("An alert at each prayer's time, Time Sensitive so it can come through a Focus.")
    }
  }

  @ViewBuilder
  private var status: some View {
    Text(authorizationText)
      .accessibilityIdentifier("alerts.authorization")
    Text(timeSensitiveText)
      .accessibilityIdentifier("alerts.timeSensitive")
    if let report = alerts.report {
      if let until = report.confirmedCoveredUntil, report.failures.isEmpty {
        let zone = settings.place.location.timeZone
        let date = until.formatted(
          Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone))
        Text("Alerts are scheduled until \(date).")
          .accessibilityIdentifier("alerts.coverage")
      } else if !report.failures.isEmpty, alerts.authorization == .authorized {
        Text("\(report.failures.count) alerts couldn't be scheduled.")
          .accessibilityIdentifier("alerts.coverage")
        // The system's own words, such as why it rejected a request. The app tries again
        // whenever it becomes active.
        if let reason = Self.firstReason(report) {
          Text(verbatim: reason)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("alerts.failure")
        }
      }
    }
  }

  private var authorizationText: LocalizedStringKey {
    switch alerts.authorization {
    case .authorized?, .provisional?, .ephemeral?: "Notifications are allowed."
    case .denied?: "Notifications are turned off in the Settings app."
    case .notDetermined?, nil: "Notifications aren't allowed yet."
    @unknown default: "Notifications aren't allowed yet."
    }
  }

  private var timeSensitiveText: LocalizedStringKey {
    switch alerts.timeSensitive {
    case .enabled?: "Time Sensitive alerts are allowed."
    case .disabled?: "Time Sensitive alerts are turned off in the Settings app."
    case .notSupported?, nil: "Time Sensitive alerts aren't available."
    @unknown default: "Time Sensitive alerts aren't available."
    }
  }

  /// The reason the system gave for the first request it rejected, if it gave one.
  private static func firstReason(_ report: NotificationApplyReport) -> String? {
    report.failures.sorted { $0.key < $1.key }.lazy.compactMap { _, failure in
      if case .addFailed(let reason) = failure { return reason }
      return nil
    }.first
  }

  private func reminderText(_ minutes: Int?) -> Text {
    if let minutes {
      Text("\(minutes) minutes before")
    } else {
      Text("None")
    }
  }

  private var isOn: Binding<Bool> {
    Binding {
      alerts.options.isOn
    } set: { isOn in
      Task { await alerts.setAlerts(on: isOn, settings: settings) }
    }
  }

  private var reminder: Binding<Int?> {
    Binding {
      alerts.options.reminderMinutes
    } set: { minutes in
      Task { await alerts.setReminder(minutes: minutes, settings: settings) }
    }
  }
}

/// A published method's name in the app's language.
func methodName(_ method: CalculationMethod) -> String {
  switch method {
  case .muslimWorldLeague: String(localized: "Muslim World League")
  case .isna: String(localized: "ISNA (North America)")
  case .egyptian: String(localized: "Egyptian General Authority of Survey")
  case .ummAlQura: String(localized: "Umm al-Qura (Makkah)")
  case .karachi: String(localized: "University of Islamic Sciences, Karachi")
  case .tehran: String(localized: "Institute of Geophysics, Tehran")
  case .diyanet: String(localized: "Diyanet (Türkiye)")
  case .dubai: String(localized: "Dubai")
  case .kuwait: String(localized: "Kuwait")
  case .qatar: String(localized: "Qatar")
  case .muis: String(localized: "MUIS (Singapore)")
  case .jakim: String(localized: "JAKIM (Malaysia)")
  case .kemenag: String(localized: "Kemenag (Indonesia)")
  case .moonsightingCommittee: String(localized: "Moonsighting Committee")
  }
}

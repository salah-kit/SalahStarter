import Foundation
import SalahCore

/// The identifiers the app and the widget extension share.
nonisolated enum AppIdentity {
  /// The App Group both targets declare in their entitlements.
  ///
  /// The build writes `APP_GROUP_IDENTIFIER` from `Config/Identity.xcconfig` into each target's
  /// entitlements and into the `AppGroupIdentifier` key of its Info.plist, where this reads it,
  /// so the code and the entitlements always name the same group.
  static let appGroup =
    Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? ""

  /// The widget's kind, which the app names when it asks WidgetKit for a reload.
  static let widgetKind = "PrayerWidget"
}

/// The language the app and the widget show: the first of the bundle's localizations that the
/// device prefers, English or Arabic.
nonisolated enum AppLanguage {
  /// The language's locale, with its native digits.
  static var locale: Locale {
    PrayerLocale.resolved(Bundle.main.preferredLocalizations.first ?? "en")
  }

  /// Prayer names in the app's language, from SalahCore's String Catalog.
  static var names: PrayerNames {
    PrayerNames(locale: locale)
  }
}

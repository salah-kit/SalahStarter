import Foundation
import SalahCore

/// A place to calculate prayer times for.
///
/// The template offers a few cities, so it runs without location services. A real app gets the
/// coordinates from Core Location, and the time zone and country code from a geocoder, and
/// builds the same `PrayerLocation`. Calculate in the place's time zone, not the device's.
nonisolated struct Place: Codable, Hashable, Identifiable, Sendable {
  /// A stable identifier, stored with the settings.
  var id: String
  /// The coordinates, time zone and country that SalahKit calculates with.
  var location: PrayerLocation

  static let makkah = Place(
    id: "makkah", latitude: 21.4225, longitude: 39.8262, zone: "Asia/Riyadh", country: "SA",
    name: "Makkah")
  static let cairo = Place(
    id: "cairo", latitude: 30.0444, longitude: 31.2357, zone: "Africa/Cairo", country: "EG",
    name: "Cairo")
  static let istanbul = Place(
    id: "istanbul", latitude: 41.0082, longitude: 28.9784, zone: "Europe/Istanbul",
    country: "TR", name: "Istanbul")
  static let karachi = Place(
    id: "karachi", latitude: 24.8607, longitude: 67.0011, zone: "Asia/Karachi", country: "PK",
    name: "Karachi")
  static let kualaLumpur = Place(
    id: "kualaLumpur", latitude: 3.1390, longitude: 101.6869, zone: "Asia/Kuala_Lumpur",
    country: "MY", name: "Kuala Lumpur")
  static let jakarta = Place(
    id: "jakarta", latitude: -6.2088, longitude: 106.8456, zone: "Asia/Jakarta", country: "ID",
    name: "Jakarta")
  static let london = Place(
    id: "london", latitude: 51.5074, longitude: -0.1278, zone: "Europe/London", country: "GB",
    name: "London")
  static let newYork = Place(
    id: "newYork", latitude: 40.7128, longitude: -74.0060, zone: "America/New_York",
    country: "US", name: "New York")

  /// The place's name in the app's language.
  var displayName: String {
    switch id {
    case Self.makkah.id: String(localized: "Makkah")
    case Self.cairo.id: String(localized: "Cairo")
    case Self.istanbul.id: String(localized: "Istanbul")
    case Self.karachi.id: String(localized: "Karachi")
    case Self.kualaLumpur.id: String(localized: "Kuala Lumpur")
    case Self.jakarta.id: String(localized: "Jakarta")
    case Self.london.id: String(localized: "London")
    case Self.newYork.id: String(localized: "New York")
    default: location.name ?? id
    }
  }

  /// The places the app offers.
  static let presets: [Place] = [
    makkah, cairo, istanbul, karachi, kualaLumpur, jakarta, london, newYork,
  ]

  private init(
    id: String, latitude: Double, longitude: Double, zone: String, country: String,
    name: String
  ) {
    self.id = id
    location = PrayerLocation(
      latitude: latitude, longitude: longitude,
      // Every identifier above is in every time zone database; GMT only guards a broken one.
      timeZone: TimeZone(identifier: zone) ?? .gmt, countryCode: country, name: name)
  }
}

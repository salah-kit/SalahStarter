import SalahUI
import SwiftUI

/// The app's colors, for the widget and the app's next-prayer card.
///
/// Replace them with your own. The unit tests check every text color against its surface with
/// SalahUI's `ContrastCheck`, so a change that makes text hard to read fails a test.
nonisolated struct Palette: Hashable, Sendable {
  /// The background of the widget and the card.
  var surface: ThemeColor
  /// Body text: names and times.
  var ink: ThemeColor
  /// Supporting text: the place and notes.
  var secondaryInk: ThemeColor
  /// The next prayer and its countdown.
  var accent: ThemeColor

  static let light = Palette(
    surface: ThemeColor(red: 0.957, green: 0.945, blue: 0.910),
    ink: ThemeColor(red: 0.106, green: 0.165, blue: 0.141),
    secondaryInk: ThemeColor(red: 0.290, green: 0.353, blue: 0.322),
    accent: ThemeColor(red: 0.059, green: 0.420, blue: 0.310))

  static let dark = Palette(
    surface: ThemeColor(red: 0.078, green: 0.125, blue: 0.106),
    ink: ThemeColor(red: 0.933, green: 0.949, blue: 0.937),
    secondaryInk: ThemeColor(red: 0.714, green: 0.769, blue: 0.737),
    accent: ThemeColor(red: 0.373, green: 0.827, blue: 0.651))

  /// The palette for a color scheme.
  static func of(_ scheme: ColorScheme) -> Palette {
    scheme == .dark ? dark : light
  }
}

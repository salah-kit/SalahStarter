import XCTest

/// Helpers shared by the journeys. The class is `nonisolated` and its members `@MainActor`, so
/// it compiles under both default-isolation settings: XCTestCase's initializers and `setUp`
/// aren't main-actor isolated.
nonisolated class JourneyCase: XCTestCase {
  /// The app's display name, which Springboard shows: `APP_DISPLAY_NAME` from
  /// Config/Identity.xcconfig, through this bundle's Info.plist.
  static let appName =
    Bundle(for: JourneyCase.self).object(forInfoDictionaryKey: "AppDisplayName") as? String
    ?? "Salah Starter"

  /// Launches the app in a language, without settings when `reset` is set.
  @MainActor
  func launch(language: String = "en", reset: Bool) -> XCUIApplication {
    continueAfterFailure = false
    let app = XCUIApplication()
    let locale = language == "ar" ? "ar_SA" : "en_US"
    app.launchArguments =
      ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
      + (reset ? ["-resetSettings"] : [])
    app.launch()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    return app
  }

  @MainActor
  func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  /// The element's label, without the directional isolates (U+2068, U+2069) that Foundation
  /// puts around arguments interpolated into strings.
  @MainActor
  func label(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 10) -> String {
    let element = element(identifier, in: app)
    XCTAssertTrue(element.waitForExistence(timeout: timeout), "\(identifier) is missing")
    return Self.clean(element.label)
  }

  /// Waits until the element's label satisfies `predicate`, and returns it.
  @MainActor
  @discardableResult
  func waitForLabel(
    _ identifier: String, in app: XCUIApplication, timeout: TimeInterval,
    _ predicate: (String) -> Bool
  ) -> String {
    let deadline = Date().addingTimeInterval(timeout)
    var last = ""
    repeat {
      let element = element(identifier, in: app)
      if element.exists {
        last = Self.clean(element.label)
        if predicate(last) { return last }
      }
      Thread.sleep(forTimeInterval: 1)
    } while Date() < deadline
    XCTFail("\(identifier) still reads \"\(last)\" after \(timeout) s")
    return last
  }

  static func clean(_ text: String) -> String {
    text.filter { $0 != "\u{2068}" && $0 != "\u{2069}" }
  }

  @MainActor
  func screenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Opens Settings from the Today screen. Right after the app comes back to the front, the
  /// first tap can land before the screen takes touches, so it taps again if Settings didn't
  /// open.
  @MainActor
  func openSettings(in app: XCUIApplication) {
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    let button = element("open.settings", in: app)
    let settings = app.navigationBars["Settings"]
    for _ in 0..<2 where !settings.exists {
      XCTAssertTrue(button.waitForExistence(timeout: 10), "open.settings is missing")
      button.tap()
      _ = settings.waitForExistence(timeout: 5)
    }
    XCTAssertTrue(settings.exists, "Settings didn't open")
  }

  /// Chooses an option of a picker that pushes a list, and waits to come back.
  @MainActor
  func pick(_ option: String, from identifier: String, in app: XCUIApplication) {
    let picker = element(identifier, in: app)
    XCTAssertTrue(picker.waitForExistence(timeout: 10), "\(identifier) is missing")
    picker.tap()
    let row = app.buttons[option].firstMatch
    XCTAssertTrue(row.waitForExistence(timeout: 10), "\(option) isn't offered")
    row.tap()
    XCTAssertTrue(picker.waitForExistence(timeout: 10))
  }
}

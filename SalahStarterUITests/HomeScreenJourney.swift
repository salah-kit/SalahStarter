import XCTest

/// The real widget extension on the Home Screen, driven through Springboard.
///
/// The journey adds the medium widget the way a person does (Edit, Add Widget, the app, the
/// medium size, Add Widget, Done) and reads what the extension drew from Springboard's
/// accessibility tree. It proves the whole path: the app saves its settings to the App Group,
/// asks for a reload, and the extension reads the settings in its own process.
///
/// It skips itself when `SALAHSTARTER_SKIP_HOME_SCREEN=1`, which CI sets through
/// `TEST_RUNNER_SALAHSTARTER_SKIP_HOME_SCREEN`: Springboard's editing screens and WidgetKit's
/// timing on a cold hosted simulator aren't something a pull request should wait on.
nonisolated final class HomeScreenJourney: JourneyCase {
  @MainActor
  override func setUp() async throws {
    if ProcessInfo.processInfo.environment["SALAHSTARTER_SKIP_HOME_SCREEN"] == "1" {
      throw XCTSkip("Skipped on hosted CI runners; run it on a local simulator.")
    }
  }

  @MainActor
  func testTheWidgetFollowsTheApp() throws {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    // A fresh install: no settings in the App Group, so the widget asks for a place.
    var app = launch(reset: true)
    XCTAssertTrue(element("setup", in: app).waitForExistence(timeout: 10))
    app.terminate()
    removeWidgets(from: springboard)
    addMediumWidget(to: springboard)
    widgetText("widget.title", in: springboard) { $0 == "Choose a place" }
    screenshot("10-widget-setup")

    // Choosing a place in the app reloads the widget with that place's times.
    app = launch(reset: false)
    element("setup.makkah", in: app).tap()
    XCTAssertEqual(label("today.place", in: app), "Makkah")
    showWidget(on: springboard)
    widgetText("widget.place", in: springboard) { $0 == "Makkah" }
    widgetText("prayer.fajr", in: springboard) { $0.hasPrefix("Fajr") }
    screenshot("11-widget-makkah")

    // Another place: the extension reads the new settings.
    app.activate()
    openSettings(in: app)
    pick("Istanbul", from: "settings.place", in: app)
    showWidget(on: springboard)
    widgetText("widget.place", in: springboard) { $0 == "Istanbul" }

    removeWidgets(from: springboard)
  }

  // MARK: Springboard

  /// Adds the app's medium widget to the Home Screen.
  @MainActor
  private func addMediumWidget(to springboard: XCUIApplication) {
    XCUIDevice.shared.press(.home)
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    // A long press on empty space between the icons and the dock starts editing. A press
    // during a page transition does nothing, so it's tried again.
    let edit = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == 'Edit'")).firstMatch
    for _ in 0..<3 where !edit.exists {
      Thread.sleep(forTimeInterval: 1)
      springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        .press(forDuration: 1.5)
      _ = edit.waitForExistence(timeout: 5)
    }
    tap("Edit", in: springboard)
    tap("Add Widget", in: springboard)

    let gallery = springboard.descendants(matching: .any)["add-sheet-collection-view"]
    XCTAssertTrue(gallery.waitForExistence(timeout: 10), springboard.debugDescription)
    let row = gallery.descendants(matching: .any).matching(identifier: Self.appName).firstMatch
    for _ in 0..<10 where !(row.exists && row.isHittable) {
      gallery.swipeUp(velocity: .slow)
    }
    XCTAssertTrue(row.isHittable, springboard.debugDescription)
    row.tap()

    // The sizes are pages: small, then medium.
    let preview = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "\(Self.appName),")).firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 10), springboard.debugDescription)
    for _ in 0..<3 where !((preview.value as? String)?.contains("Medium") ?? false) {
      preview.swipeLeft()
    }
    XCTAssertEqual(preview.value as? String, "Widget, Medium", springboard.debugDescription)
    let add = springboard.buttons.matching(NSPredicate(format: "label CONTAINS 'Add Widget'"))
      .firstMatch
    XCTAssertTrue(add.waitForExistence(timeout: 5), springboard.debugDescription)
    add.tap()
    tap("Done", in: springboard)
  }

  /// Removes every widget of the app from the Home Screen, so a rerun starts from none.
  @MainActor
  private func removeWidgets(from springboard: XCUIApplication) {
    for _ in 0..<3 {
      guard showWidget(on: springboard) else { return }
      placedWidget(in: springboard).press(forDuration: 1.5)
      tap("Remove Widget", in: springboard)
      tap("Remove", in: springboard)
    }
  }

  @MainActor
  private func tap(_ label: String, in springboard: XCUIApplication) {
    let element = springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "label == %@", label)).firstMatch
    XCTAssertTrue(
      element.waitForExistence(timeout: 10), "\(label): \(springboard.debugDescription)")
    element.tap()
  }

  /// The placed widget on the page on screen: Springboard names it after the app and gives it
  /// the value "Widget".
  @MainActor
  private func placedWidget(in springboard: XCUIApplication) -> XCUIElement {
    springboard.descendants(matching: .any)
      .matching(NSPredicate(format: "identifier == %@ AND value == 'Widget'", Self.appName))
      .firstMatch
  }

  /// Goes to the Home Screen and to the page with the widget. Going to the background also
  /// lets WidgetKit run a reload it held while the app was in front.
  @MainActor
  @discardableResult
  private func showWidget(on springboard: XCUIApplication) -> Bool {
    XCUIDevice.shared.press(.home)
    let widget = placedWidget(in: springboard)
    if widget.waitForExistence(timeout: 3) && widget.isHittable { return true }
    // Back to the first page, then through the pages in turn. The page indicator bounds the
    // swipes: past the last page is the App Library.
    let indicator = springboard.pageIndicators.firstMatch
    for _ in 0..<6 where Self.page(indicator)?.number ?? 1 > 1 {
      springboard.swipeRight()
    }
    for _ in 0..<6 {
      if widget.waitForExistence(timeout: 2) && widget.isHittable { return true }
      guard let page = Self.page(indicator), page.number < page.count else { return false }
      springboard.swipeLeft()
    }
    return false
  }

  /// The page on screen and the number of pages, from the indicator's "Page 2 of 3".
  @MainActor
  private static func page(_ indicator: XCUIElement) -> (number: Int, count: Int)? {
    guard indicator.exists, let value = indicator.value as? String else { return nil }
    let numbers = value.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    guard numbers.count == 2 else { return nil }
    return (numbers[0], numbers[1])
  }

  /// Waits up to a minute for an element of the placed widget to show a label that satisfies
  /// `expected`.
  @MainActor
  private func widgetText(
    _ identifier: String, in springboard: XCUIApplication, _ expected: (String) -> Bool
  ) {
    let element = springboard.descendants(matching: .any).matching(identifier: identifier)
      .firstMatch
    let deadline = Date().addingTimeInterval(60)
    var last = ""
    repeat {
      if element.exists {
        last = Self.clean(element.label)
        if expected(last) { return }
      }
      Thread.sleep(forTimeInterval: 2)
    } while Date() < deadline
    XCTFail("\(identifier) reads \"\(last)\": \(springboard.debugDescription)")
  }
}

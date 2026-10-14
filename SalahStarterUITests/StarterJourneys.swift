import XCTest

/// The app as a person uses it: choosing a place, changing the calculation, turning alerts on,
/// and the same in Arabic.
nonisolated final class StarterJourneys: JourneyCase {
  /// The five prayers and sunrise, as the rows' identifiers name them.
  static let kinds = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"]

  @MainActor
  func testChoosingAPlaceShowsItsPrayerTimes() throws {
    var app = launch(reset: true)
    // A fresh install: the places to choose from.
    XCTAssertTrue(element("setup", in: app).waitForExistence(timeout: 10))
    element("setup.istanbul", in: app).tap()

    XCTAssertEqual(label("today.place", in: app), "Istanbul")
    XCTAssertEqual(label("today.method", in: app), "Diyanet (Türkiye)")
    for kind in Self.kinds {
      XCTAssertTrue(element("prayer.\(kind)", in: app).waitForExistence(timeout: 10), kind)
    }
    XCTAssertTrue(label("prayer.fajr", in: app).hasPrefix("Fajr"))
    XCTAssertTrue(element("today.next", in: app).exists)
    screenshot("01-today")

    // The choice outlives the launch.
    app.terminate()
    app = launch(reset: false)
    XCTAssertEqual(label("today.place", in: app), "Istanbul")

    // The calculation: another method, then the Hanafi Asr. Each choice moves Asr on its own:
    // the methods differ in their minutes, the schools in the shadow's length.
    let diyanetAsr = label("prayer.asr", in: app)
    openSettings(in: app)
    pick("Muslim World League", from: "settings.method", in: app)
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertEqual(label("today.method", in: app), "Muslim World League")
    let standardAsr = label("prayer.asr", in: app)
    XCTAssertNotEqual(standardAsr, diyanetAsr)
    openSettings(in: app)
    let madhab = element("settings.madhab", in: app)
    XCTAssertTrue(madhab.waitForExistence(timeout: 10))
    madhab.tap()
    app.buttons["Hanafi"].firstMatch.tap()
    screenshot("02-settings")
    app.navigationBars.buttons.element(boundBy: 0).tap()
    XCTAssertEqual(label("today.method", in: app), "Muslim World League")
    XCTAssertNotEqual(label("prayer.asr", in: app), standardAsr)
  }

  /// Turning alerts on asks for permission through the system's prompt, then schedules Time
  /// Sensitive alerts. The prompt appears once per simulator; later runs find permission given.
  @MainActor
  func testTurningOnAlerts() throws {
    let app = launch(reset: true)
    element("setup.makkah", in: app).tap()
    XCTAssertEqual(label("today.place", in: app), "Makkah")
    openSettings(in: app)

    let toggle = element("alerts.toggle", in: app)
    XCTAssertTrue(toggle.waitForExistence(timeout: 10))
    flip(toggle, to: true)
    allowNotificationsIfAsked()

    waitForLabel("alerts.authorization", in: app, timeout: 30) {
      $0 == "Notifications are allowed."
    }
    // The app has the Time Sensitive capability, and the person hasn't turned it off.
    XCTAssertEqual(label("alerts.timeSensitive", in: app), "Time Sensitive alerts are allowed.")
    let coverage = element("alerts.coverage", in: app)
    XCTAssertTrue(coverage.waitForExistence(timeout: 60), "no scheduling result")
    let failure = element("alerts.failure", in: app)
    if failure.exists, Self.clean(failure.label).contains("Source is not authorized") {
      // An iOS 27.0 simulator rejects every request added after the first permission until
      // the simulator restarts (SalahKit's CalculatedPhone found it too). The app reports it
      // honestly; the scheduling can't be checked on this boot.
      screenshot("03-alerts-rejected")
      throw XCTSkip(
        "The simulator rejected the requests after the first permission (\(Self.clean(failure.label))). Restart the simulator and run the journey again."
      )
    }
    waitForLabel("alerts.coverage", in: app, timeout: 30) {
      $0.hasPrefix("Alerts are scheduled until")
    }
    screenshot("03-alerts")

    // Off again: the status lines go with the switch.
    flip(toggle, to: false)
    XCTAssertTrue(element("alerts.coverage", in: app).waitForNonExistence(timeout: 10))
  }

  @MainActor
  func testArabicReadsRightToLeft() throws {
    let app = launch(language: "ar", reset: true)
    let makkah = element("setup.makkah", in: app)
    XCTAssertTrue(makkah.waitForExistence(timeout: 10))
    XCTAssertEqual(Self.clean(makkah.label), "مكة المكرمة")
    makkah.tap()

    let place = element("today.place", in: app)
    XCTAssertTrue(place.waitForExistence(timeout: 10))
    XCTAssertEqual(Self.clean(place.label), "مكة المكرمة")
    XCTAssertTrue(label("prayer.fajr", in: app).hasPrefix("الفجر"))
    // Right to left: the place's name hugs the right edge.
    let window = app.windows.firstMatch.frame
    XCTAssertGreaterThan(place.frame.midX, window.midX)
    screenshot("04-arabic")
  }

  /// Turns a switch on or off, tapping the control itself rather than its row.
  @MainActor
  private func flip(_ toggle: XCUIElement, to isOn: Bool) {
    let control = toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
    if (control.value as? String) != (isOn ? "1" : "0") {
      control.tap()
    }
    let deadline = Date().addingTimeInterval(5)
    while (control.value as? String) != (isOn ? "1" : "0") && Date() < deadline {
      Thread.sleep(forTimeInterval: 0.5)
    }
    XCTAssertEqual(control.value as? String, isOn ? "1" : "0")
  }

  /// Taps Allow on the system's notification prompt, if it appears.
  @MainActor
  private func allowNotificationsIfAsked() {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let allow = springboard.alerts.buttons["Allow"].firstMatch
    if allow.waitForExistence(timeout: 15) {
      allow.tap()
    }
  }
}

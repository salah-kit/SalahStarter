# Contributing to SalahStarter

Thanks for helping. This page covers building, testing and formatting the template. The
organization's code of conduct, security policy, support page and issue and pull-request
templates live once, in [salah-kit/.github](https://github.com/salah-kit/.github), and apply
here.

A change to the template reaches every project created from it afterwards, so keep the
template small: it shows how the pieces of SalahKit fit together in an app, and adopters build
their own app on it. Behavior that other apps need belongs in
[SalahKit](https://github.com/salah-kit/SalahKit), not here.

## Requirements

- Xcode 26 or later (Swift 6.2 or later), and an iOS 17 or later simulator.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) 2.46.0, only when you change `project.yml`.

Simulator builds need no signing team.

## Build and test

```sh
xcodebuild test -project SalahStarter.xcodeproj -scheme SalahStarter \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

That runs:

- `SalahStarterTests` (Swift Testing, hosted by the app): the widget's timelines over a week
  with a fixed clock, a late reload and the setup state; the settings, the App Group and the
  reload gating; the alerts' planning, wording and interruption levels, and turning them on and
  off against an in-memory notification center, so the tests never ask the system for
  permission; the palette's contrast and the Arabic strings.
- `SalahStarterUITests` (XCUITest), on the real app:
  - `StarterJourneys`: choosing a place on a fresh install, a relaunch, another method and
    the Hanafi Asr; turning alerts on through the system's permission prompt, Time Sensitive
    alerts allowed, and the alerts scheduled; Arabic, right to left.
  - `HomeScreenJourney`: adds the medium widget through Springboard and checks what the real
    extension draws, before and after the app chooses a place.

Run one journey with `-only-testing:SalahStarterUITests/HomeScreenJourney`.

### On an iOS 27.0 simulator

The first time the app is allowed to send notifications, an iOS 27.0 simulator rejects every
request it adds ("Source is not authorized") until the simulator restarts. The app shows the
system's reason, and the alert journey skips itself with that message instead of passing.
Restart the simulator (`xcrun simctl shutdown <udid>`, then run the tests again) and the
journey finds permission already given and passes. iOS 26 simulators, which CI uses, accept the
requests at once.

### Default isolation

New Xcode projects default to the main actor, and so does this one. The targets set
`SWIFT_DEFAULT_ACTOR_ISOLATION` to `$(APP_DEFAULT_ISOLATION)`, which is `MainActor` unless a
build passes another value. CI builds both:

```sh
xcodebuild build-for-testing -project SalahStarter.xcodeproj -scheme SalahStarter \
  -destination 'generic/platform=iOS Simulator' APP_DEFAULT_ISOLATION=nonisolated
```

Don't pass `SWIFT_DEFAULT_ACTOR_ISOLATION` itself on the command line: it would reach
SalahKit's and SalahTimes' targets too.

## The project file

`SalahStarter.xcodeproj` is generated from `project.yml`. After changing `project.yml`, or
adding or removing a file, run `xcodegen` in this folder and commit both. CI regenerates the
project with XcodeGen 2.46.0 and fails if anything differs, including the generated
entitlements files.

## Format

The repository uses `swift format` with the shared `.swift-format` configuration (identical
in every salah-kit repository). CI lints with the formatter of Swift 6.4 (`swift:6.4-noble`);
an older toolchain's formatter can disagree with it. CI fails on any finding:

```sh
scripts/lint.sh                                                     # what CI runs
swift format --in-place --recursive SalahStarter SalahStarterWidget Shared \
  SalahStarterTests SalahStarterUITests                             # fix findings
```

## Strings

The app's text is in `Shared/Localizable.xcstrings`, in English and Arabic. Machine-drafted
translations are marked `needs_review`; a native speaker sets a reviewed entry to `translated`.
Prayer names come from SalahKit's own catalog.

## Screenshots

The README's screenshots are attachments of the journeys, exported from a test run:

```sh
xcrun xcresulttool export attachments --path <result bundle> --output-path <folder>
sips -Z 600 <folder>/*.png
```

## Pull requests

- Keep each pull request to one topic, on a branch named for it.
- Add a test for every change in behavior. A bug fix comes with a test that would have caught
  the bug.
- CI must pass.
- Add a line to the Unreleased section of [CHANGELOG.md](CHANGELOG.md).

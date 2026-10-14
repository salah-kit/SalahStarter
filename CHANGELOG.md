# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). The template isn't versioned: "Use
this template" copies `main`, so changes are listed under Unreleased with the date they landed.

## [Unreleased]

### Added

- The template, on SalahKit from 0.2.0 (2026-10-14):
  - an iPhone app that shows today's prayer times at a chosen place, with the next prayer and
    its countdown from SalahUI, and settings for the place, the calculation method and Asr;
  - a widget extension (small, medium and three Lock Screen families) that builds its own
    timeline from the settings in the App Group it shares with the app, with words for the
    setup, unavailable and expired states;
  - prayer alerts with SalahAlerts: a 60-request budget, an optional reminder, alerts at
    prayer times marked Time Sensitive, and the Time Sensitive capability;
  - privacy manifests for both targets, a String Catalog in English and Arabic (the Arabic is
    machine-drafted and marked for review), and a palette that passes SalahUI's
    `ContrastCheck`;
  - identities in one file, `Config/Identity.xcconfig`, and the signing team in a gitignored
    `Config/Local.xcconfig`;
  - unit tests (the widget's timelines over a week with a fixed clock, the settings and the
    App Group, the alerts with an in-memory notification center), UI journeys (setting up,
    the calculation, alerts with the system's prompt, Arabic and right to left) and a Home
    Screen journey that adds the real widget;
  - CI: the generated-project check, builds under both default-isolation settings, the tests
    on an iPhone simulator, and lint.

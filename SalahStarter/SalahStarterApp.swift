import SwiftUI
import UserNotifications

@main
struct SalahStarterApp: App {
  @State private var model = AppModel.live()
  @Environment(\.scenePhase) private var scenePhase
  private let presenter = NotificationPresenter()

  init() {
    UNUserNotificationCenter.current().delegate = presenter
  }

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        TodayView(model: model)
      }
    }
    // Replan the alerts whenever the app becomes active, launch included. iOS keeps a limited
    // number of pending requests, so the plan reaches only a week or two ahead; an app that's
    // opened now and then keeps its alerts going.
    .onChange(of: scenePhase, initial: true) { _, phase in
      if phase == .active {
        Task { await model.alerts.replan(settings: model.settings) }
      }
    }
  }
}

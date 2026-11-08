import SwiftUI
import UIKit

@main
struct AISEEBINApp: App {
    /// Single view model for the app's one screen; owns the AR session for the app's lifetime.
    @State private var viewModel: NavigationViewModel

    init() {
        // First, so app.launch is the session's seq 0.
        UsageLog.shared.appDidLaunch()
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification,
                                               object: nil, queue: nil) { _ in
            UsageLog.shared.appWillTerminate()
        }
        _viewModel = State(initialValue: NavigationViewModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

import SwiftUI
import UIKit

/// NUS Open House Guide: the AISEE-BIN positioning and routing, with a tour of
/// the open-house locations and SoCat walking ahead on the camera view.
@main
struct NUSOpenHouseApp: App {
    @State private var viewModel: NavigationViewModel
    @State private var guide: TourGuide

    init() {
        // First, so app.launch is the session's seq 0.
        UsageLog.shared.appDidLaunch()
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification,
                                               object: nil, queue: nil) { _ in
            UsageLog.shared.appWillTerminate()
        }
        let vm = NavigationViewModel()
        vm.mode = .navigation
        vm.positioningSource = .phone
        let guide = TourGuide(viewModel: vm)
        _viewModel = State(initialValue: vm)
        _guide = State(initialValue: guide)
    }

    var body: some Scene {
        WindowGroup {
            NUSRootView(viewModel: viewModel, guide: guide)
        }
    }
}

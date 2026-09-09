import SwiftUI

@main
struct AISEEBINApp: App {
    /// Single view model for the app's one screen; owns the AR session for the app's lifetime.
    @State private var viewModel = NavigationViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}

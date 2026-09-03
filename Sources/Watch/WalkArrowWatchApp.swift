import SwiftUI

@main
struct WalkArrowWatchApp: App {
    @StateObject private var model = GuidanceModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear { model.start() }
        }
    }
}

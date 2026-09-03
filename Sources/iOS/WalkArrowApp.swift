import SwiftUI
import UIKit

@main
struct WalkArrowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(PhoneCoordinator.shared)
        }
    }
}

/// Exists solely to activate the watch session at launch.
///
/// The activation cannot hang off a view's lifecycle: when the watch wakes this
/// app in the background to ask for a route, no scene is created, and a session
/// whose delegate is set late has already missed the message.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        PhoneCoordinator.shared.activate()
        return true
    }
}

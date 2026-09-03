import Foundation

/// The container the iOS app and the share extension both write into.
enum AppGroup {
    static let identifier = "group.com.lxxjs.walkarrow"

    /// Shared defaults, or `nil` when the app group is not configured.
    ///
    /// This is checked rather than force-unwrapped because a fresh clone will
    /// not have the group provisioned yet, and crashing the share extension is
    /// a much worse failure than falling back to per-process storage.
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static var isConfigured: Bool { sharedDefaults != nil }
}

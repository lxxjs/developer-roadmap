// swift-tools-version:5.9
import PackageDescription

/// A package over the shared sources only, so the geometry, route tracking and
/// share parsing can be tested with `swift test` on a Mac without opening
/// Xcode. The app targets themselves live in `project.yml` — SPM cannot build
/// an iOS app with an embedded watch app and a share extension.
let package = Package(
    name: "WalkArrowCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "WalkArrowCore", targets: ["WalkArrowCore"]),
    ],
    targets: [
        .target(name: "WalkArrowCore", path: "Sources/Shared"),
        .testTarget(
            name: "WalkArrowCoreTests",
            dependencies: ["WalkArrowCore"],
            path: "Tests/SharedTests"
        ),
    ]
)

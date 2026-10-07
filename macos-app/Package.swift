// swift-tools-version:5.9
//
// Builds and tests the app's timing and sound code on its own, without Xcode or a Mac:
//   swift test --package-path macos-app
// The app target in BreatheFree.xcodeproj compiles these same files.
import PackageDescription

let package = Package(
    name: "BreatheCore",
    targets: [
        .target(name: "BreatheCore", path: "BreatheFree/Core"),
        .testTarget(name: "BreatheCoreTests", dependencies: ["BreatheCore"], path: "Tests/BreatheCoreTests"),
    ]
)

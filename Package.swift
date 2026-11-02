// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TrueCloudMac",
    platforms: [.macOS(.v13)],
    targets: [
        // Networking for TrueCloud (Firebase auth, Firestore profile, dashboard server actions).
        // Foundation only, so it is unit-testable without the UI.
        .target(name: "TrueCloudKit", path: "Sources/Kit"),
        .executableTarget(
            name: "TrueCloud",
            dependencies: ["TrueCloudKit"],
            path: "Sources",
            exclude: ["Kit"],
            sources: ["Mac", "Shared"]
        ),
        .testTarget(name: "TrueCloudKitTests", dependencies: ["TrueCloudKit"], path: "Tests/KitTests"),
    ]
)

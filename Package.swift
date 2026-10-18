// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchNote",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "NotchNote", targets: ["NotchNote"])],
    targets: [
        .executableTarget(name: "NotchNote", swiftSettings: [
            .defaultIsolation(MainActor.self),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault")
        ])
    ]
)

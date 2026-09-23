// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "VibeWatchCore", platforms: [.macOS(.v13)],
    products: [.library(name: "VibeWatchCore", targets: ["VibeWatchCore"])],
    targets: [
        .target(name: "VibeWatchCore", path: "Shared", exclude: ["APIClient.swift", "SharedStore.swift", "AppModel.swift", "QuotaViews.swift", "WatchQuotaViews.swift", "QuotaTimeline.swift", "PhoneWidgetViews.swift", "WatchDashboardViews.swift"], sources: ["Models.swift"]),
        .testTarget(name: "VibeWatchCoreTests", dependencies: ["VibeWatchCore"], path: "Tests")
    ]
)

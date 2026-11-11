// swift-tools-version: 6.0

import PackageDescription

// xtool project: exactly one library product, which is the app.
// Swift 5 language mode on purpose: it turns Swift 6 strict-concurrency errors
// into warnings, so the app compiles without Sendable plumbing.
let package = Package(
    name: "QConCollector",
    platforms: [
        .iOS(.v17),
        // Kept from xtool's template. xtool builds this target only for iOS (its generated
        // builder package lists .iOS alone), so the UIKit code never compiles for macOS.
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "QConCollector",
            targets: ["QConCollector"]
        ),
    ],
    targets: [
        .target(
            name: "QConCollector"
        ),
    ],
    swiftLanguageModes: [.v5]
)

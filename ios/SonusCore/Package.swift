// swift-tools-version: 6.0
import PackageDescription

// Platform-independent Sonus logic (no UIKit/SwiftUI/AVFoundation) so it builds and tests on
// Linux CI. The iOS app will depend on this package as sources move in.
let package = Package(
    name: "SonusCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SonusCore", targets: ["SonusCore"])
    ],
    targets: [
        .target(name: "SonusCore"),
        .testTarget(name: "SonusCoreTests", dependencies: ["SonusCore"])
    ]
)

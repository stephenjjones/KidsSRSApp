// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KidsSRSCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        // Pure, UI-free scheduling + domain logic. No CoreData / SwiftUI here.
        .library(name: "KidsSRSCore", targets: ["KidsSRSCore"])
    ],
    targets: [
        .target(
            name: "KidsSRSCore",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "KidsSRSCoreTests",
            dependencies: ["KidsSRSCore"]
        )
    ]
)

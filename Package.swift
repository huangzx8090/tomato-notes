// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TomatoNotes",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TomatoNotes", targets: ["TomatoNotes"])],
    targets: [
        .target(name: "TomatoCore"),
        .executableTarget(
            name: "TomatoNotes",
            dependencies: ["TomatoCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(name: "TomatoCoreTests", dependencies: ["TomatoCore"])
    ],
    swiftLanguageModes: [.v5]
)

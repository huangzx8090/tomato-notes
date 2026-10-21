// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TomatoNotes",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TomatoNotes", targets: ["TomatoNotes"]),
        .executable(name: "TomatoDataTool", targets: ["TomatoDataTool"]),
        .executable(name: "TomatoDiagnostics", targets: ["TomatoDiagnostics"])
    ],
    targets: [
        .target(name: "TomatoCore"),
        .target(name: "TomatoSystem", dependencies: ["TomatoCore"],
                linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("Security"), .linkedFramework("ImageIO")]),
        .executableTarget(name: "TomatoDataTool", dependencies: ["TomatoCore", "TomatoSystem"]),
        .executableTarget(name: "TomatoDiagnostics", dependencies: ["TomatoCore", "TomatoSystem"],
                          linkerSettings: [.linkedFramework("AppKit"), .linkedFramework("Carbon")]),
        .executableTarget(
            name: "TomatoNotes",
            dependencies: ["TomatoCore", "TomatoSystem"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit")
            ]
        ),
        .testTarget(name: "TomatoCoreTests", dependencies: ["TomatoCore"]),
        .testTarget(name: "TomatoSystemTests", dependencies: ["TomatoCore", "TomatoSystem"])
    ],
    swiftLanguageModes: [.v5]
)

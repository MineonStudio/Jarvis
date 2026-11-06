// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Jarvis",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Jarvis", targets: ["Jarvis"])
    ],
    dependencies: [],
    targets: [
        .target(name: "JarvisDesignSystem"),
        .target(
            name: "LANTransfer",
            dependencies: ["JarvisDesignSystem"],
            path: "Sources/LANTransfer",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Jarvis",
            dependencies: [
                "LANTransfer",
                "JarvisDesignSystem"
            ],
            path: "Sources/Jarvis",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "JarvisTests",
            dependencies: ["Jarvis"],
            path: "Tests/JarvisTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LANTransferTests",
            dependencies: ["LANTransfer"],
            path: "Tests/LANTransferTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VoiceKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v17),
        .visionOS(.v1),
    ],
    products: [
        .library(
            name: "VoiceKit",
            targets: ["VoiceKit"]
        ),
        .executable(
            name: "Dictate",
            targets: ["Dictate"]
        ),
    ],
    targets: [
        .target(
            name: "VoiceKit",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .executableTarget(
            name: "Dictate",
            dependencies: ["VoiceKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "DictateTests",
            dependencies: ["Dictate"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "VoiceKitTests",
            dependencies: ["VoiceKit"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)

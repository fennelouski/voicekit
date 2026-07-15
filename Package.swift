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
    dependencies: [
        // Speaker diarization (on-device CoreML). Dictate-only; VoiceKit stays dependency-free.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.9.0"),
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
            dependencies: [
                "VoiceKit",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
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

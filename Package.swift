// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartPrompting",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "SmartPromptingCore",
            targets: ["SmartPromptingCore"]
        ),
        .executable(
            name: "sp",
            targets: ["sp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "SmartPromptingCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/SmartPromptingCore"
        ),
        .executableTarget(
            name: "sp",
            dependencies: [
                "SmartPromptingCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/sp"
        ),
        .testTarget(
            name: "SmartPromptingCoreTests",
            dependencies: ["SmartPromptingCore"],
            path: "Tests/SmartPromptingCoreTests"
        )
    ]
)

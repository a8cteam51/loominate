// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Loominate",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Loominate",
            path: "Sources/Loominate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

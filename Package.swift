// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decaffeinate",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Decaffeinate", targets: ["Decaffeinate"])
    ],
    targets: [
        .executableTarget(
            name: "Decaffeinate",
            path: "Sources/Decaffeinate",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DecaffeinateTests",
            dependencies: ["Decaffeinate"],
            path: "Tests/DecaffeinateTests"
        )
    ]
)

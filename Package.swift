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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0")
    ],
    targets: [
        .executableTarget(
            name: "Decaffeinate",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Decaffeinate",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ],
            linkerSettings: [
                // So the embedded Sparkle.framework resolves inside the .app.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "DecaffeinateTests",
            dependencies: ["Decaffeinate"],
            path: "Tests/DecaffeinateTests"
        ),
    ]
)

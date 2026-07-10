// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decaffeinate",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Decaffeinate", targets: ["Decaffeinate"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .executableTarget(
            name: "Decaffeinate",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "MCP", package: "swift-sdk"),
            ],
            path: "Sources/Decaffeinate",
            resources: [
                // Localized string tables (en/de .lproj). With defaultLocalization
                // set above, SwiftPM copies these into Bundle.module
                // (Decaffeinate_Decaffeinate.bundle) as loadable per-language
                // tables — the .app carries the bundle via build-app.sh. See L10n
                // and docs/LOCALIZATION.md.
                .process("Resources")
            ],
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

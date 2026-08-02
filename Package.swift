// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Decaffeinate",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Decaffeinate", targets: ["Decaffeinate"]),
        // Phase B spike only — see docs/PHASE-B-SPIKE.md. A separate, unintegrated
        // executable: `Decaffeinate` does not depend on it, invoke it, or
        // reference it from any UI/menu/CLI path. Compiles and is unit-tested via
        // fakes; its real pmset/XPC/SMAppService calls are never executed.
        .executable(name: "DecaffeinateLidHelper", targets: ["DecaffeinateLidHelper"]),
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

        // MARK: - Phase B spike (docs/PHASE-B-SPIKE.md) — never invoked live.
        //
        // A standalone, unintegrated executable target: no product target above
        // depends on it, and `Decaffeinate` never imports or shells out to it.
        // It exists solely so the mechanism (a privileged helper that could set
        // the undocumented, root-only `pmset disablesleep` flag) compiles and is
        // unit-tested via fakes — see the hard safety constraints in the spike
        // doc for exactly what must never be executed.
        .executableTarget(
            name: "DecaffeinateLidHelper",
            path: "Sources/DecaffeinateLidHelper",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "DecaffeinateLidHelperTests",
            dependencies: ["DecaffeinateLidHelper"],
            path: "Tests/DecaffeinateLidHelperTests"
        ),
    ]
)

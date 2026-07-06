import Foundation

/// Static knowledge of which processes are shells (walk through), and which are
/// terminals / editors / agent hosts worth naming as the "origin" of a hold.
/// Pure string/bundle matching, so it's fully unit-testable.
enum OriginRegistry {

    /// Shells we walk *through* — they're never the origin themselves.
    static let shells: Set<String> = [
        "zsh", "bash", "sh", "fish", "dash", "tcsh", "ksh", "login",
        "-zsh", "-bash", "-fish", "tmux", "screen",
    ]

    /// Agent / CLI hosts worth naming as the origin command's owner. Matched
    /// against argv[0]'s basename and the proc name.
    static let agentCLIs: Set<String> = [
        "claude", "claude-code", "cursor", "cursor-agent", "aider", "node", "deno", "bun",
        "python", "python3", "ruby", "go", "cargo", "xcodebuild", "swift",
        "make", "docker", "npm", "pnpm", "yarn",
    ]

    /// proc-name → friendly terminal origin. Keyed on the executable/app name as
    /// `processName(forPID:)` returns it.
    static let terminalsByName: [String: (name: String, kind: OriginKind)] = [
        "Terminal": ("Terminal", .terminal),
        "iTerm2": ("iTerm2", .terminal),
        "iTerm": ("iTerm2", .terminal),
        "Ghostty": ("Ghostty", .terminal),
        "Warp": ("Warp", .terminal),
        "WarpPreview": ("Warp", .terminal),
        "kitty": ("kitty", .terminal),
        "Alacritty": ("Alacritty", .terminal),
        "WezTerm": ("WezTerm", .terminal),
        "wezterm-gui": ("WezTerm", .terminal),
        "Hyper": ("Hyper", .terminal),
        "Tabby": ("Tabby", .terminal),
    ]

    /// bundle-id prefix → friendly origin (terminals / editors / agent hosts).
    static let byBundlePrefix: [(prefix: String, name: String, kind: OriginKind)] = [
        ("com.apple.Terminal", "Terminal", .terminal),
        ("com.googlecode.iterm2", "iTerm2", .terminal),
        ("com.mitchellh.ghostty", "Ghostty", .terminal),
        ("dev.warp.Warp", "Warp", .terminal),
        ("net.kovidgoyal.kitty", "kitty", .terminal),
        ("org.alacritty", "Alacritty", .terminal),
        ("com.github.wez.wezterm", "WezTerm", .terminal),
        ("com.microsoft.VSCode", "VS Code", .editor),
        ("com.microsoft.VSCodeInsiders", "VS Code Insiders", .editor),
        ("com.visualstudio.code.oss", "VS Code", .editor),
        ("com.todesktop.230313mzl4w4u92", "Cursor", .editor),
        ("com.exafunction.windsurf", "Windsurf", .editor),
        ("dev.zed.Zed", "Zed", .editor),
        ("com.anthropic.claude", "Claude", .agentHost),
        ("com.anthropic.claudefordesktop", "Claude", .agentHost),
    ]

    /// Electron helper proc-name needles whose bundle is the real editor/host.
    static let electronHelperNeedles = [
        "Code Helper", "Cursor Helper", "Windsurf Helper", "Claude Helper", "Electron",
    ]

    static func isShell(_ name: String) -> Bool { shells.contains(name.lowercased()) }

    static func isAgentCLI(_ name: String) -> Bool {
        agentCLIs.contains((name as NSString).lastPathComponent.lowercased())
    }

    /// Classify one ancestor by name + optional bundle id. Returns nil when it's
    /// not a recognized terminal / editor / agent host.
    static func classify(name: String, bundleID: String?) -> (AssertionOwner, OriginKind)? {
        if let hit = terminalsByName[name] {
            return (AssertionOwner(name: hit.name, bundleIdentifier: bundleID), hit.kind)
        }
        if let bundleID {
            // Match on a segment boundary ("." or "-"), not a bare prefix: with
            // bare `hasPrefix`, "com.microsoft.VSCode" swallowed
            // "com.microsoft.VSCodeInsiders" (making that entry dead code and
            // misattributing the bundle id). The "-" boundary keeps channel
            // variants like dev.warp.Warp-Stable / dev.zed.Zed-Preview matching;
            // distinct products get their own entries (e.g.
            // com.anthropic.claudefordesktop above).
            for entry in byBundlePrefix
            where bundleID == entry.prefix || bundleID.hasPrefix(entry.prefix + ".")
                || bundleID.hasPrefix(entry.prefix + "-")
            {
                return (
                    AssertionOwner(name: entry.name, bundleIdentifier: entry.prefix), entry.kind
                )
            }
        }
        if electronHelperNeedles.contains(where: { name.contains($0) }) {
            return (AssertionOwner(name: name, bundleIdentifier: bundleID), .editor)
        }
        return nil
    }
}

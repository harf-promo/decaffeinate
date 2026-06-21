import Foundation

/// One hop in a holder's parent chain, from the holder up toward launchd.
struct ProcessLink: Hashable, Sendable {
    let pid: pid_t
    let name: String
}

/// What kind of thing spawned the process that's holding the Mac awake.
enum OriginKind: String, Hashable, Sendable {
    case terminal  // Terminal, iTerm2, Ghostty, Warp, kitty, Alacritty, WezTerm…
    case editor  // VS Code / "Code Helper", Cursor, Windsurf, Zed…
    case agentHost  // the "Claude" app, other agent shells
    case guiApp  // a generic regular GUI app that owns the subtree
    case launchAgent  // reparented to launchd / a LaunchAgent (terminal already gone)
    case unknown
}

/// Everything we resolved about where a sleep-holder (often `caffeinate`) came
/// from — the "this is from *this* window / agent / project" answer. Resolved
/// lazily from a pid by `ProcessProvenanceResolver`; a pure value otherwise.
struct ProcessProvenance: Hashable, Sendable {
    let holderPid: pid_t
    let holderName: String
    /// Tokenized command line of the holder (argv), already sanitized + clamped.
    let holderArgv: [String]
    /// Parent chain, holder-exclusive, nearest-first, bounded.
    let parentChain: [ProcessLink]
    /// The classified origin app/host, when identified (Terminal, VS Code, Claude…).
    let originApp: AssertionOwner?
    let originKind: OriginKind
    /// Controlling tty short name, e.g. "ttys004" (nil if none / detached).
    let ttyName: String?
    /// Current working directory of the holder, home-relativized for display.
    let cwd: String?
    /// argv of the nearest agent/CLI ancestor, when distinct from the holder.
    let originCommand: [String]?
    /// A short, display-ready one-liner, e.g. "started by Claude Code · in ~/dev/myrepo".
    let sessionLabel: String?

    /// The friendliest available name for who started this (origin app, else a
    /// recognized agent CLI, else nil).
    var originDisplayName: String? {
        originApp?.name ?? ProcessProvenance.friendlyAgentName(argv: originCommand ?? holderArgv)
    }

    /// Just the project folder, e.g. "~/myrepo" — the last path component of cwd.
    var projectLabel: String? {
        guard let cwd else { return nil }
        let last = (cwd as NSString).lastPathComponent
        return last.isEmpty || last == "~" ? cwd : "~/\(last)"
    }
}

extension ProcessProvenance {
    /// Map a holder's argv to a friendly agent/tool name when we can be confident
    /// (never guesses from a bare interpreter name alone).
    static func friendlyAgentName(argv: [String]) -> String? {
        guard let first = argv.first else { return nil }
        let base = (first as NSString).lastPathComponent.lowercased()
        let joined = argv.joined(separator: " ").lowercased()

        if base == "claude" || joined.contains("/.claude/") || joined.contains("claude code") {
            return "Claude Code"
        }
        if joined.contains("cursor") { return "Cursor" }
        if joined.contains("windsurf") { return "Windsurf" }
        if base == "aider" || joined.contains(" aider") { return "Aider" }
        return nil
    }

    /// Compose the one-line session label from already-resolved parts.
    static func composeLabel(originName: String?, cwd: String?, ttyName: String?) -> String? {
        var parts: [String] = []
        if let originName, !originName.isEmpty { parts.append("started by \(originName)") }
        if let cwd, let pretty = relativizeHome(cwd) { parts.append("in \(pretty)") }
        if parts.isEmpty, let ttyName { parts.append(ttyName) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// `/Users/me/dev/x` → `~/dev/x`; leaves other paths untouched. Returns nil
    /// for an empty or root path.
    static func relativizeHome(_ path: String) -> String? {
        guard !path.isEmpty, path != "/" else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

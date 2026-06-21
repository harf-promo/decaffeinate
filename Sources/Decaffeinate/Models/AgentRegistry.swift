import Foundation

/// A known agentic / long-running dev-tool identity. One source of truth for
/// both the "Common tools" watch list and AI-agent labelling.
struct AgentIdentity: Sendable, Hashable {
    let id: String
    let displayName: String
    let bundleIDs: [String]
    let processNames: [String]
    /// True → label as an "AI agent session" (Claude Code, Cursor…).
    let isAIAgent: Bool
    /// True → offered in the menu's "Common tools" watch list.
    let watchByDefault: Bool
}

enum AgentRegistry {
    static let all: [AgentIdentity] = [
        AgentIdentity(
            id: "claude-code", displayName: "Claude Code",
            bundleIDs: ["com.anthropic.claude"], processNames: ["claude", "claude-code"],
            isAIAgent: true, watchByDefault: true),
        AgentIdentity(
            id: "node", displayName: "Node", bundleIDs: [], processNames: ["node"],
            isAIAgent: false, watchByDefault: true),
        AgentIdentity(
            id: "python", displayName: "Python", bundleIDs: [], processNames: ["python3"],
            isAIAgent: false, watchByDefault: true),
        AgentIdentity(
            id: "xcodebuild", displayName: "xcodebuild", bundleIDs: [],
            processNames: ["xcodebuild"], isAIAgent: false, watchByDefault: true),
        AgentIdentity(
            id: "cargo", displayName: "cargo", bundleIDs: [], processNames: ["cargo"],
            isAIAgent: false, watchByDefault: true),
        AgentIdentity(
            id: "make", displayName: "make", bundleIDs: [], processNames: ["make"],
            isAIAgent: false, watchByDefault: true),
        AgentIdentity(
            id: "swift", displayName: "swift", bundleIDs: [], processNames: ["swift"],
            isAIAgent: false, watchByDefault: true),
        AgentIdentity(
            id: "docker", displayName: "docker", bundleIDs: [], processNames: ["docker"],
            isAIAgent: false, watchByDefault: true),
        // AI agents that aren't in the default watch list but get labelled.
        AgentIdentity(
            id: "cursor", displayName: "Cursor",
            bundleIDs: ["com.todesktop.230313mzl4w4u92"], processNames: ["cursor"],
            isAIAgent: true, watchByDefault: false),
        AgentIdentity(
            id: "windsurf", displayName: "Windsurf", bundleIDs: ["com.exafunction.windsurf"],
            processNames: ["windsurf"], isAIAgent: true, watchByDefault: false),
        AgentIdentity(
            id: "aider", displayName: "Aider", bundleIDs: [], processNames: ["aider"],
            isAIAgent: true, watchByDefault: false),
    ]

    /// The menu's "Common tools" watch list — one canonical name per default tool.
    /// Replaces the old hardcoded array on `AppState`.
    static var commonWatchProcessNames: [String] {
        all.filter(\.watchByDefault).compactMap { $0.processNames.first }
    }

    /// Identify a known agent/tool by (resolved) origin app name, bundle id, or any
    /// process name in the parent chain. Bundle/app matches win; a bare process-name
    /// match is the weakest signal (used cautiously by callers).
    static func identify(originApp: String?, bundleID: String?, processNames: [String])
        -> AgentIdentity?
    {
        if let bundleID,
            let hit = all.first(where: { $0.bundleIDs.contains(where: { bundleID.hasPrefix($0) }) })
        {
            return hit
        }
        if let originApp, let hit = all.first(where: { $0.displayName == originApp }) {
            return hit
        }
        let names = Set(processNames.map { ($0 as NSString).lastPathComponent.lowercased() })
        return all.first(where: { identity in
            identity.processNames.contains(where: { names.contains($0) })
        })
    }
}

import Foundation

/// One stable row in the menu: either a single power assertion (non-agent) or a
/// coalesced **agent session** — one or more live `caffeinate` holds that share
/// a session key. AI agents re-spawn `caffeinate -t` every few minutes, so the
/// pids churn; grouping by session key (agent + project + terminal) gives a row
/// whose `id` survives those respawns.
struct HoldGroup: Identifiable, Hashable {
    /// The stable session key (see `AppState.sessionKey(for:)`).
    let id: String
    /// A stable stand-in member (the longest-lived) used for the row's icon,
    /// menu, approval, and provenance-derived title.
    let representative: PowerAssertion
    /// All live holds sharing this session key (usually one; >1 during overlap).
    let members: [PowerAssertion]
    let isAgentSession: Bool
    /// When this session was first seen holding — the anchor for a stable
    /// "held since" that doesn't reset on a `-t` respawn.
    let firstSeen: Date?

    var liveCount: Int { members.count }
}

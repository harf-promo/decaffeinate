import Foundation
import MCP

/// The action a tool call resolves to — extracted so request→action parsing is a
/// pure function, unit-testable without a live transport.
enum MCPAction: Equatable {
    case status
    case keepAwake(minutes: Int)
    case releaseKeepAwake
    case sleepNow
    case sleepIfIdle(seconds: Int)
    case clamshellStatus
    /// A known tool called without an argument it requires; the message names it.
    case invalidArguments(String)
}

/// A Model Context Protocol server (`Decaffeinate --mcp`, stdio JSON-RPC) so an
/// agent can ask what's holding the Mac awake, hold it awake for a while, release
/// that hold, or sleep it — directly, without shelling out.
///
/// Self-contained: it owns its own `CaffeineEngine`, holds the IOKit assertion in
/// *this* process, and the kernel releases it when the process exits — exactly the
/// session-scoped lifetime an MCP client wants (the client spawns the server for
/// the session and kills it at the end). It deliberately does NOT expose "sleep
/// when I finish": an MCP server has no reliable turn-end signal and the client
/// hard-kills it at session end, so that job belongs to the Stop hook
/// (`--install-hook`), which fires as a fresh process exactly at turn end.
@MainActor
final class MCPServer {

    private let engine: any KeepAwakeControlling
    private var keepAwakeTask: Task<Void, Never>?
    private let railCheck: @MainActor () -> String?
    private let pollNanoseconds: UInt64

    /// Why a safety rail ended the last `keep_awake` hold early, reported by
    /// `whats_keeping_awake` until a new hold starts or the client releases it.
    private(set) var keepAwakeReleasedReason: String?

    /// `engine`, `railCheck` and `pollNanoseconds` are seams for tests; the app
    /// uses the defaults (a real `CaffeineEngine`, the live rails, 5 s polling).
    init(
        engine: any KeepAwakeControlling = CaffeineEngine(),
        railCheck: (@MainActor () -> String?)? = nil,
        pollNanoseconds: UInt64 = 5 * 1_000_000_000
    ) {
        self.engine = engine
        self.railCheck = railCheck ?? MCPServer.liveRailDropReason
        self.pollNanoseconds = pollNanoseconds
    }

    /// Build the server, register handlers, serve stdio until the client
    /// disconnects, then release the hold (also guaranteed by process exit).
    /// Serves stdio until the client disconnects. Returns `false` if the
    /// transport never came up — the caller turns that into a non-zero exit, so a
    /// supervisor can tell a dead server from a finished one.
    @discardableResult
    func run() async -> Bool {
        let server = Server(
            name: "Decaffeinate",
            version: AppInfo.version,
            capabilities: .init(tools: .init(listChanged: false)))

        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: MCPServer.toolList())
        }
        await server.withMethodHandler(CallTool.self) { [weak self] params in
            guard let self else {
                return CallTool.Result(
                    content: [MCPServer.contentText("Server stopped")], isError: true)
            }
            return await self.handle(params)
        }

        var served = true
        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data("decaffeinate --mcp: \(error)\n".utf8))
            served = false
        }
        keepAwakeTask?.cancel()
        engine.releaseAll()
        await server.stop()
        return served
    }

    /// Non-deprecated `Tool.Content.text` — the SDK's `.text(_:)`/`.text(text:)`
    /// convenience overloads are both deprecated in favor of the full enum case.
    nonisolated private static func contentText(_ s: String) -> Tool.Content {
        .text(text: s, annotations: nil, _meta: nil)
    }

    // MARK: - Tool catalogue (pure)

    nonisolated static func toolList() -> [Tool] {
        [
            Tool(
                name: "whats_keeping_awake",
                description:
                    "Report what's currently holding this Mac awake, as JSON (the same shape as `Decaffeinate --status --json`).",
                inputSchema: emptyObjectSchema),
            Tool(
                name: "keep_awake",
                description:
                    "Hold this Mac awake for a number of minutes (honouring the battery-floor and thermal safety rails). Releases automatically when the time elapses or the session ends.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "minutes": .object([
                            "type": .string("integer"),
                            "description": .string("How long to hold the Mac awake, in minutes."),
                        ])
                    ]),
                    "required": .array([.string("minutes")]),
                ])),
            Tool(
                name: "release_keep_awake",
                description: "Release any keep-awake hold this server is holding.",
                inputSchema: emptyObjectSchema),
            Tool(
                name: "sleep_now",
                description: "Put this Mac to sleep now.",
                inputSchema: emptyObjectSchema),
            Tool(
                name: "sleep_if_idle",
                description:
                    "Put this Mac to sleep only if it has been idle at least `seconds` seconds (default 300) — safe to call at the end of an unattended job.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "seconds": .object([
                            "type": .string("integer"),
                            "description": .string(
                                "Minimum idle seconds before sleeping (default 300)."),
                        ])
                    ]),
                ])),
            Tool(
                name: "clamshell_status",
                description:
                    "Report whether this Mac is ready for Apple's own built-in clamshell mode (lid closed, with an external display, AC power, and an external keyboard/mouse) — the same shape as `Decaffeinate --clamshell-status --json`. Read-only: never arms or changes anything.",
                inputSchema: emptyObjectSchema),
        ]
    }

    nonisolated private static let emptyObjectSchema: Value = .object([
        "type": .string("object"), "properties": .object([:]),
    ])

    // MARK: - Request → action (pure)

    nonisolated static func parseAction(name: String, arguments: [String: Value]?) -> MCPAction? {
        switch name {
        case "whats_keeping_awake": return .status
        case "release_keep_awake": return .releaseKeepAwake
        case "sleep_now": return .sleepNow
        case "keep_awake":
            guard let minutes = arguments?["minutes"]?.intValue else {
                return .invalidArguments("Missing required argument: minutes (integer).")
            }
            return .keepAwake(minutes: minutes)
        case "sleep_if_idle":
            let requested = arguments?["seconds"]?.intValue ?? HookInstaller.defaultIdleSeconds
            return .sleepIfIdle(seconds: HookInstaller.clampedIdleSeconds(requested))
        case "clamshell_status": return .clamshellStatus
        default:
            return nil
        }
    }

    // MARK: - Effectful dispatch (MainActor)

    private func handle(_ params: CallTool.Parameters) async -> CallTool.Result {
        guard let action = MCPServer.parseAction(name: params.name, arguments: params.arguments)
        else {
            return CallTool.Result(
                content: [MCPServer.contentText("Unknown tool: \(params.name)")], isError: true)
        }
        switch action {
        case .invalidArguments(let message):
            return .init(content: [MCPServer.contentText(message)], isError: true)
        case .status:
            return .init(content: [MCPServer.contentText(currentStatusJSON())], isError: false)
        case .keepAwake(let minutes):
            return .init(
                content: [MCPServer.contentText(startKeepAwake(minutes: minutes))], isError: false)
        case .releaseKeepAwake:
            keepAwakeTask?.cancel()
            keepAwakeReleasedReason = nil
            engine.releaseAll()
            return .init(
                content: [MCPServer.contentText("Released the keep-awake hold.")], isError: false)
        case .sleepNow:
            // Calls SleepController directly, not AppState.sleepNow() — an MCP
            // tool call is a non-interactive automation invocation with no one
            // to answer the "you appear to be on a call" confirmation the menu
            // button / hotkey path shows, so this stays immediate.
            switch SleepController().sleepNow() {
            case .success:
                return .init(
                    content: [MCPServer.contentText("Putting this Mac to sleep now.")],
                    isError: false)
            case .failure(let error):
                return .init(
                    content: [MCPServer.contentText("Couldn't sleep: \(error.description)")],
                    isError: true)
            }
        case .sleepIfIdle(let seconds):
            // Same gate as `--sleep-if-idle`: HID idle time AND the safety rails
            // (call, backup, update, media) — an agent's end-of-turn call must not
            // sleep the Mac mid-call.
            let note = MCPServer.idleFloorNote(
                requested: params.arguments?["seconds"]?.intValue, used: seconds)
            let (verdict, idle) = CLI.currentSleepIfIdleVerdict(threshold: seconds)
            if let message = MCPServer.sleepIfIdleHoldMessage(
                verdict: verdict, idleSeconds: idle, threshold: seconds)
            {
                return .init(content: [MCPServer.contentText(note + message)], isError: false)
            }
            switch SleepController().sleepNow() {
            case .success:
                return .init(
                    content: [
                        MCPServer.contentText(
                            note + "Idle \(Int(idle))s ≥ \(seconds)s — sleeping now.")
                    ],
                    isError: false)
            case .failure(let error):
                return .init(
                    content: [MCPServer.contentText("Couldn't sleep: \(error.description)")],
                    isError: true)
            }
        case .clamshellStatus:
            return .init(
                content: [MCPServer.contentText(currentClamshellStatusJSON())], isError: false)
        }
    }

    /// Engage the keep-awake hold now (refusing under a safety rail) and schedule
    /// an auto-release after `minutes`, re-checking the rails every few seconds —
    /// the async analogue of the `--keep-awake` foreground loop.
    ///
    /// When a rail ends the hold early, the reason is kept in
    /// `keepAwakeReleasedReason` and reported by `whats_keeping_awake`, so the
    /// client can tell its hold is gone.
    func startKeepAwake(minutes: Int) -> String {
        let clamped = min(max(minutes, 1), 24 * 60)
        if let reason = railCheck() {
            return "Not keeping awake — \(reason)."
        }
        keepAwakeTask?.cancel()
        keepAwakeReleasedReason = nil
        engine.update(
            keepSystemAwake: true, keepDisplayAwake: false, reason: "Decaffeinate MCP keep_awake")
        let deadline = Date().addingTimeInterval(TimeInterval(clamped) * 60)
        let poll = pollNanoseconds
        keepAwakeTask = Task { @MainActor [weak self] in
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: poll)
                if Task.isCancelled { return }
                guard let self else { return }
                if let reason = self.railCheck() {
                    self.keepAwakeReleasedReason = reason
                    self.engine.releaseAll()
                    return
                }
            }
            self?.engine.releaseAll()
        }
        return "Keeping this Mac awake for \(clamped) min (or until released / the session ends)."
    }

    /// A prefix for the `sleep_if_idle` reply when the requested threshold was
    /// raised to the floor, or "" when it was used as given.
    nonisolated static func idleFloorNote(requested: Int?, used: Int) -> String {
        guard let requested, requested != used else { return "" }
        return "Requested \(requested)s is below the \(used)s minimum; using \(used)s. "
    }

    /// The reply for a `sleep_if_idle` call that must NOT sleep, or nil to sleep.
    /// Pure so the MCP tool's safety-rail gate is unit-testable.
    nonisolated static func sleepIfIdleHoldMessage(
        verdict: CLI.SleepIfIdleVerdict, idleSeconds: TimeInterval, threshold: Int
    ) -> String? {
        switch verdict {
        case .sleep:
            return nil
        case .stillActive:
            return "Active \(Int(idleSeconds))s ago (< \(threshold)s) — leaving this Mac awake."
        case .leaveAwake(let reason):
            return "Not sleeping — leaving this Mac awake: \(reason)"
        }
    }

    private static func liveRailDropReason() -> String? {
        CLI.keepAwakeSafetyDropReason(
            power: PowerSourceReader().snapshot(),
            thermalState: ProcessInfo.processInfo.thermalState,
            settings: SettingsStore().settings)
    }

    private func currentStatusJSON() -> String {
        var report = StatusReport.from(
            version: AppInfo.version, now: Date(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            assertions: TelemetryEngine().scan(),
            power: PowerSourceReader().snapshot(),
            thermal: ProcessInfo.processInfo.thermalState,
            idleSeconds: IdleMonitor().secondsSinceLastInput(),
            uptimeSeconds: SystemStateReader().bootTime().map { Date().timeIntervalSince($0) }
        )
        report.keepAwakeReleasedReason = keepAwakeReleasedReason
        return report.jsonString()
    }

    /// Read-only clamshell readiness — same reads `CLI --clamshell-status`
    /// uses. Deliberately no `handle` case exists to *arm* a session: an
    /// agent must never decide to change this Mac's power-management posture.
    private func currentClamshellStatusJSON() -> String {
        let readiness = ClamshellAdvisor.classify(
            lid: LidStateReader().snapshot(),
            displays: DisplayTopologyReader().snapshot(),
            power: PowerSourceReader().snapshot(),
            input: ExternalInputProbe().probe())
        return ClamshellStatusReport.from(readiness: readiness).jsonString()
    }
}

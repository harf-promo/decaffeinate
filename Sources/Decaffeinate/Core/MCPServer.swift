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

    private let engine = CaffeineEngine()
    private var keepAwakeTask: Task<Void, Never>?

    /// Build the server, register handlers, serve stdio until the client
    /// disconnects, then release the hold (also guaranteed by process exit).
    func run() async {
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

        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            FileHandle.standardError.write(Data("decaffeinate --mcp: \(error)\n".utf8))
        }
        keepAwakeTask?.cancel()
        engine.releaseAll()
        await server.stop()
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
            guard let minutes = arguments?["minutes"]?.intValue else { return nil }
            return .keepAwake(minutes: minutes)
        case "sleep_if_idle":
            return .sleepIfIdle(
                seconds: arguments?["seconds"]?.intValue ?? HookInstaller.defaultIdleSeconds)
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
        case .status:
            return .init(content: [MCPServer.contentText(currentStatusJSON())], isError: false)
        case .keepAwake(let minutes):
            return .init(
                content: [MCPServer.contentText(startKeepAwake(minutes: minutes))], isError: false)
        case .releaseKeepAwake:
            keepAwakeTask?.cancel()
            engine.releaseAll()
            return .init(
                content: [MCPServer.contentText("Released the keep-awake hold.")], isError: false)
        case .sleepNow:
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
            let idle = IdleMonitor().secondsSinceLastInput()
            guard CLI.shouldSleep(idleSeconds: idle, threshold: seconds) else {
                return .init(
                    content: [
                        MCPServer.contentText(
                            "Active \(Int(idle))s ago (< \(seconds)s) — leaving this Mac awake.")
                    ],
                    isError: false)
            }
            switch SleepController().sleepNow() {
            case .success:
                return .init(
                    content: [
                        MCPServer.contentText("Idle \(Int(idle))s ≥ \(seconds)s — sleeping now.")
                    ],
                    isError: false)
            case .failure(let error):
                return .init(
                    content: [MCPServer.contentText("Couldn't sleep: \(error.description)")],
                    isError: true)
            }
        }
    }

    /// Engage the keep-awake hold now (refusing under a safety rail) and schedule
    /// an auto-release after `minutes`, re-checking the rails every few seconds —
    /// the async analogue of the `--keep-awake` foreground loop.
    private func startKeepAwake(minutes: Int) -> String {
        let clamped = min(max(minutes, 1), 24 * 60)
        if let reason = railDropReason() {
            return "Not keeping awake — \(reason)."
        }
        keepAwakeTask?.cancel()
        engine.update(
            keepSystemAwake: true, keepDisplayAwake: false, reason: "Decaffeinate MCP keep_awake")
        let deadline = Date().addingTimeInterval(TimeInterval(clamped) * 60)
        keepAwakeTask = Task { @MainActor [weak self] in
            while Date() < deadline {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                if Task.isCancelled { return }
                if self?.railDropReason() != nil {
                    self?.engine.releaseAll()
                    return
                }
            }
            self?.engine.releaseAll()
        }
        return "Keeping this Mac awake for \(clamped) min (or until released / the session ends)."
    }

    private func railDropReason() -> String? {
        CLI.keepAwakeSafetyDropReason(
            power: PowerSourceReader().snapshot(),
            thermalState: ProcessInfo.processInfo.thermalState,
            settings: SettingsStore().settings)
    }

    private func currentStatusJSON() -> String {
        StatusReport.from(
            version: AppInfo.version, now: Date(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            assertions: TelemetryEngine().scan(),
            power: PowerSourceReader().snapshot(),
            thermal: ProcessInfo.processInfo.thermalState,
            idleSeconds: IdleMonitor().secondsSinceLastInput(),
            uptimeSeconds: SystemStateReader().bootTime().map { Date().timeIntervalSince($0) }
        ).jsonString()
    }
}

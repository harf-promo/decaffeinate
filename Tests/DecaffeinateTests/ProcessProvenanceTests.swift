import XCTest

@testable import Decaffeinate

@MainActor
final class ProcessProvenanceTests: XCTestCase {

    private func resolve(_ pid: pid_t, _ intro: FakeProcessIntrospector) -> ProcessProvenance? {
        ProcessProvenanceResolver(introspector: intro).provenance(for: pid)
    }

    // MARK: Registry

    func testRegistryClassifiesTerminalsEditorsAgents() {
        XCTAssertEqual(OriginRegistry.classify(name: "Ghostty", bundleID: nil)?.1, .terminal)
        XCTAssertEqual(
            OriginRegistry.classify(name: "x", bundleID: "com.microsoft.VSCode")?.1, .editor)
        XCTAssertEqual(
            OriginRegistry.classify(name: "x", bundleID: "com.todesktop.230313mzl4w4u92")?.1,
            .editor)
        XCTAssertEqual(
            OriginRegistry.classify(name: "x", bundleID: "com.anthropic.claude")?.1, .agentHost)
        XCTAssertNil(OriginRegistry.classify(name: "zsh", bundleID: nil))
    }

    func testRegistryShellAndAgentCLI() {
        XCTAssertTrue(OriginRegistry.isShell("zsh"))
        XCTAssertTrue(OriginRegistry.isShell("-bash"))
        XCTAssertFalse(OriginRegistry.isShell("claude"))
        XCTAssertTrue(OriginRegistry.isAgentCLI("/opt/homebrew/bin/node"))
        XCTAssertFalse(OriginRegistry.isAgentCLI("Finder"))
    }

    // MARK: Pure label helpers

    func testFriendlyAgentName() {
        XCTAssertEqual(
            ProcessProvenance.friendlyAgentName(argv: ["claude", "--model", "opusplan"]),
            "Claude Code")
        XCTAssertEqual(
            ProcessProvenance.friendlyAgentName(argv: ["node", "/Users/x/.claude/local/cli.js"]),
            "Claude Code")
        XCTAssertNil(ProcessProvenance.friendlyAgentName(argv: ["node", "server.js"]))
        XCTAssertNil(ProcessProvenance.friendlyAgentName(argv: []))
    }

    func testComposeLabel() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(
            ProcessProvenance.composeLabel(
                originName: "Claude Code", cwd: home + "/dev/myrepo", ttyName: "ttys004"),
            "started by Claude Code · in ~/dev/myrepo")
        XCTAssertEqual(
            ProcessProvenance.composeLabel(originName: "Terminal", cwd: nil, ttyName: "ttys004"),
            "started by Terminal")
        XCTAssertEqual(
            ProcessProvenance.composeLabel(originName: nil, cwd: nil, ttyName: "ttys004"), "ttys004"
        )
        XCTAssertNil(ProcessProvenance.composeLabel(originName: nil, cwd: nil, ttyName: nil))
    }

    func testRelativizeHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        XCTAssertEqual(ProcessProvenance.relativizeHome(home + "/dev/x"), "~/dev/x")
        XCTAssertEqual(ProcessProvenance.relativizeHome(home), "~")
        XCTAssertEqual(ProcessProvenance.relativizeHome("/opt/thing"), "/opt/thing")
        XCTAssertNil(ProcessProvenance.relativizeHome("/"))
    }

    // MARK: The walk

    func testHolderIsGUIAppShortCircuits() {
        let intro = FakeProcessIntrospector()
        intro.add(100, ppid: 1, name: "Safari", bundleID: "com.apple.Safari", regularApp: "Safari")
        let p = resolve(100, intro)
        XCTAssertEqual(p?.originApp?.name, "Safari")
        XCTAssertEqual(p?.originKind, .guiApp)
        XCTAssertTrue(p?.parentChain.isEmpty == true)
    }

    func testCaffeinateThroughShellToTerminal() {
        let intro = FakeProcessIntrospector()
        intro.add(
            30, ppid: 20, name: "caffeinate", cwd: "/Users/me/dev/x", argv: ["caffeinate", "-i"])
        intro.add(20, ppid: 10, name: "zsh")
        intro.add(
            10, ppid: 1, name: "Terminal", bundleID: "com.apple.Terminal", regularApp: "Terminal")
        let p = resolve(30, intro)
        XCTAssertEqual(p?.originApp?.name, "Terminal")
        XCTAssertEqual(p?.originKind, .terminal)
        XCTAssertEqual(p?.parentChain.map(\.name), ["zsh", "Terminal"])
    }

    func testCaffeinateFromClaudeCodeNamedByVersion() {
        // Real-world: Claude Code's process name is its version ("2.1.183"), but
        // argv[0] is `claude`. We must identify it from the command line.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let intro = FakeProcessIntrospector()
        intro.add(
            30, ppid: 20, name: "caffeinate", cwd: home + "/dev/myrepo",
            argv: ["caffeinate", "-dimsu", "-w", "20"])
        intro.add(20, ppid: 10, name: "2.1.183", argv: ["claude", "--model", "opusplan"])
        intro.add(10, ppid: 1, name: "zsh")
        let p = resolve(30, intro)
        XCTAssertEqual(p?.originKind, .agentHost)
        XCTAssertEqual(p?.originDisplayName, "Claude Code")
        XCTAssertEqual(p?.originCommand?.first, "claude")
        XCTAssertEqual(p?.sessionLabel, "started by Claude Code · in ~/dev/myrepo")
    }

    func testReparentedToLaunchd() {
        let intro = FakeProcessIntrospector()
        intro.add(30, ppid: 1, name: "caffeinate", cwd: "/Users/me/dev/x")
        let p = resolve(30, intro)
        XCTAssertEqual(p?.originKind, .launchAgent)
        XCTAssertNil(p?.originApp)
        XCTAssertTrue(p?.parentChain.isEmpty == true)
    }

    func testCycleAndDepthTerminate() {
        let intro = FakeProcessIntrospector()
        intro.add(30, ppid: 20, name: "caffeinate")
        intro.add(20, ppid: 30, name: "weird")  // cycle back to 30
        XCTAssertNotNil(resolve(30, intro))  // must not hang

        let deep = FakeProcessIntrospector()
        for i in 2...40 { deep.add(pid_t(i), ppid: pid_t(i - 1), name: "p\(i)") }
        deep.add(41, ppid: 40, name: "caffeinate")
        XCTAssertNotNil(deep.facts(for: 41).map { _ in resolve(41, deep) })  // bounded, returns
    }

    func testGoneProcessIsNil() {
        XCTAssertNil(resolve(999, FakeProcessIntrospector()))
    }

    func testCachingResolvesOncePerTTL() {
        let intro = FakeProcessIntrospector()
        intro.add(30, ppid: 1, name: "caffeinate", cwd: "/x")
        var t = Date()
        let resolver = ProcessProvenanceResolver(introspector: intro, now: { t })
        _ = resolver.provenance(for: 30)
        _ = resolver.provenance(for: 30)
        // Two calls within TTL → same cached value; advancing past TTL re-resolves.
        t = t.addingTimeInterval(10)
        XCTAssertNotNil(resolver.provenance(for: 30))
    }
}

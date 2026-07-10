import XCTest

@testable import Decaffeinate

/// Pure tests for the hook config editors — no disk, no real `~/.claude` or
/// `~/.codex`.
final class HookInstallerTests: XCTestCase {

    private let bin = "/Applications/Decaffeinate.app/Contents/MacOS/Decaffeinate"

    private func stopCommands(_ data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let hooks = root["hooks"] as? [String: Any],
            let stop = hooks["Stop"] as? [[String: Any]]
        else { return [] }
        return stop.flatMap {
            ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    private func object(_ data: Data) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
    }

    // MARK: Claude Code (settings.json)

    func testInstallIntoNilCreatesStopHook() {
        let out = HookInstaller.installClaudeHook(into: nil, binaryPath: bin, seconds: 300)!
        let cmds = stopCommands(out)
        XCTAssertEqual(cmds.count, 1)
        XCTAssertTrue(cmds[0].contains("--sleep-if-idle 300"))
        XCTAssertTrue(cmds[0].contains(bin))
    }

    func testInstallIntoBlankFileStartsFresh() {
        XCTAssertNotNil(
            HookInstaller.installClaudeHook(into: Data(), binaryPath: bin, seconds: 300),
            "an empty file is 'absent', not a parse error")
        XCTAssertNotNil(
            HookInstaller.installClaudeHook(into: Data("  \n".utf8), binaryPath: bin, seconds: 300))
    }

    func testInstallIsIdempotentByteForByte() {
        let first = HookInstaller.installClaudeHook(into: nil, binaryPath: bin, seconds: 300)
        XCTAssertNotNil(first)
        let second = HookInstaller.installClaudeHook(into: first, binaryPath: bin, seconds: 300)
        XCTAssertEqual(first, second, "re-installing must not duplicate or reformat")
    }

    func testReinstallWithNewSecondsReplacesInPlace() {
        let first = HookInstaller.installClaudeHook(into: nil, binaryPath: bin, seconds: 300)
        let updated = HookInstaller.installClaudeHook(into: first, binaryPath: bin, seconds: 600)!
        let cmds = stopCommands(updated)
        XCTAssertEqual(cmds.count, 1, "no duplicate entry")
        XCTAssertTrue(cmds[0].contains("--sleep-if-idle 600"))
    }

    func testInstallPreservesForeignKeysAndHooks() {
        let input = Data(
            """
            {"model":"opus","hooks":{"Stop":[{"matcher":"Foo","hooks":[{"type":"command","command":"echo hi"}]}],"PreToolUse":[{"hooks":[{"type":"command","command":"lint"}]}]}}
            """.utf8)
        let out = HookInstaller.installClaudeHook(into: input, binaryPath: bin, seconds: 300)!
        let root = object(out)
        XCTAssertEqual(root["model"] as? String, "opus")
        let hooks = root["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["PreToolUse"], "unrelated hook events preserved")
        let cmds = stopCommands(out)
        XCTAssertTrue(cmds.contains("echo hi"), "foreign Stop hook preserved")
        XCTAssertTrue(cmds.contains { $0.contains("--sleep-if-idle 300") }, "our hook added")
    }

    func testUninstallRemovesOnlyOurs() {
        let input = Data(
            """
            {"hooks":{"Stop":[{"matcher":"Foo","hooks":[{"type":"command","command":"echo hi"}]}]}}
            """.utf8)
        let installed = HookInstaller.installClaudeHook(into: input, binaryPath: bin, seconds: 300)!
        let removed = HookInstaller.uninstallClaudeHook(from: installed)
        let cmds = stopCommands(removed!)
        XCTAssertEqual(cmds, ["echo hi"], "our hook gone, foreign hook intact")
    }

    func testUninstallWhenAbsentReturnsInputUnchanged() {
        let input = Data(
            """
            {"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo hi"}]}]}}
            """.utf8)
        let out = HookInstaller.uninstallClaudeHook(from: input)
        XCTAssertEqual(out, input, "no Decaffeinate hook present → bytes untouched")
    }

    func testInstallUninstallRoundTripDropsHooksKey() {
        let input = Data(
            """
            {"permissions":{"allow":["Bash"]}}
            """.utf8)
        let installed = HookInstaller.installClaudeHook(into: input, binaryPath: bin, seconds: 300)!
        let removed = HookInstaller.uninstallClaudeHook(from: installed)!
        let root = object(removed)
        XCTAssertNil(root["hooks"], "the empty hooks/Stop scaffold is pruned away")
        XCTAssertNotNil(root["permissions"], "unrelated keys survive the round-trip")
    }

    func testInstallRefusesPresentButMalformedFile() {
        // A hand-edit typo (a stray comma, a comment) must NEVER cost the user
        // their whole settings.json — refuse, don't clobber.
        let garbage = Data("{ not valid json, oops".utf8)
        XCTAssertNil(HookInstaller.installClaudeHook(into: garbage, binaryPath: bin, seconds: 300))
        XCTAssertNil(
            HookInstaller.uninstallClaudeHook(from: garbage),
            "never overwrite a file we can't parse")
    }

    func testInstallRefusesUnexpectedStopShape() {
        // `hooks.Stop` present but not an array of objects → refuse rather than
        // silently replace it with only our hook.
        let weird = Data("{\"hooks\":{\"Stop\":\"oops\"}}".utf8)
        XCTAssertNil(HookInstaller.installClaudeHook(into: weird, binaryPath: bin, seconds: 300))
        let weird2 = Data("{\"hooks\":\"nope\"}".utf8)
        XCTAssertNil(HookInstaller.installClaudeHook(into: weird2, binaryPath: bin, seconds: 300))
    }

    // MARK: Codex (config.toml notify)

    func testCodexInstallIntoEmptyAddsMarkedNotify() {
        let out = try! HookInstaller.installCodexNotify(into: "", binaryPath: bin, seconds: 300)
            .get()
        XCTAssertTrue(out.contains("notify = ["))
        XCTAssertTrue(out.contains("--sleep-if-idle"))
        XCTAssertTrue(out.contains("300"))
        XCTAssertTrue(out.contains(HookInstaller.codexMarker))
    }

    func testCodexInstallIsIdempotent() {
        let first = try! HookInstaller.installCodexNotify(into: "", binaryPath: bin, seconds: 300)
            .get()
        let second = try! HookInstaller.installCodexNotify(
            into: first, binaryPath: bin, seconds: 300
        )
        .get()
        XCTAssertEqual(first, second)
    }

    func testCodexReinstallUpdatesMarkedLineInPlace() {
        let first = try! HookInstaller.installCodexNotify(into: "", binaryPath: bin, seconds: 300)
            .get()
        let updated = try! HookInstaller.installCodexNotify(
            into: first, binaryPath: bin, seconds: 600
        )
        .get()
        let notifyLines = updated.split(separator: "\n").filter { $0.contains("notify") }
        XCTAssertEqual(notifyLines.count, 1, "no duplicate notify line")
        XCTAssertTrue(updated.contains("600"))
        XCTAssertFalse(updated.contains("300"))
    }

    func testCodexRefusesToClobberUnmarkedNotify() {
        let existing = "notify = [\"/usr/bin/say\", \"done\"]\n"
        let result = HookInstaller.installCodexNotify(into: existing, binaryPath: bin, seconds: 300)
        XCTAssertEqual(result, .failure(.wouldClobberExistingNotify))
    }

    func testCodexHonoursRootBeforeTables() {
        let existing = "[profile.default]\nmodel = \"gpt\"\n"
        let out = try! HookInstaller.installCodexNotify(
            into: existing, binaryPath: bin, seconds: 300
        )
        .get()
        let lines = out.split(separator: "\n", omittingEmptySubsequences: false)
        let notifyIdx = lines.firstIndex { $0.contains("notify") }!
        let tableIdx = lines.firstIndex { $0.hasPrefix("[profile") }!
        XCTAssertLessThan(notifyIdx, tableIdx, "notify must precede the first table header")
        XCTAssertTrue(out.contains("model = \"gpt\""), "existing table preserved")
    }

    func testCodexUninstallRemovesOnlyMarkedLine() {
        let installed = try! HookInstaller.installCodexNotify(
            into: "verbose = true\n", binaryPath: bin, seconds: 300
        )
        .get()
        let removed = HookInstaller.uninstallCodexNotify(from: installed)
        XCTAssertFalse(removed.contains("notify"), "our marked notify removed")
        XCTAssertTrue(removed.contains("verbose = true"), "other root keys untouched")
    }

    func testCodexUninstallLeavesUnmarkedNotifyAlone() {
        let userNotify = "notify = [\"/usr/bin/say\", \"done\"]\n"
        let out = HookInstaller.uninstallCodexNotify(from: userNotify)
        XCTAssertEqual(out, userNotify, "an unmarked user notify is never removed")
    }

    func testCodexClobberRefusalSurvivesNestedArrayBeforeNotify() {
        // A `[1, 2]`-leading array-element line must not be mistaken for a table
        // header, or the real root `notify` below it would be missed and we'd
        // write a duplicate `notify` key (invalid TOML).
        let existing = """
            matrix = [
              [1, 2],
              [3, 4],
            ]
            notify = ["/usr/bin/say", "done"]
            """
        XCTAssertEqual(
            HookInstaller.installCodexNotify(into: existing, binaryPath: bin, seconds: 300),
            .failure(.wouldClobberExistingNotify))
    }

    func testCodexClobberRefusalSurvivesMultilineStringBeforeNotify() {
        // `[not a table]` inside a triple-quoted string must not end the root region.
        let existing = "desc = \"\"\"\n[not a table]\n\"\"\"\nnotify = [\"/usr/bin/say\"]\n"
        XCTAssertEqual(
            HookInstaller.installCodexNotify(into: existing, binaryPath: bin, seconds: 300),
            .failure(.wouldClobberExistingNotify))
    }

    func testCodexNotifyInsideRealTableIsNotClobbered() {
        // A sub-table key named `notify` (`[hooks].notify`) is NOT the root notify;
        // installing must add our root notify and leave the sub-table key alone.
        let existing = "[hooks]\nnotify = \"something\"\n"
        let out = try! HookInstaller.installCodexNotify(
            into: existing, binaryPath: bin, seconds: 300
        )
        .get()
        XCTAssertTrue(out.contains("[hooks]"))
        XCTAssertTrue(out.contains("notify = \"something\""), "the sub-table key survives")
        XCTAssertTrue(out.contains(HookInstaller.codexMarker), "our root notify was added")
    }
}

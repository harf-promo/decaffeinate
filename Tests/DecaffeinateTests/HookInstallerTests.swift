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

    // MARK: Shell quoting (B-052)

    func testHookCommandLeavesSafePathBare() {
        XCTAssertEqual(
            HookInstaller.claudeHookCommand(binaryPath: bin, seconds: 5), "\(bin) --sleep-if-idle 5"
        )
    }

    func testHookCommandQuotesPathWithSpaceAndSingleQuote() {
        let path = "/Users/o'brien/My Apps/Decaffeinate.app/Contents/MacOS/Decaffeinate"
        let expected =
            "'/Users/o'\\''brien/My Apps/Decaffeinate.app/Contents/MacOS/Decaffeinate' --sleep-if-idle 5"
        XCTAssertEqual(HookInstaller.claudeHookCommand(binaryPath: path, seconds: 5), expected)
        XCTAssertEqual(HookInstaller.cursorHookCommand(binaryPath: path, seconds: 5), expected)
        XCTAssertTrue(HookInstaller.isDecaffeinateHookCommand(expected))
    }

    func testShellQuoteNeutralisesMetacharacters() {
        XCTAssertEqual(HookInstaller.shellQuote("a$(x);b"), "'a$(x);b'")
        XCTAssertEqual(HookInstaller.shellQuote(""), "''")
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

    // MARK: Minimal JSON edits (M2): never reformat the user's file

    /// A hand-written settings file: 4-space indent, non-sorted keys, numbers a
    /// `JSONSerialization` round trip would rewrite (`0.1` → `0.10000000000000001`).
    private let handWritten = """
        {
            "zeta": 0.1,
            "alpha": 1.0e2,
            "big": 12345678901234567890,
            "permissions": {
                "allow": ["Bash"]
            },
            "url": "https://example.com/a/b"
        }

        """

    func testInstallKeepsTheUsersNumbersKeyOrderAndLayout() throws {
        let out = try XCTUnwrap(
            HookInstaller.installClaudeHook(
                into: Data(handWritten.utf8), binaryPath: bin, seconds: 300))
        let text = String(decoding: out, as: UTF8.self)
        XCTAssertTrue(text.contains("\"zeta\": 0.1,"), "0.1 must not become 0.10000000000000001")
        XCTAssertTrue(text.contains("\"alpha\": 1.0e2,"), "number lexeme preserved")
        XCTAssertTrue(text.contains("12345678901234567890"), "big integer preserved")
        XCTAssertTrue(text.contains("https://example.com/a/b"), "slashes not escaped")
        XCTAssertTrue(
            text.contains("    \"permissions\": {\n        \"allow\": [\"Bash\"]\n    },"),
            "untouched members keep their exact bytes")
        XCTAssertLessThan(
            text.range(of: "zeta")!.lowerBound, text.range(of: "alpha")!.lowerBound,
            "key order is the user's, not sorted")
        XCTAssertEqual(stopCommands(out).count, 1)
        XCTAssertTrue(text.hasSuffix("    }\n}\n"), "trailing bytes preserved")
    }

    func testInstallThenUninstallRestoresTheOriginalBytes() throws {
        let original = Data(handWritten.utf8)
        let installed = try XCTUnwrap(
            HookInstaller.installClaudeHook(into: original, binaryPath: bin, seconds: 300))
        XCTAssertNotEqual(installed, original)
        XCTAssertEqual(HookInstaller.uninstallClaudeHook(from: installed), original)
    }

    func testReinstallOfAHandWrittenFileIsByteStable() throws {
        let first = try XCTUnwrap(
            HookInstaller.installClaudeHook(
                into: Data(handWritten.utf8), binaryPath: bin, seconds: 300))
        let second = HookInstaller.installClaudeHook(into: first, binaryPath: bin, seconds: 300)
        XCTAssertEqual(second, first)
    }

    func testUninstallKeepsNumbersWhenOtherHooksRemain() throws {
        let input = """
            {"ratio": 0.1, "hooks": {"Stop": [{"matcher": "Foo", "hooks": [{"type": "command", "command": "echo hi"}]}]}}
            """
        let installed = try XCTUnwrap(
            HookInstaller.installClaudeHook(into: Data(input.utf8), binaryPath: bin, seconds: 300))
        let removed = try XCTUnwrap(HookInstaller.uninstallClaudeHook(from: installed))
        XCTAssertEqual(String(decoding: removed, as: UTF8.self), input)
    }

    func testUninstallRemovesOnlyOurEntryFromASharedGroup() throws {
        let ours = HookInstaller.claudeHookCommand(binaryPath: bin, seconds: 300)
        let input = """
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo hi"}, {"type": "command", "command": "\(ours)"}]}]}}
            """
        let removed = try XCTUnwrap(HookInstaller.uninstallClaudeHook(from: Data(input.utf8)))
        XCTAssertEqual(stopCommands(removed), ["echo hi"])
        XCTAssertEqual(
            String(decoding: removed, as: UTF8.self),
            """
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo hi"}]}]}}
            """)
    }

    func testInstallKeepsAForeignEntrySharingAGroupWithOurOldHook() throws {
        let old = HookInstaller.claudeHookCommand(binaryPath: bin, seconds: 120)
        let input = """
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo hi"}, {"type": "command", "command": "\(old)"}]}]}}
            """
        let out = try XCTUnwrap(
            HookInstaller.installClaudeHook(into: Data(input.utf8), binaryPath: bin, seconds: 300))
        let cmds = stopCommands(out)
        XCTAssertTrue(cmds.contains("echo hi"), "a foreign hook is never dropped with ours")
        XCTAssertEqual(cmds.filter { $0.contains("--sleep-if-idle") }.count, 1)
        XCTAssertTrue(cmds.contains { $0.contains("--sleep-if-idle 300") })
    }

    func testInstallEditsACompactSingleLineFileCompactly() throws {
        let input = "{\"ratio\":0.1}"
        let out = try XCTUnwrap(
            HookInstaller.installClaudeHook(into: Data(input.utf8), binaryPath: bin, seconds: 300))
        let text = String(decoding: out, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("{\"ratio\":0.1, \"hooks\""), text)
        XCTAssertFalse(text.contains("\n"), "a one-line file stays one line")
        XCTAssertEqual(stopCommands(out).count, 1)
    }

    func testCursorEditsKeepNumbersAndRoundTripBytes() throws {
        let input = """
            {
              "version": 1,
              "scale": 0.1,
              "hooks": {
                "stop": [{ "command": "echo hi" }]
              }
            }

            """
        let installed = try XCTUnwrap(
            HookInstaller.installCursorHook(
                into: Data(input.utf8), binaryPath: bin, seconds: 300))
        XCTAssertTrue(String(decoding: installed, as: UTF8.self).contains("\"scale\": 0.1,"))
        XCTAssertEqual(cursorStopCommands(installed).count, 2)
        let removed = HookInstaller.uninstallCursorHook(from: installed)
        XCTAssertEqual(removed.map { String(decoding: $0, as: UTF8.self) }, input)
    }

    // MARK: Writing through symlinks (M2)

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("decaf-hook-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func mode(of url: URL) throws -> Int {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }

    private func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    func testAtomicWriteThroughASymlinkUpdatesTheTargetAndKeepsTheLink() throws {
        let dir = try makeTempDir()
        let target = dir.appendingPathComponent("real.json")
        let link = dir.appendingPathComponent("settings.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try HookInstaller.atomicWrite(Data("{\"a\": 1}".utf8), to: link)

        XCTAssertTrue(isSymlink(link), "the symlink must survive an install")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "{\"a\": 1}")
        XCTAssertEqual(try mode(of: target), 0o600, "the target's mode is preserved")
    }

    func testAtomicWriteFollowsARelativeSymlinkChain() throws {
        let dir = try makeTempDir()
        let dotfiles = dir.appendingPathComponent("dotfiles", isDirectory: true)
        let home = dir.appendingPathComponent("home", isDirectory: true)
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("claude.json")
        try Data("old".utf8).write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: target.path)
        let hop = dotfiles.appendingPathComponent("hop.json")
        try FileManager.default.createSymbolicLink(
            atPath: hop.path, withDestinationPath: "claude.json")
        let link = home.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: "../dotfiles/hop.json")

        try HookInstaller.atomicWrite(Data("new".utf8), to: link)

        XCTAssertTrue(isSymlink(link))
        XCTAssertTrue(isSymlink(hop))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "new")
        XCTAssertEqual(try mode(of: target), 0o640)
    }

    func testAtomicWriteCreatesTheTargetOfADanglingSymlink() throws {
        let dir = try makeTempDir()
        let target = dir.appendingPathComponent("missing/real.json")
        let link = dir.appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(
            atPath: link.path, withDestinationPath: target.path)

        try HookInstaller.atomicWrite(Data("x".utf8), to: link)

        XCTAssertTrue(isSymlink(link))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "x")
    }

    func testAtomicWriteKeepsThePlainFileMode() throws {
        let dir = try makeTempDir()
        let file = dir.appendingPathComponent("settings.json")
        try Data("{}".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)

        try HookInstaller.atomicWrite(Data("{\"a\": 2}".utf8), to: file)

        XCTAssertEqual(try mode(of: file), 0o600)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{\"a\": 2}")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(leftovers, ["settings.json"], "no temp file left behind")
    }

    func testAtomicWriteRefusesASymlinkLoop() throws {
        let dir = try makeTempDir()
        let a = dir.appendingPathComponent("a.json")
        let b = dir.appendingPathComponent("b.json")
        try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: b.path)
        try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: a.path)
        XCTAssertThrowsError(try HookInstaller.atomicWrite(Data("x".utf8), to: a))
        XCTAssertTrue(isSymlink(a), "a loop is never replaced with a regular file")
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

    // MARK: Cursor (~/.cursor/hooks.json)

    private func cursorStopCommands(_ data: Data) -> [String] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let hooks = root["hooks"] as? [String: Any],
            let stop = hooks["stop"] as? [[String: Any]]
        else { return [] }
        return stop.compactMap { $0["command"] as? String }
    }

    func testCursorInstallIntoNilCreatesStopHook() {
        let out = HookInstaller.installCursorHook(into: nil, binaryPath: bin, seconds: 300)!
        let root = object(out)
        XCTAssertEqual(root["version"] as? Int, 1)
        let cmds = cursorStopCommands(out)
        XCTAssertEqual(cmds.count, 1)
        XCTAssertTrue(cmds[0].contains("--sleep-if-idle 300"))
        XCTAssertTrue(cmds[0].contains(bin))
    }

    func testCursorInstallIntoBlankFileStartsFresh() {
        XCTAssertNotNil(
            HookInstaller.installCursorHook(into: Data(), binaryPath: bin, seconds: 300),
            "an empty file is 'absent', not a parse error")
        XCTAssertNotNil(
            HookInstaller.installCursorHook(into: Data("  \n".utf8), binaryPath: bin, seconds: 300))
    }

    func testCursorInstallIsIdempotentByteForByte() {
        let first = HookInstaller.installCursorHook(into: nil, binaryPath: bin, seconds: 300)
        XCTAssertNotNil(first)
        let second = HookInstaller.installCursorHook(into: first, binaryPath: bin, seconds: 300)
        XCTAssertEqual(first, second, "re-installing must not duplicate or reformat")
    }

    func testCursorReinstallWithNewSecondsReplacesInPlace() {
        let first = HookInstaller.installCursorHook(into: nil, binaryPath: bin, seconds: 300)
        let updated = HookInstaller.installCursorHook(into: first, binaryPath: bin, seconds: 600)!
        let cmds = cursorStopCommands(updated)
        XCTAssertEqual(cmds.count, 1, "no duplicate entry")
        XCTAssertTrue(cmds[0].contains("--sleep-if-idle 600"))
    }

    func testCursorInstallPreservesForeignKeysAndHooks() {
        let input = Data(
            """
            {"version":1,"hooks":{"stop":[{"command":"echo hi"}],"sessionEnd":[{"command":"audit.sh"}]}}
            """.utf8)
        let out = HookInstaller.installCursorHook(into: input, binaryPath: bin, seconds: 300)!
        let root = object(out)
        XCTAssertEqual(root["version"] as? Int, 1)
        let hooks = root["hooks"] as? [String: Any]
        XCTAssertNotNil(hooks?["sessionEnd"], "unrelated hook events preserved")
        let cmds = cursorStopCommands(out)
        XCTAssertTrue(cmds.contains("echo hi"), "foreign stop hook preserved")
        XCTAssertTrue(cmds.contains { $0.contains("--sleep-if-idle 300") }, "our hook added")
    }

    func testCursorUninstallRemovesOnlyOurs() {
        let input = Data(
            """
            {"version":1,"hooks":{"stop":[{"command":"echo hi"}]}}
            """.utf8)
        let installed = HookInstaller.installCursorHook(into: input, binaryPath: bin, seconds: 300)!
        let removed = HookInstaller.uninstallCursorHook(from: installed)
        let cmds = cursorStopCommands(removed!)
        XCTAssertEqual(cmds, ["echo hi"], "our hook gone, foreign hook intact")
        XCTAssertEqual(object(removed!)["version"] as? Int, 1, "version preserved")
    }

    func testCursorUninstallWhenAbsentReturnsInputUnchanged() {
        let input = Data(
            """
            {"version":1,"hooks":{"stop":[{"command":"echo hi"}]}}
            """.utf8)
        let out = HookInstaller.uninstallCursorHook(from: input)
        XCTAssertEqual(out, input, "no Decaffeinate hook present → bytes untouched")
    }

    func testCursorInstallUninstallRoundTripDropsHooksKey() {
        let input = Data(
            """
            {"permissions":{"allow":["Bash"]}}
            """.utf8)
        let installed = HookInstaller.installCursorHook(into: input, binaryPath: bin, seconds: 300)!
        let removed = HookInstaller.uninstallCursorHook(from: installed)!
        let root = object(removed)
        XCTAssertNil(root["hooks"], "the empty hooks/stop scaffold is pruned away")
        XCTAssertNotNil(root["permissions"], "unrelated keys survive the round-trip")
        XCTAssertEqual(root["version"] as? Int, 1)
    }

    func testCursorInstallRefusesPresentButMalformedFile() {
        let garbage = Data("{ not valid json, oops".utf8)
        XCTAssertNil(HookInstaller.installCursorHook(into: garbage, binaryPath: bin, seconds: 300))
        XCTAssertNil(
            HookInstaller.uninstallCursorHook(from: garbage),
            "never overwrite a file we can't parse")
    }

    // MARK: Undecodable settings (DC-1)

    /// A settings file that is not valid UTF-8 (UTF-16, or one stray Latin-1 byte)
    /// used to read as "blank" and was replaced by a file holding only our hook.
    /// It is present-but-unreadable: every editor must return nil ("left untouched").
    /// BOM-less UTF-16 of ASCII JSON is also valid UTF-8 (every other byte is NUL), and
    /// `JSONSerialization` auto-detects it, so it must be refused on the NUL bytes.
    private var undecodableFiles: [(name: String, data: Data)] {
        [
            (
                "UTF-16 with BOM",
                "{\"permissions\":{\"allow\":[\"Bash\"]}}".data(using: .utf16)!
            ),
            (
                "UTF-16 whitespace only",
                " \n ".data(using: .utf16)!
            ),
            (
                "UTF-16LE without BOM",
                "{\"permissions\":{\"allow\":[\"Bash\"]}}".data(using: .utf16LittleEndian)!
            ),
            (
                "UTF-16BE without BOM",
                "{\"permissions\":{\"allow\":[\"Bash\"]}}".data(using: .utf16BigEndian)!
            ),
            (
                "UTF-16LE without BOM, whitespace only",
                " \n ".data(using: .utf16LittleEndian)!
            ),
            (
                "stray Latin-1 byte",
                Data(
                    [UInt8]("{\"note\":\"caf".utf8) + [0xE9]
                        + [UInt8]("\",\"permissions\":{}}".utf8))
            ),
            ("lone invalid byte", Data([0xE9])),
        ]
    }

    func testClaudeEditorsRefuseUndecodableFile() {
        for file in undecodableFiles {
            XCTAssertNil(
                HookInstaller.installClaudeHook(into: file.data, binaryPath: bin, seconds: 300),
                "install must not overwrite: \(file.name)")
            XCTAssertNil(
                HookInstaller.uninstallClaudeHook(from: file.data),
                "uninstall must not overwrite: \(file.name)")
        }
    }

    func testCursorEditorsRefuseUndecodableFile() {
        for file in undecodableFiles {
            XCTAssertNil(
                HookInstaller.installCursorHook(into: file.data, binaryPath: bin, seconds: 300),
                "install must not overwrite: \(file.name)")
            XCTAssertNil(
                HookInstaller.uninstallCursorHook(from: file.data),
                "uninstall must not overwrite: \(file.name)")
        }
    }

    func testEmptyAndWhitespaceUTF8StillCountAsBlank() {
        for text in ["", "  \n\t "] {
            let data = Data(text.utf8)
            XCTAssertNotNil(
                HookInstaller.installClaudeHook(into: data, binaryPath: bin, seconds: 300))
            XCTAssertNotNil(
                HookInstaller.installCursorHook(into: data, binaryPath: bin, seconds: 300))
        }
    }

    func testCursorInstallRefusesUnexpectedStopShape() {
        let weird = Data("{\"hooks\":{\"stop\":\"oops\"}}".utf8)
        XCTAssertNil(HookInstaller.installCursorHook(into: weird, binaryPath: bin, seconds: 300))
        let weird2 = Data("{\"hooks\":\"nope\"}".utf8)
        XCTAssertNil(HookInstaller.installCursorHook(into: weird2, binaryPath: bin, seconds: 300))
    }
}

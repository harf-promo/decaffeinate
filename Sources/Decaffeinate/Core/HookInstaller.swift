import Foundation

/// Writes (and cleanly removes) a turn-end "let this Mac sleep once you're also
/// away" hook into an agent's config — Claude Code's `~/.claude/settings.json`
/// Stop hook and Codex's `~/.codex/config.toml` `notify` key. The installed
/// command is `Decaffeinate --sleep-if-idle <seconds>`, so the gating lives in
/// Decaffeinate, not a shell wrapper.
///
/// Every editor is a **pure** `Data`/`String` transform so the whole merge/remove
/// logic is unit-testable without touching disk; only path resolution and the
/// atomic write are impure.
enum HookInstaller {

    enum Client: String, CaseIterable {
        case claude
        case codex
    }

    enum HookError: Error, Equatable {
        /// The user already set a `notify` key we didn't write — never clobber it.
        case wouldClobberExistingNotify
    }

    static let defaultIdleSeconds = 300

    // MARK: - Paths & identity (impure)

    /// The installed executable to embed in the hook, e.g.
    /// `/Applications/Decaffeinate.app/Contents/MacOS/Decaffeinate`.
    static func binaryPath() -> String {
        Bundle.main.executablePath ?? CommandLine.arguments.first ?? "Decaffeinate"
    }

    static func claudeSettingsURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".claude/settings.json")
    }

    static func codexConfigURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".codex/config.toml")
    }

    /// `mkdir -p` the parent, then an atomic write (the codebase's first). Atomic so
    /// a crash mid-write can never leave a half-written settings file.
    static func atomicWrite(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
    }

    // MARK: - Claude Code (~/.claude/settings.json, JSON)

    /// The Stop-hook command we manage. JSON has no comments, so our identity is
    /// the command itself: it contains both `--sleep-if-idle` and `Decaffeinate`.
    static func claudeHookCommand(binaryPath: String, seconds: Int) -> String {
        "\(binaryPath) --sleep-if-idle \(seconds)"
    }

    /// Path-tolerant so a moved `.app` is still recognized on uninstall/re-install.
    static func isDecaffeinateClaudeCommand(_ command: String) -> Bool {
        command.contains("--sleep-if-idle") && command.contains("Decaffeinate")
    }

    /// Add/refresh our Stop hook, preserving every other key, matcher, and hook.
    /// A nil or blank input starts from a fresh object. Returns **nil** — refusing
    /// to write — when the input is present but not valid JSON, or when the shape
    /// we'd edit (`hooks` / `hooks.Stop`) isn't what we expect, so a hand-edit typo
    /// can never make us clobber the user's whole settings file. Idempotent:
    /// re-installing replaces our prior entry rather than duplicating it.
    static func installClaudeHook(into json: Data?, binaryPath: String, seconds: Int) -> Data? {
        var root: [String: Any] = [:]
        if let json, !isBlank(json) {
            guard let parsed = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
            else { return nil }  // present but unparseable → never clobber
            root = parsed
        }
        // Refuse on unexpected shapes rather than silently dropping user data.
        var hooks: [String: Any] = [:]
        if let existing = root["hooks"] {
            guard let dict = existing as? [String: Any] else { return nil }
            hooks = dict
        }
        var stop: [[String: Any]] = []
        if let existing = hooks["Stop"] {
            guard let array = existing as? [[String: Any]] else { return nil }
            stop = array
        }

        stop = stop.filter { group in
            let entries = group["hooks"] as? [[String: Any]] ?? []
            return !entries.contains { isDecaffeinateClaudeCommand($0["command"] as? String ?? "") }
        }
        stop.append([
            "hooks": [
                [
                    "type": "command",
                    "command": claudeHookCommand(binaryPath: binaryPath, seconds: seconds),
                ]
            ]
        ])
        hooks["Stop"] = stop
        root["hooks"] = hooks
        return serialize(root)
    }

    private static func isBlank(_ data: Data) -> Bool {
        (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Remove only our Stop hook, pruning emptied groups/keys and leaving all
    /// foreign keys and matchers intact. Returns nil if the file can't be parsed —
    /// we never overwrite a settings file we can't read. Returns the input
    /// unchanged when our hook isn't present.
    static func uninstallClaudeHook(from json: Data) -> Data? {
        guard var root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            return nil
        }
        guard var hooks = root["hooks"] as? [String: Any],
            var stop = hooks["Stop"] as? [[String: Any]]
        else { return json }

        // If none of our hooks are present, return the input BYTES unchanged so the
        // caller can tell "nothing removed" from "removed + reformatted".
        let hasOurs = stop.contains { group in
            (group["hooks"] as? [[String: Any]] ?? []).contains {
                isDecaffeinateClaudeCommand($0["command"] as? String ?? "")
            }
        }
        guard hasOurs else { return json }

        stop = stop.compactMap { group -> [String: Any]? in
            var group = group
            guard var entries = group["hooks"] as? [[String: Any]] else { return group }
            entries = entries.filter {
                !isDecaffeinateClaudeCommand($0["command"] as? String ?? "")
            }
            if entries.isEmpty { return nil }
            group["hooks"] = entries
            return group
        }
        if stop.isEmpty { hooks.removeValue(forKey: "Stop") } else { hooks["Stop"] = stop }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        return serialize(root)
    }

    private static func serialize(_ object: [String: Any]) -> Data {
        let data =
            (try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return data + Data("\n".utf8)
    }

    // MARK: - Codex (~/.codex/config.toml, `notify` root key)

    static let codexMarker = "# decaffeinate-managed"

    static func codexNotifyLine(binaryPath: String, seconds: Int) -> String {
        "notify = [\"\(tomlEscape(binaryPath))\", \"--sleep-if-idle\", \"\(seconds)\"] \(codexMarker)"
    }

    private static func tomlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Set our `notify` line in the file's root region (before any `[table]`, as
    /// TOML requires). Refuses to overwrite a pre-existing `notify` we didn't write.
    /// Idempotent: an existing marked line is replaced in place. Line-oriented on
    /// purpose (no TOML dependency).
    static func installCodexNotify(into toml: String, binaryPath: String, seconds: Int) -> Result<
        String, HookError
    > {
        var lines = toml.components(separatedBy: "\n")
        let rootEnd = firstTableHeaderIndex(lines)
        let line = codexNotifyLine(binaryPath: binaryPath, seconds: seconds)

        for i in 0..<rootEnd where isNotifyLine(lines[i]) {
            guard lines[i].contains(codexMarker) else {
                return .failure(.wouldClobberExistingNotify)
            }
            lines[i] = line
            return .success(lines.joined(separator: "\n"))
        }
        // No notify line yet — insert at the very top (always inside the root region).
        lines.insert(line, at: 0)
        return .success(lines.joined(separator: "\n"))
    }

    /// Remove only our marked `notify` line; leave an unmarked user `notify` alone.
    static func uninstallCodexNotify(from toml: String) -> String {
        var lines = toml.components(separatedBy: "\n")
        let rootEnd = firstTableHeaderIndex(lines)
        let removed = lines.enumerated().filter { index, line in
            index < rootEnd && isNotifyLine(line) && line.contains(codexMarker)
        }.map(\.offset)
        for index in removed.reversed() { lines.remove(at: index) }
        return lines.joined(separator: "\n")
    }

    private static func isNotifyLine(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("notify") else { return false }
        let afterKey = trimmed.dropFirst("notify".count).drop(while: { $0 == " " || $0 == "\t" })
        return afterKey.hasPrefix("=")
    }

    /// The index of the first `[table]` / `[[array]]` header, or `count` if none —
    /// i.e. the exclusive end of the root-key region. Skips `[`-leading lines that
    /// are array elements (`[1, 2],`) or sit inside a `"""`/`'''` multi-line
    /// string, so a genuine root `notify` after such a line is still found (and the
    /// clobber-refusal still fires). Not a full TOML parser; a single-element
    /// numeric sub-array on its own line is the lone residual ambiguity.
    private static func firstTableHeaderIndex(_ lines: [String]) -> Int {
        var inString = false
        var delimiter = ""
        for (index, line) in lines.enumerated() {
            if inString {
                if line.contains(delimiter) { inString = false }
                continue
            }
            let trimmed = String(line.drop(while: { $0 == " " || $0 == "\t" }))
            if looksLikeTableHeader(trimmed) { return index }
            // Enter a multi-line string when this line has an odd number of a
            // triple-quote delimiter (opens but doesn't close it).
            for d in ["\"\"\"", "'''"] where (line.components(separatedBy: d).count - 1) % 2 == 1 {
                inString = true
                delimiter = d
                break
            }
        }
        return lines.count
    }

    /// A TOML table header: `[key]` / `[[key]]` whose bracketed content is a bare/
    /// dotted/quoted key — not an array element like `[1, 2]` (comma) or `[a = 1]`.
    private static func looksLikeTableHeader(_ trimmed: String) -> Bool {
        guard trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") else { return false }
        let inner = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            .trimmingCharacters(in: CharacterSet(charactersIn: "[] \t"))
        return !inner.isEmpty && !inner.contains(",") && !inner.contains("=")
    }
}

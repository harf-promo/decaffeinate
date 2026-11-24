import Foundation

/// Writes (and cleanly removes) a turn-end "let this Mac sleep once you're also
/// away" hook into an agent's config — Claude Code's `~/.claude/settings.json`
/// Stop hook, Codex's `~/.codex/config.toml` `notify` key, and Cursor's
/// user-level `~/.cursor/hooks.json` `stop` hook. The installed command is
/// `Decaffeinate --sleep-if-idle <seconds>`, so the gating lives in
/// Decaffeinate, not a shell wrapper.
///
/// Every editor is a **pure** `Data`/`String` transform so the whole merge/remove
/// logic is unit-testable without touching disk; only path resolution and the
/// atomic write are impure.
enum HookInstaller {

    enum Client: String, CaseIterable {
        case claude
        case codex
        case cursor
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
        canonicalBinaryPath(
            Bundle.main.executablePath ?? CommandLine.arguments.first ?? "Decaffeinate")
    }

    /// Resolves symlinks in an absolute executable path, so a binary launched
    /// through a link with another name is embedded by its real name (and
    /// recognized as ours on the next install or uninstall). A relative or bare
    /// name is returned unchanged.
    static func canonicalBinaryPath(_ raw: String) -> String {
        guard raw.hasPrefix("/") else { return raw }
        return URL(fileURLWithPath: raw).resolvingSymlinksInPath().path
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

    /// User-level only — never a project `.cursor/hooks.json`.
    static func cursorHooksURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".cursor/hooks.json")
    }

    /// Follows `url` through any symlinks to the file that actually holds the content
    /// (dotfiles repos and managed installs link `~/.claude/settings.json` elsewhere).
    /// Relative links resolve against the link's own directory. A dangling link resolves
    /// to its (not yet existing) target; a loop throws.
    static func resolvedDestination(of url: URL) throws -> URL {
        let fm = FileManager.default
        var current = url
        for _ in 0..<32 {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: current.path) else {
                return current
            }
            current =
                target.hasPrefix("/")
                ? URL(fileURLWithPath: target)
                : current.deletingLastPathComponent().appendingPathComponent(target)
        }
        throw CocoaError(
            .fileWriteUnknown,
            userInfo: [NSFilePathErrorKey: url.path, NSLocalizedDescriptionKey: "symlink loop"])
    }

    /// `mkdir -p` the parent, then an atomic write (temp file in the same directory,
    /// then `rename`) so a crash mid-write can never leave a half-written settings file.
    /// A symlinked destination is written *through*: the link stays a link and its
    /// target is replaced. The target's permission bits carry over, and the temp file
    /// is created with them from the start so a 0600 file is never briefly 0644.
    static func atomicWrite(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let destination = try resolvedDestination(of: url)
        let directory = destination.deletingLastPathComponent()
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let existing = try? fm.attributesOfItem(atPath: destination.path)
        let mode = (existing?[.posixPermissions] as? NSNumber).map { mode_t($0.uint16Value) }
        let temp = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).decaffeinate-\(UUID().uuidString).tmp")

        let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, mode ?? 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            if let mode { _ = fchmod(fd, mode) }  // beat the umask: keep the exact bits
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                var offset = 0
                while offset < raw.count {
                    let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                    if written < 0 {
                        if errno == EINTR { continue }
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    offset += written
                }
            }
            _ = fsync(fd)
            close(fd)
            guard rename(temp.path, destination.path) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }

    // MARK: - Claude Code (~/.claude/settings.json, JSON)

    /// The Stop-hook command we manage. JSON has no comments, so our identity is
    /// the command itself (see `isDecaffeinateHookCommand`).
    static func claudeHookCommand(binaryPath: String, seconds: Int) -> String {
        "\(shellQuote(binaryPath)) --sleep-if-idle \(seconds)"
    }

    /// POSIX-shell quoting: bare when only safe characters, otherwise single-quoted
    /// with embedded `'` written as `'\''`.
    static func shellQuote(_ s: String) -> String {
        let safe = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./_-"
        )
        if !s.isEmpty, s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Path-tolerant so a moved `.app` is still recognized on uninstall/re-install.
    /// Shared identity for Claude and Cursor: the command's executable (its first
    /// shell word) is a file named `Decaffeinate`, its next word is the
    /// `--sleep-if-idle` verb, and at most one argument (the seconds) follows.
    /// A user's own wrapper that merely mentions both strings is not ours.
    ///
    /// Before v1.26 the path was written unquoted, so a path with spaces splits
    /// into several words; that legacy shape is still ours when the words before
    /// the verb rejoin into an absolute `….app/Contents/MacOS/Decaffeinate` path.
    static func isDecaffeinateHookCommand(_ command: String) -> Bool {
        guard let words = shellWords(command),
            let verb = words.firstIndex(of: "--sleep-if-idle"), verb >= 1,
            words.count - verb <= 2
        else { return false }
        if verb == 1 {
            return (words[0] as NSString).lastPathComponent == "Decaffeinate"
        }
        let joined = words[0..<verb].joined(separator: " ")
        return joined.hasPrefix("/") && joined.hasSuffix(".app/Contents/MacOS/Decaffeinate")
    }

    /// Splits `command` into words the way a POSIX shell would for the simple
    /// commands we write: whitespace separates words; single quotes, double
    /// quotes and backslashes quote. Returns nil on an unterminated quote.
    static func shellWords(_ command: String) -> [String]? {
        var words: [String] = []
        var current = ""
        var inWord = false
        var iterator = command.makeIterator()
        while let c = iterator.next() {
            switch c {
            case " ", "\t", "\n":
                if inWord { words.append(current) }
                current = ""
                inWord = false
            case "'":
                inWord = true
                var closed = false
                while let q = iterator.next() {
                    if q == "'" {
                        closed = true
                        break
                    }
                    current.append(q)
                }
                if !closed { return nil }
            case "\"":
                inWord = true
                var closed = false
                while let q = iterator.next() {
                    if q == "\"" {
                        closed = true
                        break
                    }
                    if q == "\\" {
                        guard let next = iterator.next() else { return nil }
                        if !"$`\"\\\n".contains(next) { current.append(q) }
                        current.append(next)
                        continue
                    }
                    current.append(q)
                }
                if !closed { return nil }
            case "\\":
                inWord = true
                guard let next = iterator.next() else { return nil }
                current.append(next)
            default:
                inWord = true
                current.append(c)
            }
        }
        if inWord { words.append(current) }
        return words
    }

    static func isDecaffeinateClaudeCommand(_ command: String) -> Bool {
        isDecaffeinateHookCommand(command)
    }

    /// Add/refresh our Stop hook, preserving every other key, matcher, and hook.
    /// A nil or blank input starts from a fresh object. Returns **nil** — refusing
    /// to write — when the input is present but not valid JSON, or when the shape
    /// we'd edit (`hooks` / `hooks.Stop`) isn't what we expect, so a hand-edit typo
    /// can never make us clobber the user's whole settings file. Idempotent:
    /// re-installing replaces our prior entry rather than duplicating it. The edit is
    /// spliced into the original text (see `JSONTextEditor`), so the rest of the file
    /// keeps its exact bytes: key order, indentation and number formatting.
    static func installClaudeHook(into json: Data?, binaryPath: String, seconds: Int) -> Data? {
        let entry = JSONNode.object([
            (
                "hooks",
                .array([
                    .object([
                        ("type", .string("command")),
                        (
                            "command",
                            .string(claudeHookCommand(binaryPath: binaryPath, seconds: seconds))
                        ),
                    ])
                ])
            )
        ])
        guard let json, !isBlank(json) else {
            return JSONTextEditor.render(
                root: .object([("hooks", .object([("Stop", .array([entry]))]))]))
        }
        guard let root = parseObject(json) else { return nil }  // unparseable → never clobber
        // Refuse on unexpected shapes rather than silently dropping user data.
        let hooks: [String: Any]?
        if let existing = root["hooks"] {
            guard let dict = existing as? [String: Any] else { return nil }
            hooks = dict
        } else {
            hooks = nil
        }
        if let existing = hooks?["Stop"], !(existing is [[String: Any]]) { return nil }

        var editor = JSONTextEditor(json)
        guard removeOurHooks(from: &editor, event: "Stop", grouped: true) != nil else {
            return nil
        }
        let placed: Bool
        if hooks == nil {
            placed = editor.insertMember(
                into: [], key: "hooks", value: .object([("Stop", .array([entry]))]))
        } else if hooks?["Stop"] == nil {
            placed = editor.insertMember(
                into: [.key("hooks")], key: "Stop", value: .array([entry]))
        } else {
            placed = editor.appendElement(to: [.key("hooks"), .key("Stop")], value: entry)
        }
        return placed ? editor.data : nil
    }

    /// True only for a file that decodes as UTF-8 and holds nothing but whitespace.
    /// Data that does not decode (UTF-16, or a stray Latin-1 byte) is present but
    /// unreadable, never blank: treating it as blank would replace the user's whole
    /// settings file with a fresh one holding only our hook.
    private static func isBlank(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Parse a settings file, or nil when it is not a UTF-8 JSON object. The text
    /// editor splices raw UTF-8 bytes, so a UTF-16 file (which `JSONSerialization`
    /// would accept) is refused here as well, keeping the "left untouched" branch.
    /// UTF-16 without a BOM holding ASCII JSON is itself valid UTF-8 (every other byte
    /// is NUL) and `JSONSerialization` auto-detects it, so a NUL byte is refused too:
    /// JSON text never contains a raw NUL.
    private static func parseObject(_ data: Data) -> [String: Any]? {
        guard String(data: data, encoding: .utf8) != nil, !data.contains(0) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Delete our hook entries (and any group or key they leave empty, when `prune`)
    /// from `editor`'s text. `grouped` is Claude's `{ matcher, hooks: [..] }` groups;
    /// otherwise the entries sit directly in the event array (Cursor). Returns how many
    /// entries were removed, or nil when the text could not be edited.
    private static func removeOurHooks(
        from editor: inout JSONTextEditor, event: String, grouped: Bool, prune: Bool = false
    ) -> Int? {
        var removed = 0
        while let root = parseObject(editor.data),
            let hooks = root["hooks"] as? [String: Any],
            let list = hooks[event] as? [[String: Any]]
        {
            let base: [JSONTextEditor.Step] = [.key("hooks"), .key(event)]
            var target: [JSONTextEditor.Step]?
            for (g, item) in list.enumerated() {
                if grouped {
                    let entries = item["hooks"] as? [[String: Any]] ?? []
                    guard
                        let e = entries.firstIndex(where: {
                            isDecaffeinateClaudeCommand($0["command"] as? String ?? "")
                        })
                    else { continue }
                    target =
                        entries.count == 1
                        ? base + [.index(g)] : base + [.index(g), .key("hooks"), .index(e)]
                } else if isDecaffeinateHookCommand(item["command"] as? String ?? "") {
                    target = base + [.index(g)]
                }
                if target != nil { break }
            }
            guard let target else { break }
            guard editor.delete(target) else { return nil }
            removed += 1
        }
        guard removed > 0, prune else { return removed }
        // Same pruning as before the text-level editor: drop the scaffold we emptied.
        if let root = parseObject(editor.data), let hooks = root["hooks"] as? [String: Any] {
            if (hooks[event] as? [Any])?.isEmpty == true {
                guard editor.delete([.key("hooks"), .key(event)]) else { return nil }
            }
        }
        if let root = parseObject(editor.data), let hooks = root["hooks"] as? [String: Any],
            hooks.isEmpty
        {
            guard editor.delete([.key("hooks")]) else { return nil }
        }
        return removed
    }

    /// Remove only our Stop hook, pruning emptied groups/keys and leaving all
    /// foreign keys and matchers intact. Returns nil if the file can't be parsed —
    /// we never overwrite a settings file we can't read. Returns the input
    /// unchanged when our hook isn't present.
    static func uninstallClaudeHook(from json: Data) -> Data? {
        guard let root = parseObject(json) else { return nil }
        guard let hooks = root["hooks"] as? [String: Any],
            hooks["Stop"] is [[String: Any]]
        else { return json }

        var editor = JSONTextEditor(json)
        guard let removed = removeOurHooks(from: &editor, event: "Stop", grouped: true, prune: true)
        else { return nil }
        // If none of our hooks are present, return the input BYTES unchanged so the
        // caller can tell "nothing removed" from "removed".
        return removed == 0 ? json : editor.data
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

    // MARK: - Cursor (~/.cursor/hooks.json, user-level only)

    static func cursorHookCommand(binaryPath: String, seconds: Int) -> String {
        "\(shellQuote(binaryPath)) --sleep-if-idle \(seconds)"
    }

    /// Add/refresh our `stop` hook, preserving every other key and hook.
    /// Shape: `{ "version": 1, "hooks": { "stop": [{ "command": "<bin> --sleep-if-idle N" }] } }`.
    /// A nil or blank input starts from a fresh object (`version: 1`). Returns
    /// **nil** — refusing to write — when the input is present but not valid
    /// JSON, or when `hooks` / `hooks.stop` isn't the expected shape. Idempotent:
    /// re-installing replaces our prior entry rather than duplicating it. Edited as
    /// text, like the Claude file, so the user's formatting survives.
    static func installCursorHook(into json: Data?, binaryPath: String, seconds: Int) -> Data? {
        let entry = JSONNode.object([
            ("command", .string(cursorHookCommand(binaryPath: binaryPath, seconds: seconds)))
        ])
        guard let json, !isBlank(json) else {
            return JSONTextEditor.render(
                root: .object([
                    ("version", .int(1)), ("hooks", .object([("stop", .array([entry]))])),
                ]))
        }
        guard let root = parseObject(json) else { return nil }  // unparseable → never clobber
        let hooks: [String: Any]?
        if let existing = root["hooks"] {
            guard let dict = existing as? [String: Any] else { return nil }
            hooks = dict
        } else {
            hooks = nil
        }
        if let existing = hooks?["stop"], !(existing is [[String: Any]]) { return nil }

        var editor = JSONTextEditor(json)
        guard removeOurHooks(from: &editor, event: "stop", grouped: false) != nil else {
            return nil
        }
        if root["version"] == nil, !editor.insertMember(into: [], key: "version", value: .int(1)) {
            return nil
        }
        let placed: Bool
        if hooks == nil {
            placed = editor.insertMember(
                into: [], key: "hooks", value: .object([("stop", .array([entry]))]))
        } else if hooks?["stop"] == nil {
            placed = editor.insertMember(
                into: [.key("hooks")], key: "stop", value: .array([entry]))
        } else {
            placed = editor.appendElement(to: [.key("hooks"), .key("stop")], value: entry)
        }
        return placed ? editor.data : nil
    }

    /// Remove only our `stop` hook, pruning emptied groups/keys and leaving all
    /// foreign keys intact. Returns nil if the file can't be parsed. Returns the
    /// input unchanged when our hook isn't present.
    static func uninstallCursorHook(from json: Data) -> Data? {
        guard let root = parseObject(json) else { return nil }
        guard let hooks = root["hooks"] as? [String: Any],
            hooks["stop"] is [[String: Any]]
        else { return json }

        var editor = JSONTextEditor(json)
        guard
            let removed = removeOurHooks(from: &editor, event: "stop", grouped: false, prune: true)
        else { return nil }
        return removed == 0 ? json : editor.data
    }
}

import Foundation

/// Reads the app's own source as text so the conformance gates can assert on it.
///
/// The Harf design system is a set of rules about values that appear *in source*
/// — a radius literal, a duration, a font size, a `style: .continuous`. Those
/// rules cannot be checked by running the app, so they are checked by reading it.
///
/// The repo root is derived from `#filePath`, which the compiler resolves to this
/// file's absolute path on the machine that built the test bundle — the same
/// machine that runs it. That keeps the scanner working under `swift test` with
/// no bundled resources and no environment variables.
enum SourceScanner {

    /// `<repo>/Sources/Decaffeinate` — the only tree the gates govern.
    /// `Tests/DecaffeinateTests/SourceScanner.swift` → up three → repo root.
    static let sourcesRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // DecaffeinateTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // <repo>
            .appendingPathComponent("Sources/Decaffeinate")
    }()

    /// One Swift file, already read, with a stable name for failure messages.
    struct SourceFile {
        /// Path relative to `Sources/Decaffeinate`, e.g. `Views/MenuRedesign.swift`.
        let relativePath: String
        let lines: [String]

        var name: String { (relativePath as NSString).lastPathComponent }

        /// `Views/MenuRedesign.swift:423` — clickable in a terminal.
        func anchor(_ oneBasedLine: Int) -> String { "\(relativePath):\(oneBasedLine)" }
    }

    /// Every `.swift` file under `Sources/Decaffeinate`, sorted for stable output.
    static func allFiles() throws -> [SourceFile] { try files(under: "") }

    /// Every `.swift` file under `Sources/Decaffeinate/<subpath>` (`""` = all).
    static func files(under subpath: String) throws -> [SourceFile] {
        let root = subpath.isEmpty ? sourcesRoot : sourcesRoot.appendingPathComponent(subpath)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw ScannerError.unreadableTree(root.path)
        }
        var found: [SourceFile] = []
        for case let entry as String in walker where entry.hasSuffix(".swift") {
            let url = root.appendingPathComponent(entry)
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = subpath.isEmpty ? entry : "\(subpath)/\(entry)"
            let lines = text.components(separatedBy: "\n")
            found.append(SourceFile(relativePath: relative, lines: lines))
        }
        return found.sorted { $0.relativePath < $1.relativePath }
    }

    /// A single rule hit: where it is, and the line that tripped it.
    struct Hit {
        let anchor: String
        let line: String

        var report: String { "\(anchor)  \(line.trimmingCharacters(in: .whitespaces))" }
    }

    /// Every line under `subpath` matching `predicate`, skipping comment-only lines.
    ///
    /// Comments are skipped because the gates govern what the app *renders*, not
    /// what its documentation discusses — several files legitimately name a banned
    /// value while explaining why it is banned.
    static func scan(
        under subpath: String,
        skippingFiles skipped: Set<String> = [],
        matching predicate: (String) -> Bool
    ) throws -> [Hit] {
        var hits: [Hit] = []
        for file in try files(under: subpath) where !skipped.contains(file.name) {
            for (index, line) in file.lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") || trimmed.hasPrefix("*") {
                    continue
                }
                if predicate(line) { hits.append(Hit(anchor: file.anchor(index + 1), line: line)) }
            }
        }
        return hits
    }

    /// Every *number* in `line` that is a real literal rather than part of an
    /// identifier — `12`, `0.15`, `1.5`. `s1`, `paper2` and `green900` are names,
    /// not numbers, so their digits are skipped.
    ///
    /// The whole line is scanned, not just a leading argument: the app's compact
    /// button writes its size as `compact ? 12 : 14`, so a gate that read only
    /// the first token would score that illegal 14 as compliant.
    static func numberLiterals(in line: String) -> [Double] {
        var found: [Double] = []
        var index = line.startIndex
        var previous: Character?
        while index < line.endIndex {
            guard line[index].isNumber else {
                previous = line[index]
                index = line.index(after: index)
                continue
            }
            // Digits glued to an identifier belong to it: `s1`, `paper2`.
            let attached = previous.map { $0.isLetter || $0 == "_" } ?? false
            var token = ""
            var seenPoint = false
            var scan = index
            while scan < line.endIndex {
                let character = line[scan]
                if character.isNumber {
                    token.append(character)
                    scan = line.index(after: scan)
                    continue
                }
                // A single decimal point, and only with a digit behind it, so
                // `0.15` stays one number and `view.frame` ends the token.
                let next = line.index(after: scan)
                let followedByDigit = next < line.endIndex && line[next].isNumber
                guard character == ".", !seenPoint, followedByDigit else { break }
                seenPoint = true
                token.append(character)
                scan = next
            }
            if !attached, let value = Double(token) { found.append(value) }
            previous = line[line.index(before: scan)]
            index = scan
        }
        return found
    }

    /// Every whole number in `line`, for the gates that speak in points.
    static func integerLiterals(in line: String) -> [Int] {
        numberLiterals(in: line).filter { $0 == $0.rounded() }.map { Int($0) }
    }

    // MARK: - Localization keys

    /// One `L10n.localized("…")` call whose key is a plain literal.
    struct LocalizedKey: Hashable {
        let key: String
        let anchor: String
    }

    /// Every literal key passed to `L10n.localized(…)` anywhere in the app.
    ///
    /// Two details make this trustworthy rather than a grep:
    ///
    /// * **Adjacent literals are joined.** Several long strings are written as
    ///   `"one " + "two"` to stay inside the line limit; the key Swift actually
    ///   looks up is the concatenation, so a per-literal scan would report three
    ///   phantom missing keys that are really one present one.
    /// * **Computed keys are skipped.** `L10n.localized(policy?.shortLabel ?? "")`
    ///   has no literal key to check, and reading its `""` fallback as a key would
    ///   report an empty string as permanently missing from the table.
    static func localizedKeys() throws -> [LocalizedKey] {
        var found: [LocalizedKey] = []
        for file in try allFiles() {
            let text = file.lines.joined(separator: "\n")
            var cursor = text.startIndex
            while let call = text.range(of: "L10n.localized(", range: cursor..<text.endIndex) {
                cursor = call.upperBound
                guard let key = literalArgument(in: text, from: call.upperBound) else { continue }
                let preceding = text[text.startIndex..<call.lowerBound]
                let line = preceding.filter { $0 == "\n" }.count + 1
                found.append(LocalizedKey(key: key, anchor: file.anchor(line)))
            }
        }
        return found
    }

    /// The first argument at `start`, if it is built only from string literals.
    /// Returns nil for a computed key, or for a call with no literal at all.
    private static func literalArgument(in text: String, from start: String.Index) -> String? {
        var index = start
        var depth = 1
        var literal = ""
        var sawLiteral = false
        var sawIdentifier = false
        while index < text.endIndex, depth > 0 {
            let character = text[index]
            if character == "\"" {
                index = text.index(after: index)
                while index < text.endIndex, text[index] != "\"" {
                    if text[index] == "\\" {
                        literal.append(text[index])
                        index = text.index(after: index)
                        if index == text.endIndex { break }
                    }
                    literal.append(text[index])
                    index = text.index(after: index)
                }
                sawLiteral = true
                if index < text.endIndex { index = text.index(after: index) }
                continue
            }
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            // A top-level comma ends the key argument; the rest are format values.
            if character == ",", depth == 1 { break }
            if character.isLetter { sawIdentifier = true }
            index = text.index(after: index)
        }
        guard sawLiteral, !sawIdentifier else { return nil }
        return unescape(literal)
    }

    /// Resolves the escapes Swift source uses into the characters a `.strings`
    /// table stores literally — the two sides of the compiler must agree, or every
    /// curly apostrophe in the app reads as a missing key.
    static func unescape(_ source: String) -> String {
        var output = ""
        var index = source.startIndex
        while index < source.endIndex {
            guard source[index] == "\\", source.index(after: index) < source.endIndex else {
                output.append(source[index])
                index = source.index(after: index)
                continue
            }
            let escape = source[source.index(after: index)]
            var next = source.index(index, offsetBy: 2)
            switch escape {
            case "u":
                guard next < source.endIndex, source[next] == "{",
                    let close = source[next...].firstIndex(of: "}"),
                    let value = UInt32(source[source.index(after: next)..<close], radix: 16),
                    let unicode = Unicode.Scalar(value)
                else {
                    output.append(escape)
                    break
                }
                output.append(Character(unicode))
                next = source.index(after: close)
            case "n": output.append("\n")
            case "t": output.append("\t")
            default: output.append(escape)
            }
            index = next
        }
        return output
    }

    enum ScannerError: Error, CustomStringConvertible {
        case unreadableTree(String)

        var description: String {
            switch self {
            case .unreadableTree(let path): return "SourceScanner could not read \(path)"
            }
        }
    }
}

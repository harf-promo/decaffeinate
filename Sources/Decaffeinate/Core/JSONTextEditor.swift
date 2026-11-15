import Foundation

/// A new JSON value to splice into a document. Only what the hook installer
/// writes: strings, integers, objects and arrays.
indirect enum JSONNode {
    case string(String)
    case int(Int)
    case object([(key: String, value: JSONNode)])
    case array([JSONNode])
}

/// A minimal, byte-preserving editor for JSON *text*.
///
/// `JSONSerialization` cannot round-trip a hand-written settings file: it re-sorts
/// every key, rewrites numbers (`0.1` becomes `0.10000000000000001`) and drops the
/// user's layout. The hook installer edits other tools' config files, so it splices
/// into the original bytes instead: only the members and elements it adds or removes
/// change; everything else stays exactly as the user wrote it.
///
/// It is **not** a validator. Callers parse the input with `JSONSerialization` first;
/// every method here returns `false` / `nil` on anything it cannot place, so an
/// unexpected document is refused rather than guessed at.
struct JSONTextEditor {

    enum Step: Equatable {
        case key(String)
        case index(Int)
    }

    private(set) var bytes: [UInt8]

    init(_ data: Data) { bytes = [UInt8](data) }

    var data: Data { Data(bytes) }

    // MARK: Rendering new values

    /// A fresh document: `node` as the root, ending in a newline.
    static func render(root node: JSONNode) -> Data {
        Data((render(node, base: "", unit: "  ", multiline: true) + "\n").utf8)
    }

    private static func quoted(_ string: String) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: string, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return data.map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
    }

    private static func render(_ node: JSONNode, base: String, unit: String, multiline: Bool)
        -> String
    {
        let inner = base + unit
        switch node {
        case .string(let s): return quoted(s)
        case .int(let n): return String(n)
        case .object(let members):
            if members.isEmpty { return "{}" }
            let parts = members.map {
                "\(quoted($0.key)): \(render($0.value, base: inner, unit: unit, multiline: multiline))"
            }
            return multiline
                ? "{\n" + parts.map { inner + $0 }.joined(separator: ",\n") + "\n" + base + "}"
                : "{" + parts.joined(separator: ", ") + "}"
        case .array(let elements):
            if elements.isEmpty { return "[]" }
            let parts = elements.map { render($0, base: inner, unit: unit, multiline: multiline) }
            return multiline
                ? "[\n" + parts.map { inner + $0 }.joined(separator: ",\n") + "\n" + base + "]"
                : "[" + parts.joined(separator: ", ") + "]"
        }
    }

    // MARK: Edits

    /// Adds `"key": value` as the last member of the object at `path` (`[]` = root).
    mutating func insertMember(into path: [Step], key: String, value: JSONNode) -> Bool {
        guard let container = span(of: path), let items = members(of: container) else {
            return false
        }
        return insert(
            into: container, items: items.map { ($0.keyStart, $0.value.end) },
            open: "{", close: "}"
        ) { layout in
            "\(Self.quoted(key)): "
                + Self.render(
                    value, base: layout.base, unit: layout.unit, multiline: layout.multiline)
        }
    }

    /// Adds `value` as the last element of the array at `path`.
    mutating func appendElement(to path: [Step], value: JSONNode) -> Bool {
        guard let container = span(of: path), let items = elements(of: container) else {
            return false
        }
        return insert(
            into: container, items: items.map { ($0.start, $0.end) }, open: "[", close: "]"
        ) { layout in
            Self.render(value, base: layout.base, unit: layout.unit, multiline: layout.multiline)
        }
    }

    /// Removes the object member or array element at `path`, with its separator.
    mutating func delete(_ path: [Step]) -> Bool {
        guard let last = path.last, let container = span(of: Array(path.dropLast())) else {
            return false
        }
        let items: [(start: Int, end: Int)]
        let position: Int
        switch last {
        case .key(let key):
            guard let found = members(of: container),
                let at = uniqueIndex(of: key, in: found)
            else { return false }
            items = found.map { ($0.keyStart, $0.value.end) }
            position = at
        case .index(let i):
            guard let found = elements(of: container), found.indices.contains(i) else {
                return false
            }
            items = found.map { ($0.start, $0.end) }
            position = i
        }
        let range: Range<Int>
        if items.count == 1 {
            range = (container.start + 1)..<(container.end - 1)
        } else if position == items.count - 1 {
            range = items[position - 1].end..<items[position].end
        } else {
            range = items[position].start..<items[position + 1].start
        }
        bytes.removeSubrange(range)
        return true
    }

    // MARK: Layout for inserted text

    private struct Layout {
        let base: String
        let unit: String
        let multiline: Bool
    }

    private static let newline = UInt8(ascii: "\n")

    private mutating func insert(
        into container: Span, items: [(start: Int, end: Int)], open: String, close: String,
        render: (Layout) -> String
    ) -> Bool {
        let unit = detectedIndentUnit()
        if let last = items.last {
            // Mirror the gap in front of the last item; with one item, borrow its gap
            // to the opening bracket and add the comma.
            let previousEnd = items.count >= 2 ? items[items.count - 2].end : container.start + 1
            let gap = Array(bytes[previousEnd..<last.start])
            let multiline = gap.contains(Self.newline)
            let separator =
                items.count >= 2
                ? String(decoding: gap, as: UTF8.self)
                : (multiline ? "," + String(decoding: gap, as: UTF8.self) : ", ")
            let base = multiline ? lineIndent(before: last.start) : ""
            let text = render(Layout(base: base, unit: unit, multiline: multiline))
            bytes.insert(contentsOf: Array((separator + text).utf8), at: last.end)
            return true
        }
        let multiline = bytes.contains(Self.newline)
        let containerIndent = lineIndent(before: container.start)
        let childIndent = multiline ? containerIndent + unit : ""
        let text = render(Layout(base: childIndent, unit: unit, multiline: multiline))
        let interior =
            multiline ? "\n" + childIndent + text + "\n" + containerIndent : text
        bytes.replaceSubrange(
            (container.start + 1)..<(container.end - 1), with: Array(interior.utf8))
        return true
    }

    /// The leading whitespace of the line containing `index`.
    private func lineIndent(before index: Int) -> String {
        var start = index
        while start > 0, bytes[start - 1] != Self.newline { start -= 1 }
        var end = start
        while end < bytes.count, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// One indentation step, taken from the first indented line (default 2 spaces).
    private func detectedIndentUnit() -> String {
        var i = 0
        while i < bytes.count {
            if bytes[i] == Self.newline {
                var j = i + 1
                while j < bytes.count, bytes[j] == 0x20 || bytes[j] == 0x09 { j += 1 }
                if j > i + 1, j < bytes.count, bytes[j] != Self.newline {
                    return String(decoding: bytes[(i + 1)..<j], as: UTF8.self)
                }
            }
            i += 1
        }
        return "  "
    }

    // MARK: Scanning

    struct Span {
        var start: Int
        var end: Int  // exclusive
    }

    private struct Member {
        let key: String
        let keyStart: Int
        let value: Span
    }

    private func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == Self.newline || b == 0x0D
    }

    private func skipWhitespace(_ index: Int) -> Int {
        var i = index
        while i < bytes.count, isWhitespace(bytes[i]) { i += 1 }
        return i
    }

    /// Index just past the string literal that opens at `index`.
    private func stringEnd(_ index: Int) -> Int? {
        var i = index + 1
        while i < bytes.count {
            switch bytes[i] {
            case 0x5C: i += 2
            case 0x22: return i + 1
            default: i += 1
            }
        }
        return nil
    }

    /// Index just past the value that starts at `index`.
    private func valueEnd(_ index: Int) -> Int? {
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case 0x22:
            return stringEnd(index)
        case 0x7B, 0x5B:
            var depth = 0
            var i = index
            while i < bytes.count {
                switch bytes[i] {
                case 0x22:
                    guard let end = stringEnd(i) else { return nil }
                    i = end
                    continue
                case 0x7B, 0x5B: depth += 1
                case 0x7D, 0x5D:
                    depth -= 1
                    if depth == 0 { return i + 1 }
                default: break
                }
                i += 1
            }
            return nil
        default:
            var i = index
            while i < bytes.count, !isWhitespace(bytes[i]), bytes[i] != 0x2C, bytes[i] != 0x7D,
                bytes[i] != 0x5D
            {
                i += 1
            }
            return i > index ? i : nil
        }
    }

    private func decodeString(_ start: Int, _ end: Int) -> String? {
        try? JSONSerialization.jsonObject(
            with: Data(bytes[start..<end]), options: [.fragmentsAllowed]) as? String
    }

    private func members(of container: Span) -> [Member]? {
        guard bytes[container.start] == 0x7B else { return nil }
        var out: [Member] = []
        var i = skipWhitespace(container.start + 1)
        while i < container.end {
            if bytes[i] == 0x7D { return out }
            guard bytes[i] == 0x22, let keyEnd = stringEnd(i), let key = decodeString(i, keyEnd)
            else { return nil }
            var j = skipWhitespace(keyEnd)
            guard j < container.end, bytes[j] == 0x3A else { return nil }
            j = skipWhitespace(j + 1)
            guard let end = valueEnd(j) else { return nil }
            out.append(Member(key: key, keyStart: i, value: Span(start: j, end: end)))
            i = skipWhitespace(end)
            if i < container.end, bytes[i] == 0x2C { i = skipWhitespace(i + 1) }
        }
        return nil
    }

    private func elements(of container: Span) -> [Span]? {
        guard bytes[container.start] == 0x5B else { return nil }
        var out: [Span] = []
        var i = skipWhitespace(container.start + 1)
        while i < container.end {
            if bytes[i] == 0x5D { return out }
            guard let end = valueEnd(i) else { return nil }
            out.append(Span(start: i, end: end))
            i = skipWhitespace(end)
            if i < container.end, bytes[i] == 0x2C { i = skipWhitespace(i + 1) }
        }
        return nil
    }

    /// Index of `key` when it occurs exactly once (a duplicate key is ambiguous).
    private func uniqueIndex(of key: String, in members: [Member]) -> Int? {
        let hits = members.indices.filter { members[$0].key == key }
        return hits.count == 1 ? hits[0] : nil
    }

    /// The span of the value at `path`, or nil when it isn't there (or is ambiguous).
    func span(of path: [Step]) -> Span? {
        let start = skipWhitespace(0)
        guard let end = valueEnd(start) else { return nil }
        var current = Span(start: start, end: end)
        for step in path {
            switch step {
            case .key(let key):
                guard let found = members(of: current), let at = uniqueIndex(of: key, in: found)
                else { return nil }
                current = found[at].value
            case .index(let i):
                guard let found = elements(of: current), found.indices.contains(i) else {
                    return nil
                }
                current = found[i]
            }
        }
        return current
    }
}

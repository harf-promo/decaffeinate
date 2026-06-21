import Foundation

/// Parsed semantics of a `caffeinate` command line — what it's actually
/// preventing, and (the agentic key) whether it's waiting on another process.
/// Pure value type, no I/O.
struct CaffeinateInvocation: Equatable, Sendable {
    var preventsDisplay = false  // -d
    var preventsIdleSystem = false  // -i
    var preventsDisk = false  // -m
    var preventsOnAC = false  // -s
    var assertsUserActive = false  // -u
    var waitPID: pid_t?  // -w <pid> — keep awake until this pid exits
    var timeoutSeconds: Int?  // -t <sec>
    var trailingCommand: [String] = []  // caffeinate <utility> [args…]

    var isAnyFlagSet: Bool {
        preventsDisplay || preventsIdleSystem || preventsDisk || preventsOnAC || assertsUserActive
    }
    /// Bare `caffeinate` (no flags) ≈ prevents idle system sleep.
    var effectivePreventsSystem: Bool { preventsIdleSystem || !isAnyFlagSet }
}

enum CaffeinateArgvParser {
    /// `argv` is the full command line including argv[0] (which is ignored).
    static func parse(_ argv: [String]) -> CaffeinateInvocation {
        var inv = CaffeinateInvocation()
        var i = 1
        while i < argv.count {
            let token = argv[i]
            if token == "--" {
                inv.trailingCommand = Array(argv[(i + 1)...])
                break
            }
            guard token.hasPrefix("-"), token.count > 1 else {
                // First non-flag token → the utility caffeinate runs and waits on.
                inv.trailingCommand = Array(argv[i...])
                break
            }
            let chars = Array(token.dropFirst())
            var j = 0
            while j < chars.count {
                switch chars[j] {
                case "d": inv.preventsDisplay = true
                case "i": inv.preventsIdleSystem = true
                case "m": inv.preventsDisk = true
                case "s": inv.preventsOnAC = true
                case "u": inv.assertsUserActive = true
                case "w", "t":
                    let flag = chars[j]
                    let attached = String(chars[(j + 1)...])
                    let value: String?
                    if attached.isEmpty {
                        i += 1
                        value = i < argv.count ? argv[i] : nil
                    } else {
                        value = attached
                        j = chars.count  // consume the rest of this token
                    }
                    if flag == "w", let value, let pid = pid_t(value) { inv.waitPID = pid }
                    if flag == "t", let value, let secs = Int(value) { inv.timeoutSeconds = secs }
                default: break  // unknown flag — ignored (forward-compatible)
                }
                j += 1
            }
            i += 1
        }
        return inv
    }
}

enum CaffeinateExplainer {
    /// A plain-language sentence describing what a `caffeinate` hold is doing.
    /// `waitTargetName` is the resolved process name for `waitPID`, when known.
    /// No trailing period (matches the assertion-label voice).
    static func explain(_ inv: CaffeinateInvocation, waitTargetName: String? = nil) -> String {
        var scopes: [String] = []
        if inv.effectivePreventsSystem { scopes.append("system") }
        if inv.preventsDisplay { scopes.append("display") }
        if inv.preventsDisk { scopes.append("disk activity") }
        let scope = scopes.isEmpty ? "system" : scopes.joined(separator: " & ")

        if let pid = inv.waitPID {
            if let name = waitTargetName, !name.isEmpty {
                return "Keeping the \(scope) awake until \(name) (PID \(pid)) finishes"
            }
            return "Keeping the \(scope) awake until process \(pid) exits"
        }
        if let secs = inv.timeoutSeconds {
            return "Keeping the \(scope) awake for up to \(Format.duration(TimeInterval(secs)))"
        }
        if !inv.trailingCommand.isEmpty {
            return
                "Keeping the \(scope) awake while \(inv.trailingCommand.joined(separator: " ")) runs"
        }
        return "Keeping the \(scope) awake"
    }
}

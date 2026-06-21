import Foundation

/// Headless command-line entry points, so the same binary that runs the menu-bar
/// app can also answer questions from a terminal or a script:
///
///     Decaffeinate --scan       # print what's keeping this Mac awake
///     Decaffeinate --version
///
/// `--scan` needs no GUI session, which also makes it the project's smoke test.
enum CLI {
    /// Returns `true` if it handled a command and the process should exit.
    @MainActor
    static func handleIfNeeded(_ arguments: [String]) -> Bool {
        if arguments.contains("--version") || arguments.contains("-v") {
            print("Decaffeinate \(AppInfo.version)")
            return true
        }
        if arguments.contains("--scan") || arguments.contains("-s") {
            runScan()
            return true
        }
        if arguments.contains("--help") || arguments.contains("-h") {
            printHelp()
            return true
        }
        if let index = arguments.firstIndex(of: "--screenshots") {
            let dir = arguments.indices.contains(index + 1) ? arguments[index + 1] : "screenshots"
            _ = ScreenshotRenderer.renderAll(to: dir)
            return true
        }
        if let index = arguments.firstIndex(of: "--provenance") {
            let pid = arguments.indices.contains(index + 1) ? pid_t(arguments[index + 1]) : nil
            runProvenance(pid: pid)
            return true
        }
        return false
    }

    /// Resolve and print where each sleep-holder came from — the window / agent /
    /// project behind it. `--provenance [pid]` resolves one pid, or every holder.
    @MainActor
    private static func runProvenance(pid: pid_t?) {
        let resolver = ProcessProvenanceResolver()

        func dump(_ pid: pid_t, label: String) {
            guard let p = resolver.provenance(for: pid) else {
                print("• \(label) — pid \(pid): (unresolved)")
                return
            }
            let chain = p.parentChain.map { "\($0.name)(\($0.pid))" }.joined(separator: " → ")
            print("• \(label) — pid \(p.holderPid) [\(p.holderName)]")
            print("    session:  \(p.sessionLabel ?? "—")")
            print("    started by: \(p.originDisplayName ?? "—")  (\(p.originKind.rawValue))")
            print("    tty:      \(p.ttyName ?? "—")")
            print("    cwd:      \(p.cwd ?? "—")")
            print("    argv:     \(p.holderArgv.joined(separator: " "))")
            print("    parents:  \(chain.isEmpty ? "—" : chain)")
            if let cmd = p.originCommand { print("    command:  \(cmd.joined(separator: " "))") }
        }

        if let pid {
            dump(pid, label: "process")
            return
        }
        let holders = TelemetryEngine().scan().filter(\.blocksSystemSleep)
        if holders.isEmpty {
            print("☕️  Nothing is holding this Mac awake.")
            return
        }
        for holder in holders { dump(holder.pid, label: holder.displayName) }
    }

    @MainActor
    private static func runScan() {
        let assertions = TelemetryEngine().scan()
        let blockers = assertions.filter(\.blocksSystemSleep)
        let displayOnly = assertions.filter { $0.kind == .displaySleep }

        if assertions.isEmpty {
            print("☕️  Nothing is keeping this Mac awake. It is free to sleep.")
            return
        }

        if blockers.isEmpty {
            print("☕️  Nothing is blocking *system* sleep.")
        } else {
            print(
                "☀️  \(blockers.count) assertion\(blockers.count == 1 ? "" : "s") are keeping this Mac awake:\n"
            )
            for a in blockers { printRow(a) }
        }

        if !displayOnly.isEmpty {
            print("\n🖥  Keeping the display on (likely media or a call):\n")
            for a in displayOnly { printRow(a) }
        }
    }

    @MainActor
    private static func printRow(_ a: PowerAssertion) {
        // The assertion name is app-controlled free text; sanitize before it hits
        // the terminal (ESC/ANSI injection) just like the reason explanation.
        let rawName = a.name.isEmpty || a.name == "Unnamed" ? "—" : a.name
        let name = ReasonEngine.sanitize(rawName)
        let via = a.attribution.map { " (\($0))" } ?? ""
        let reason = a.reason
        var why = "↳ \(reason.explanation)"
        if !reason.resourceLabels.isEmpty {
            why += " · " + reason.resourceLabels.joined(separator: ", ")
        }
        if let secs = reason.autoReleaseSeconds {
            why += " · auto-releases in \(secs)s"
        }
        print("  • \(a.displayName)\(via)  (pid \(a.pid))")
        print("      \(why)")
        print("      \(a.assertionType): “\(name)”")
    }

    private static func printHelp() {
        print(
            """
            Decaffeinate — the truth about what keeps your Mac awake.

            USAGE:
              Decaffeinate                Run the menu-bar app
              Decaffeinate --scan         Print active sleep assertions and exit
              Decaffeinate --provenance   Trace each holder to its window / agent / project
              Decaffeinate --version      Print the version and exit
              Decaffeinate --help         Show this help

            Project: https://github.com/harf-promo/decaffeinate
            """
        )
    }
}

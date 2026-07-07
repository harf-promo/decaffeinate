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
        if arguments.contains("--scan") || arguments.contains("-s")
            || arguments.contains("--why-awake")
        {
            if arguments.contains("--json") { runStatus(json: true) } else { runScan() }
            return true
        }
        if arguments.contains("--status") {
            runStatus(json: arguments.contains("--json"))
            return true
        }
        if arguments.contains("--sleep-now") {
            runSleepNow()
            return true
        }
        if arguments.contains("--display-off") {
            runDisplayOff()
            return true
        }
        if let index = arguments.firstIndex(of: "--keep-awake") {
            let minutes = arguments.indices.contains(index + 1) ? Int(arguments[index + 1]) : nil
            runKeepAwake(minutes: minutes ?? 30)
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
        if let index = arguments.firstIndex(of: "--icon") {
            let dir = arguments.indices.contains(index + 1) ? arguments[index + 1] : "assets"
            _ = IconRenderer.renderAll(to: dir)
            return true
        }
        if let index = arguments.firstIndex(of: "--provenance") {
            let pid = arguments.indices.contains(index + 1) ? pid_t(arguments[index + 1]) : nil
            runProvenance(pid: pid)
            return true
        }
        if arguments.contains("--diagnose") {
            runDiagnose()
            return true
        }
        return false
    }

    /// Print a copy-pasteable diagnostics report — the artifact a bug report
    /// needs (effective settings + rules + the current scan). Headless, so it
    /// captures the settings *combination*, not just the live assertions.
    @MainActor
    private static func runDiagnose() {
        let settings = SettingsStore().settings
        let rules = RulesEngine()
        let all = TelemetryEngine().scan().filter {
            $0.pid != ProcessInfo.processInfo.processIdentifier
        }
        let uptime = SystemStateReader().bootTime().map { Date().timeIntervalSince($0) }
        let snapshot = Diagnostics.Snapshot(
            version: AppInfo.version,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: SystemProfile.modelIdentifier(),
            generatedAt: Date(),
            settings: settings,
            rules: rules.rules,
            power: PowerSourceReader().snapshot(),
            thermal: ProcessInfo.processInfo.thermalState,
            idleSeconds: IdleMonitor().secondsSinceLastInput(),
            uptimeSeconds: uptime,
            stateHeadline: "(run the app for the live verdict)",
            stateDetail: "headless --diagnose snapshot",
            systemBlockers: all.filter(\.blocksSystemSleep),
            otherAssertions: all.filter { !$0.blocksSystemSleep })
        print(Diagnostics.report(snapshot))
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

    /// Machine-readable status — the JSON scripts and agent hooks consume. A
    /// stable, sorted shape; the process's own hold is excluded.
    @MainActor
    private static func runStatus(json: Bool) {
        let report = StatusReport.from(
            version: AppInfo.version, now: Date(),
            ownPID: ProcessInfo.processInfo.processIdentifier,
            assertions: TelemetryEngine().scan(),
            power: PowerSourceReader().snapshot(),
            thermal: ProcessInfo.processInfo.thermalState,
            idleSeconds: IdleMonitor().secondsSinceLastInput(),
            uptimeSeconds: SystemStateReader().bootTime().map { Date().timeIntervalSince($0) })
        if json {
            print(report.jsonString())
        } else {
            // A terse human line for `--status` without --json.
            let verb = report.holdingSystemSleep == 0 ? "free to sleep" : "held awake"
            let by =
                report.holdingSystemSleep == 0
                ? ""
                : " by \(report.holdingSystemSleep) app\(report.holdingSystemSleep == 1 ? "" : "s")"
            print("This Mac is \(verb)\(by). Idle \(report.idleSeconds)s.")
        }
    }

    /// Turn the display off now (system keeps running). Exits non-zero on failure.
    @MainActor
    private static func runDisplayOff() {
        switch SleepController().displayOffNow() {
        case .success:
            print("🌙  Turning the display off…")
        case .failure(let error):
            FileHandle.standardError.write(Data("decaffeinate: \(error.description)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Put the Mac to sleep now — the same headless `pmset sleepnow` path the app
    /// uses. Exits non-zero if the launch fails, so scripts can react.
    @MainActor
    private static func runSleepNow() {
        switch SleepController().sleepNow() {
        case .success:
            print("😴  Putting this Mac to sleep now…")
        case .failure(let error):
            FileHandle.standardError.write(Data("decaffeinate: \(error.description)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Hold this Mac awake for `minutes`, then release — a foreground, blocking
    /// hold (like `caffeinate -t`). Ctrl-C exits early; the kernel releases the
    /// assertion automatically on process exit.
    ///
    /// The hold is watched by the same safety rails as the GUI toggle: every few
    /// seconds the thermal and battery state are re-evaluated, and the hold is
    /// released (with a non-zero exit so scripts can react) the moment a rail
    /// demands it — the Backpack Guard and Battery Floor are unconditional
    /// promises, not GUI-only ones.
    @MainActor
    private static func runKeepAwake(minutes: Int) {
        let clamped = min(max(minutes, 1), 24 * 60)
        let power = PowerSourceReader()

        // Re-reads the user's settings on every check: a hold can run for up to
        // 24 h, and a battery-floor / thermal-guard change made in the GUI
        // mid-hold must apply to it, not a snapshot from launch time. (Shared
        // defaults domain when run from the installed app; safe defaults
        // otherwise.)
        func dropReason() -> String? {
            keepAwakeSafetyDropReason(
                power: power.snapshot(),
                thermalState: ProcessInfo.processInfo.thermalState,
                settings: SettingsStore().settings)
        }

        // Rails apply from the very first moment — never create a hold on a Mac
        // that is already below the floor or thermally stressed.
        if let reason = dropReason() {
            FileHandle.standardError.write(
                Data("🛟  \(reason) — not keeping this Mac awake.\n".utf8))
            exit(EXIT_FAILURE)
        }

        let engine = CaffeineEngine()
        engine.update(
            keepSystemAwake: true, keepDisplayAwake: false, reason: "Decaffeinate --keep-awake")
        print("☕️  Keeping this Mac awake for \(clamped) min. Press Ctrl-C to stop early.")
        let deadline = Date().addingTimeInterval(TimeInterval(clamped) * 60)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            Thread.sleep(forTimeInterval: min(5, remaining))
            // A hold that ran its full course is a success — don't let a rail
            // dip during the final nap turn a completed hold into exit 1.
            if deadline.timeIntervalSinceNow <= 0 { break }
            if let reason = dropReason() {
                engine.releaseAll()
                FileHandle.standardError.write(
                    Data("🛟  \(reason) — released the keep-awake hold.\n".utf8))
                exit(EXIT_FAILURE)
            }
        }
        engine.releaseAll()
        print("✓  Done — this Mac can sleep again.")
    }

    /// Why the safety rails demand dropping a keep-awake hold right now, or nil.
    /// Pure mapping over `SafetyRails` so `--keep-awake`'s guard is testable.
    static func keepAwakeSafetyDropReason(
        power: PowerSnapshot,
        thermalState: ProcessInfo.ThermalState,
        settings: DecaffeinateSettings
    ) -> String? {
        let decision = SafetyRails.evaluate(
            assertions: [],
            power: power,
            thermalState: thermalState,
            whitelistedAwakeAppNames: [],
            settings: settings)
        return decision.dropKeepAwakeReasons.first
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
        // The GUI filters its own hold out of the app; the CLI keeps it visible
        // for honesty, tagged so the reader knows who it belongs to. (A scan runs
        // as its own process, so match the app by name, not pid.)
        let selfTag =
            a.pid == ProcessInfo.processInfo.processIdentifier || a.processName == "Decaffeinate"
            ? " ← this app" : ""
        print("  • \(a.displayName)\(selfTag)\(via)  (pid \(a.pid))")
        print("      \(why)")
        print("      \(a.assertionType): “\(name)”")
    }

    private static func printHelp() {
        print(
            """
            Decaffeinate — the truth about what keeps your Mac awake.

            USAGE:
              Decaffeinate                  Run the menu-bar app
              Decaffeinate --scan           Print active sleep assertions and exit
              Decaffeinate --status [--json]  Print a status line (or JSON for scripts/hooks)
              Decaffeinate --why-awake [--json]  Alias for --scan (add --json for machine output)
              Decaffeinate --sleep-now      Put this Mac to sleep now and exit
              Decaffeinate --display-off    Turn the display off now (system keeps running)
              Decaffeinate --keep-awake N   Hold this Mac awake for N minutes (default 30), then exit
              Decaffeinate --provenance     Trace each holder to its window / agent / project
              Decaffeinate --diagnose       Print a diagnostics report (settings + rules + scan)
              Decaffeinate --icon [dir]     Regenerate icon-1024.png, AppIcon.icns, SVG (default: assets/)
              Decaffeinate --version        Print the version and exit
              Decaffeinate --help           Show this help

            Project: https://github.com/harf-promo/decaffeinate
            """
        )
    }
}

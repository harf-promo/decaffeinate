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
        if arguments.contains("--clamshell-status") {
            runClamshellStatus(json: arguments.contains("--json"))
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
        if let index = arguments.firstIndex(of: "--sleep-if-idle") {
            runSleepIfIdle(
                threshold: idleThreshold(
                    after: index, in: arguments, default: HookInstaller.defaultIdleSeconds))
            return true
        }
        if let index = arguments.firstIndex(of: "--install-hook") {
            runInstallHook(target: hookTarget(after: index, in: arguments))
            return true
        }
        if let index = arguments.firstIndex(of: "--uninstall-hook") {
            runUninstallHook(target: hookTarget(after: index, in: arguments))
            return true
        }
        if arguments.contains("--mcp") {
            runMCP()  // returns Never — serves stdio until the client disconnects
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
            stateHeadline: L10n.localized("(run the app for the live verdict)"),
            stateDetail: L10n.localized("headless --diagnose snapshot"),
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
                print(L10n.localized("• %@ — pid %d: (unresolved)", label, pid))
                return
            }
            let chain = p.parentChain.map { "\($0.name)(\($0.pid))" }.joined(separator: " → ")
            print(
                L10n.localized(
                    "• %@ — pid %d [%@]", label, p.holderPid, p.holderName))
            print(L10n.localized("    session:  %@", p.sessionLabel ?? "—"))
            print(
                L10n.localized(
                    "    started by: %@  (%@)", p.originDisplayName ?? "—", p.originKind.rawValue))
            print(L10n.localized("    tty:      %@", p.ttyName ?? "—"))
            print(L10n.localized("    cwd:      %@", p.cwd ?? "—"))
            print(L10n.localized("    argv:     %@", p.holderArgv.joined(separator: " ")))
            print(L10n.localized("    parents:  %@", chain.isEmpty ? "—" : chain))
            if let cmd = p.originCommand {
                print(L10n.localized("    command:  %@", cmd.joined(separator: " ")))
            }
        }

        if let pid {
            dump(pid, label: L10n.localized("process"))
            return
        }
        let holders = TelemetryEngine().scan().filter(\.blocksSystemSleep)
        if holders.isEmpty {
            print(L10n.localized("☕️  Nothing is holding this Mac awake."))
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
            if report.holdingSystemSleep == 0 {
                print(
                    L10n.localized(
                        "This Mac is free to sleep. Idle %ds.", report.idleSeconds))
            } else if report.holdingSystemSleep == 1 {
                print(
                    L10n.localized(
                        "This Mac is held awake by 1 app. Idle %ds.", report.idleSeconds))
            } else {
                print(
                    L10n.localized(
                        "This Mac is held awake by %d apps. Idle %ds.",
                        report.holdingSystemSleep, report.idleSeconds))
            }
        }
    }

    /// Print the zero-root Clamshell Assistant's readiness verdict — a plain
    /// line, or JSON (same stable-sorted-keys convention as `--status --json`).
    /// Read-only: this never arms a keep-awake hold, it only reports.
    @MainActor
    private static func runClamshellStatus(json: Bool) {
        let readiness = ClamshellAdvisor.classify(
            lid: LidStateReader().snapshot(),
            displays: DisplayTopologyReader().snapshot(),
            power: PowerSourceReader().snapshot(),
            input: ExternalInputProbe().probe())
        if json {
            print(ClamshellStatusReport.from(readiness: readiness).jsonString())
        } else {
            print(clamshellStatusLine(readiness))
        }
    }

    /// The human-readable line for `--clamshell-status` (without `--json`) and
    /// `ClamshellStatusIntent`'s spoken dialog — one place so the two surfaces
    /// never drift.
    static func clamshellStatusLine(_ readiness: ClamshellReadiness) -> String {
        switch readiness {
        case .notApplicable:
            return L10n.localized(
                "This Mac doesn\u{2019}t have a lid \u{2014} clamshell mode doesn\u{2019}t apply.")
        case .ready:
            return L10n.localized(
                "Ready for clamshell mode \u{2014} close the lid whenever you like.")
        case .missing(let unmet):
            let items = ClamshellRequirement.allCases.filter { unmet.contains($0) }
                .map { L10n.localized($0.label) }
            return L10n.localized(
                "Not ready for clamshell mode \u{2014} %@.", items.joined(separator: "; "))
        }
    }

    /// Turn the display off now (system keeps running). Exits non-zero on failure.
    @MainActor
    private static func runDisplayOff() {
        switch SleepController().displayOffNow() {
        case .success:
            print(L10n.localized("🌙  Turning the display off…"))
        case .failure(let error):
            FileHandle.standardError.write(
                Data((L10n.localized("decaffeinate: %@", error.description) + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    /// Put the Mac to sleep now — the same headless `pmset sleepnow` path the app
    /// uses. Exits non-zero if the launch fails, so scripts can react.
    /// Deliberately bypasses `AppState.sleepNow()`'s call-in-progress
    /// confirmation guard (menu button / hotkey only) — a non-interactive CLI
    /// invocation has no one to answer a confirmation dialog.
    @MainActor
    private static func runSleepNow() {
        switch SleepController().sleepNow() {
        case .success:
            print(L10n.localized("😴  Putting this Mac to sleep now…"))
        case .failure(let error):
            FileHandle.standardError.write(
                Data((L10n.localized("decaffeinate: %@", error.description) + "\n").utf8))
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
                Data(
                    (L10n.localized("🛟  %@ — not keeping this Mac awake.", reason) + "\n").utf8))
            exit(EXIT_FAILURE)
        }

        let engine = CaffeineEngine()
        engine.update(
            keepSystemAwake: true, keepDisplayAwake: false, reason: "Decaffeinate --keep-awake")
        print(
            L10n.localized(
                "☕️  Keeping this Mac awake for %d min. Press Ctrl-C to stop early.", clamped))
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
                    Data(
                        (L10n.localized("🛟  %@ — released the keep-awake hold.", reason) + "\n")
                            .utf8))
                exit(EXIT_FAILURE)
            }
        }
        engine.releaseAll()
        print(L10n.localized("✓  Done — this Mac can sleep again."))
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

    // MARK: --sleep-if-idle (idle-gated sleep — the turn-end hook target)

    /// True iff the Mac has been idle at least `threshold` seconds (the boundary
    /// sleeps). Pure so the gate is unit-testable.
    static func shouldSleep(idleSeconds: TimeInterval, threshold: Int) -> Bool {
        Int(idleSeconds) >= threshold
    }

    /// The idle threshold following `--sleep-if-idle`: the first Int-parseable
    /// token after the flag, else `fallback`. This tolerates the trailing JSON blob
    /// Codex appends to its `notify` program (a non-numeric arg → fallback), so the
    /// same verb works for Claude (`--sleep-if-idle 300`) and Codex without parsing
    /// JSON.
    static func idleThreshold(after index: Int, in args: [String], default fallback: Int) -> Int {
        guard args.indices.contains(index + 1), let n = Int(args[index + 1]) else {
            return fallback
        }
        return n
    }

    /// Which agent(s) an `--install-hook` / `--uninstall-hook` targets; defaults to
    /// all when no (or an unrecognized) argument follows.
    static func hookTarget(after index: Int, in args: [String]) -> [HookInstaller.Client] {
        guard args.indices.contains(index + 1) else { return HookInstaller.Client.allCases }
        switch args[index + 1] {
        case "claude": return [.claude]
        case "codex": return [.codex]
        case "cursor": return [.cursor]
        default: return HookInstaller.Client.allCases
        }
    }

    @MainActor
    private static func runSleepIfIdle(threshold: Int) {
        let idle = IdleMonitor().secondsSinceLastInput()
        guard shouldSleep(idleSeconds: idle, threshold: threshold) else {
            // Exit 0: a Stop hook fires every turn, so "still busy" is expected, not
            // an error.
            print(
                L10n.localized(
                    "☕️  Active %ds ago (< %ds) — leaving this Mac awake.", Int(idle), threshold))
            return
        }
        switch SleepController().sleepNow() {
        case .success:
            print(
                L10n.localized(
                    "😴  Idle %ds ≥ %ds — putting this Mac to sleep now…", Int(idle), threshold))
        case .failure(let error):
            FileHandle.standardError.write(
                Data((L10n.localized("decaffeinate: %@", error.description) + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    // MARK: --install-hook / --uninstall-hook

    @MainActor
    private static func runInstallHook(target: [HookInstaller.Client]) {
        let bin = HookInstaller.binaryPath()
        if !bin.contains("/Applications/") {
            FileHandle.standardError.write(
                Data(
                    (L10n.localized(
                        "⚠️  Hook will run %@ — move Decaffeinate to /Applications for a stable path.",
                        bin) + "\n").utf8))
        }
        let seconds = HookInstaller.defaultIdleSeconds
        var failed = false
        let fm = FileManager.default
        for client in target {
            switch client {
            case .claude:
                let url = HookInstaller.claudeSettingsURL()
                // A present-but-unreadable file reads as nil; only treat a genuinely
                // absent file as "start fresh", never overwrite one we can't read.
                let exists = fm.fileExists(atPath: url.path)
                let data = try? Data(contentsOf: url)
                if exists && data == nil {
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized("✗ Couldn't read %@ — left it untouched.", url.path)
                                + "\n").utf8))
                    failed = true
                    continue
                }
                guard
                    let updated = HookInstaller.installClaudeHook(
                        into: data, binaryPath: bin, seconds: seconds)
                else {
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized(
                                "✗ %@ isn't JSON I can safely edit — left it untouched. Fix or remove it, then re-run.",
                                url.path) + "\n").utf8))
                    failed = true
                    continue
                }
                if writeHook(updated, to: url, label: L10n.localized("Claude Code Stop hook")) {
                    failed = true
                }
            case .codex:
                let url = HookInstaller.codexConfigURL()
                let existing: String
                if fm.fileExists(atPath: url.path) {
                    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
                        FileHandle.standardError.write(
                            Data(
                                (L10n.localized(
                                    "✗ %@ isn't readable UTF-8 — left it untouched.",
                                    url.path) + "\n").utf8))
                        failed = true
                        continue
                    }
                    existing = contents
                } else {
                    existing = ""
                }
                switch HookInstaller.installCodexNotify(
                    into: existing, binaryPath: bin, seconds: seconds)
                {
                case .success(let text):
                    if writeHook(
                        Data(text.utf8), to: url, label: L10n.localized("Codex notify hook"))
                    {
                        failed = true
                    }
                case .failure(.wouldClobberExistingNotify):
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized(
                                "✗ %@ already sets `notify` — refusing to overwrite it. Remove it first, then re-run.",
                                url.path) + "\n").utf8))
                    failed = true
                }
            case .cursor:
                let url = HookInstaller.cursorHooksURL()
                let exists = fm.fileExists(atPath: url.path)
                let data = try? Data(contentsOf: url)
                if exists && data == nil {
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized("✗ Couldn't read %@ — left it untouched.", url.path)
                                + "\n").utf8))
                    failed = true
                    continue
                }
                guard
                    let updated = HookInstaller.installCursorHook(
                        into: data, binaryPath: bin, seconds: seconds)
                else {
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized(
                                "✗ %@ isn't JSON I can safely edit — left it untouched. Fix or remove it, then re-run.",
                                url.path) + "\n").utf8))
                    failed = true
                    continue
                }
                if writeHook(updated, to: url, label: L10n.localized("Cursor stop hook")) {
                    failed = true
                }
            }
        }
        if failed { exit(EXIT_FAILURE) }
    }

    /// Write hook file content; returns true on failure (so the caller can exit
    /// non-zero). Prints a confirmation on success.
    @MainActor
    private static func writeHook(_ data: Data, to url: URL, label: String) -> Bool {
        do {
            try HookInstaller.atomicWrite(data, to: url)
            print(L10n.localized("✓  Installed the %@ → %@", label, url.path))
            return false
        } catch {
            FileHandle.standardError.write(
                Data(
                    (L10n.localized("✗ Couldn't write %@: %@", url.path, "\(error)") + "\n").utf8))
            return true
        }
    }

    @MainActor
    private static func runUninstallHook(target: [HookInstaller.Client]) {
        var failed = false
        for client in target {
            switch client {
            case .claude:
                let url = HookInstaller.claudeSettingsURL()
                guard let existing = try? Data(contentsOf: url) else {
                    print(L10n.localized("·  No Claude settings at %@.", url.path))
                    continue
                }
                guard let updated = HookInstaller.uninstallClaudeHook(from: existing) else {
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized("✗ Couldn't parse %@ — left it untouched.", url.path)
                                + "\n").utf8))
                    failed = true
                    continue
                }
                removeHook(
                    updated, wasUnchanged: updated == existing, to: url,
                    label: L10n.localized("Claude Code"))
            case .codex:
                let url = HookInstaller.codexConfigURL()
                guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
                    print(L10n.localized("·  No Codex config at %@.", url.path))
                    continue
                }
                let updated = HookInstaller.uninstallCodexNotify(from: existing)
                removeHook(
                    Data(updated.utf8), wasUnchanged: updated == existing, to: url,
                    label: L10n.localized("Codex"))
            case .cursor:
                let url = HookInstaller.cursorHooksURL()
                guard let existing = try? Data(contentsOf: url) else {
                    print(L10n.localized("·  No Cursor hooks at %@.", url.path))
                    continue
                }
                guard let updated = HookInstaller.uninstallCursorHook(from: existing) else {
                    FileHandle.standardError.write(
                        Data(
                            (L10n.localized("✗ Couldn't parse %@ — left it untouched.", url.path)
                                + "\n").utf8))
                    failed = true
                    continue
                }
                removeHook(
                    updated, wasUnchanged: updated == existing, to: url,
                    label: L10n.localized("Cursor"))
            }
        }
        if failed { exit(EXIT_FAILURE) }
    }

    @MainActor
    private static func removeHook(_ data: Data, wasUnchanged: Bool, to url: URL, label: String) {
        if wasUnchanged {
            print(L10n.localized("·  No Decaffeinate hook in %@.", url.path))
            return
        }
        do {
            try HookInstaller.atomicWrite(data, to: url)
            print(L10n.localized("✓  Removed the %@ hook from %@.", label, url.path))
        } catch {
            FileHandle.standardError.write(
                Data(
                    (L10n.localized("✗ Couldn't write %@: %@", url.path, "\(error)") + "\n").utf8))
        }
    }

    // MARK: --mcp

    /// Serve the Model Context Protocol over stdio until the client disconnects.
    /// Never returns: the server runs on a detached task and `dispatchMain()`
    /// services the main-actor executor (a main-thread semaphore would deadlock it).
    @MainActor
    static func runMCP() -> Never {
        let server = MCPServer()
        Task.detached {
            await server.run()
            exit(EXIT_SUCCESS)
        }
        dispatchMain()
    }

    @MainActor
    private static func runScan() {
        let assertions = TelemetryEngine().scan()
        let blockers = assertions.filter(\.blocksSystemSleep)
        let displayOnly = assertions.filter { $0.kind == .displaySleep }

        if assertions.isEmpty {
            print(L10n.localized("☕️  Nothing is keeping this Mac awake. It is free to sleep."))
            return
        }

        if blockers.isEmpty {
            print(L10n.localized("☕️  Nothing is blocking *system* sleep."))
        } else {
            let header =
                blockers.count == 1
                ? L10n.localized("☀️  1 assertion is keeping this Mac awake:")
                : L10n.localized(
                    "☀️  %d assertions are keeping this Mac awake:", blockers.count)
            print(header + "\n")
            for a in blockers { printRow(a) }
        }

        if !displayOnly.isEmpty {
            print(
                "\n" + L10n.localized("🖥  Keeping the display on (likely media or a call):") + "\n")
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
        // `--scan` is the human-readable line (unlike `--status --json`, which
        // embeds `reason.explanation`/`resourceLabels` verbatim and must stay
        // English) — localize here, at the print site, not at the source.
        var why = "↳ \(L10n.localized(reason.explanation))"
        if !reason.resourceLabels.isEmpty {
            why += " · " + reason.resourceLabels.map { L10n.localized($0) }.joined(separator: ", ")
        }
        if let secs = reason.autoReleaseSeconds {
            why += " · " + L10n.localized("auto-releases in %ds", secs)
        }
        // The GUI filters its own hold out of the app; the CLI keeps it visible
        // for honesty, tagged so the reader knows who it belongs to. (A scan runs
        // as its own process, so match the app by name, not pid.)
        let selfTag =
            a.pid == ProcessInfo.processInfo.processIdentifier || a.processName == "Decaffeinate"
            ? " " + L10n.localized("← this app") : ""
        print("  • \(a.displayName)\(selfTag)\(via)  (pid \(a.pid))")
        print("      \(why)")
        print("      \(a.assertionType): “\(name)”")
    }

    private static func printHelp() {
        let lines = [
            L10n.localized("Decaffeinate — the truth about what keeps your Mac awake."),
            "",
            L10n.localized("USAGE:"),
            L10n.localized("  Decaffeinate                  Run the menu-bar app"),
            L10n.localized(
                "  Decaffeinate --scan           Print active sleep assertions and exit"),
            L10n.localized(
                "  Decaffeinate --status [--json]  Print a status line (or JSON for scripts/hooks)"),
            L10n.localized(
                "  Decaffeinate --clamshell-status [--json]  Ready for Apple's lid-closed clamshell mode?"
            ),
            L10n.localized(
                "  Decaffeinate --why-awake [--json]  Alias for --scan (add --json for machine output)"
            ),
            L10n.localized("  Decaffeinate --sleep-now      Put this Mac to sleep now and exit"),
            L10n.localized(
                "  Decaffeinate --display-off    Turn the display off now (system keeps running)"),
            L10n.localized(
                "  Decaffeinate --keep-awake N   Hold this Mac awake for N minutes (default 30), then exit"
            ),
            L10n.localized(
                "  Decaffeinate --sleep-if-idle N  Sleep only if idle ≥ N seconds (default 300) — for turn-end hooks"
            ),
            L10n.localized(
                "  Decaffeinate --install-hook [claude|codex|cursor|all]    Install a turn-end sleep hook (default all)"
            ),
            L10n.localized(
                "  Decaffeinate --uninstall-hook [claude|codex|cursor|all]  Remove the hook (marker-based, clean)"
            ),
            L10n.localized(
                "  Decaffeinate --mcp            Run an MCP server over stdio (keep-awake / status / sleep tools)"
            ),
            L10n.localized(
                "  Decaffeinate --provenance     Trace each holder to its window / agent / project"),
            L10n.localized(
                "  Decaffeinate --diagnose       Print a diagnostics report (settings + rules + scan)"
            ),
            L10n.localized(
                "  Decaffeinate --icon [dir]     Regenerate icon-1024.png, AppIcon.icns, SVG (default: assets/)"
            ),
            L10n.localized("  Decaffeinate --version        Print the version and exit"),
            L10n.localized("  Decaffeinate --help           Show this help"),
            "",
            L10n.localized("Project: https://github.com/harf-promo/decaffeinate"),
        ]
        print(lines.joined(separator: "\n"))
    }
}

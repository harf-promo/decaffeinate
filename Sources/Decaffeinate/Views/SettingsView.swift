import SwiftUI

/// Settings as a native sidebar (the macOS idiom for many sections) instead of
/// the old 8-tab strip that clipped its last tab. Eight panes fold into five,
/// grouped; native toggles/sliders are kept for muscle memory but tinted in the
/// brand green so Settings and the menu read as one product.
struct SettingsView: View {
    @Environment(\.theme) private var theme
    @State private var pane: SettingsPane

    /// Defaults to General; the screenshot renderer opens a specific pane.
    init(initialPane: SettingsPane = .general) {
        _pane = State(initialValue: initialPane)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(theme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 660, height: 480)
        .background(theme.paper)
        .tint(theme.accent)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 1) {
            sidebarLabel("Settings")
            ForEach([SettingsPane.general, .schedule, .automation, .freshness]) { sidebarRow($0) }
            sidebarLabel("Info").padding(.top, Space.s3)
            ForEach([SettingsPane.history, .about]) { sidebarRow($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Space.s2)
        .padding(.vertical, Space.s3)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.card)
    }

    private func sidebarLabel(_ text: String) -> some View {
        Text(text).textCase(.uppercase).font(.system(size: 11, weight: .semibold))
            .tracking(0.8).foregroundStyle(theme.ink4)
            .padding(.horizontal, Space.s2).padding(.bottom, 2)
    }

    private func sidebarRow(_ item: SettingsPane) -> some View {
        let selected = pane == item
        return Button {
            pane = item
        } label: {
            HStack(spacing: Space.s2) {
                Image(systemName: item.icon).frame(width: 18)
                    .foregroundStyle(selected ? Color.onGreen : theme.ink3)
                Text(item.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.onGreen : theme.ink1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.s2).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.soft)
                    .fill(selected ? theme.accent : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralSettings()
        case .schedule: ScheduleSettings()
        case .automation: AutomationSettings()
        case .freshness: FreshnessSettings()
        case .history: HistorySettings()
        case .about: AboutView()
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, schedule, automation, freshness, history, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .schedule: return "Schedule"
        case .automation: return "Automation"
        case .freshness: return "Rest & Restart"
        case .history: return "History"
        case .about: return "About"
        }
    }
    var icon: String {
        switch self {
        case .general: return "zzz"
        case .schedule: return "calendar"
        case .automation: return "bolt.horizontal.circle"
        case .freshness: return "arrow.clockwise.circle"
        case .history: return "clock.arrow.circlepath"
        case .about: return "info.circle"
        }
    }
}

// ── General: auto-sleep + battery + keep-awake + safety guards + startup ──
private struct GeneralSettings: View {
    @EnvironmentObject var store: SettingsStore
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            Section("Put the Mac to sleep") {
                Toggle("Auto-sleep when left idle", isOn: s.decaffeinateEnabled)
                LabeledSlider(
                    "Sleep after", value: s.idleThresholdMinutes, range: 1...60,
                    unit: "min", enabled: store.settings.decaffeinateEnabled)
                Text(
                    "When you step away, Decaffeinate forces sleep after this much idle time — even if an app is trying to keep the Mac awake."
                )
                .settingsCaption()

                Toggle("Sleep sooner on battery", isOn: s.sleepSoonerOnBattery)
                    .disabled(!store.settings.decaffeinateEnabled)
                LabeledSlider(
                    "On battery, sleep after", value: s.batteryIdleThresholdMinutes, range: 1...30,
                    unit: "min",
                    enabled: store.settings.decaffeinateEnabled
                        && store.settings.sleepSoonerOnBattery
                )
                if store.settings.sleepSoonerOnBattery,
                    store.settings.batteryIdleThresholdMinutes
                        >= store.settings.idleThresholdMinutes
                {
                    Text(
                        "This is at least your normal idle time, so it has no effect — lower it to sleep sooner on battery."
                    )
                    .font(.caption).foregroundStyle(Color.warning)
                }
            }

            Section("Never sleep at a bad moment") {
                Toggle("Pause while the microphone is in use (calls)", isOn: s.pauseForActiveCall)
                Toggle("Pause for active media", isOn: s.pauseForActiveMedia)
                Toggle("Pause during Time Machine backups", isOn: s.pauseForTimeMachine)
                Toggle("Pause during macOS updates", isOn: s.pauseForSystemUpdate)
                Toggle("Respect apps I've allowed", isOn: s.respectWhitelist)
                Text(
                    "The call guard is never time-limited. Media holds are released after you've been idle well past your sleep delay, so a forgotten background tab can't keep the Mac awake forever."
                )
                .settingsCaption()
            }

            Section("Battery & heat") {
                LabeledSlider(
                    "Battery floor",
                    value: Binding(
                        get: { Double(store.settings.batteryFloorPercent) },
                        set: { store.settings.batteryFloorPercent = Int($0) }),
                    range: 0...50, step: 5, unit: "%", width: 44)
                Text("On battery, keep-awake holds are dropped below this charge.")
                    .settingsCaption()
                Toggle("Backpack guard (sleep if overheating)", isOn: s.thermalGuardEnabled)
                Text(
                    "If the Mac gets thermally stressed — e.g. lid closed in a bag — all keep-awake holds are released and it sleeps immediately."
                )
                .settingsCaption()
            }

            Section("Keep awake (optional)") {
                Toggle("Hold the Mac awake on purpose", isOn: s.caffeinateEnabled)
                Toggle("Also keep the display on", isOn: s.caffeinateKeepsDisplayAwake)
                    .disabled(!store.settings.caffeinateEnabled)
            }

            Section("Startup & alerts") {
                Toggle("Notify me when a new app keeps the Mac awake", isOn: s.notifyOnNewBlocker)
                Toggle("Show the countdown in the menu bar", isOn: s.showMenuBarCountdown)
                if LoginItem.isAvailable {
                    Toggle("Launch at login", isOn: s.launchAtLogin)
                        .onChange(of: store.settings.launchAtLogin) { _, newValue in
                            // Revert the toggle if SMAppService registration fails
                            // so it always reflects the actual login-item state.
                            if !LoginItem.setEnabled(newValue) {
                                store.settings.launchAtLogin = !newValue
                            }
                        }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// ── Schedule: active hours + the live quiet window ──
private struct ScheduleSettings: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var appState: AppState
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            Section("Active hours") {
                Toggle("Don't force sleep during my active hours", isOn: s.scheduleEnabled)
                HStack {
                    Text("From")
                    Picker("", selection: s.activeHoursStart) {
                        ForEach(0..<24, id: \.self) { Text(ScheduleEngine.hourLabel($0)).tag($0) }
                    }
                    .labelsHidden().accessibilityLabel("Active hours start")
                    Text("to")
                    Picker("", selection: s.activeHoursEnd) {
                        ForEach(0..<24, id: \.self) { Text(ScheduleEngine.hourLabel($0)).tag($0) }
                    }
                    .labelsHidden().accessibilityLabel("Active hours end")
                }
                .disabled(!store.settings.scheduleEnabled)
                if store.settings.scheduleEnabled { scheduleStatusRow }
                Text(
                    "During these hours Decaffeinate stands down — it won't force sleep, so a long task or your own work is never cut off. macOS's own sleep still applies. Set the end earlier than the start for an overnight window."
                )
                .settingsCaption()
            }

            Section("Quiet window") {
                if let until = appState.quietUntil, appState.isQuietWindowActive {
                    HStack {
                        if let paused = appState.quietWindowPausedReason {
                            Label(
                                "Paused — \(paused)", systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(Color.warning)
                        } else {
                            Label(
                                "Holding awake until \(ScheduleEngine.timeLabel(until))",
                                systemImage: "clock.fill")
                        }
                        Spacer()
                        Button("Cancel") { appState.clearQuietWindow() }
                    }
                } else {
                    Text(
                        "No quiet window active. Start one any time from the menu's “Stay awake until…”."
                    )
                    .settingsCaption()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var scheduleStatusRow: some View {
        let st = store.settings
        if st.activeHoursStart == st.activeHoursEnd {
            Label(
                "Start and end are the same — this schedule does nothing.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption).foregroundStyle(Color.warning)
        } else if ScheduleEngine.isWithinActiveHours(
            Date(), start: st.activeHoursStart, end: st.activeHoursEnd)
        {
            Label(
                "Active now — auto-sleep is paused until \(ScheduleEngine.hourLabel(st.activeHoursEnd))",
                systemImage: "pause.circle.fill"
            )
            .font(.caption).foregroundStyle(Color.positive)
        } else {
            Label(
                "Outside active hours — auto-sleep is on. Next pause at \(ScheduleEngine.hourLabel(st.activeHoursStart)).",
                systemImage: "checkmark.circle"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// ── Automation: triggers + per-app rules + strict takeover ──
private struct AutomationSettings: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine
    @State private var newAppName = ""

    var body: some View {
        Form {
            Section("Keep awake while…") {
                if store.settings.triggers.isEmpty {
                    Text(
                        "No triggers yet. Add one below to keep the Mac awake whenever a condition holds — the battery floor and backpack guard still override it."
                    )
                    .settingsCaption()
                }
                ForEach(store.settings.triggers) { rule in
                    HStack(spacing: Space.s2) {
                        Toggle("", isOn: enabledBinding(rule)).labelsHidden()
                            .accessibilityLabel(rule.condition.label)
                        Text(rule.condition.label)
                            .foregroundStyle(rule.enabled ? Color.ink1 : Color.ink4)
                        Spacer()
                        if let reason = appState.activeTriggerReason, rule.enabled, isActive(rule) {
                            HarfPill(label: "Active", variant: .live, dot: true).help(reason)
                        }
                        Button(role: .destructive) {
                            remove(rule)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            Section("Add a trigger") {
                HStack {
                    TextField("App name (e.g. Zoom, Final Cut Pro)", text: $newAppName)
                        .onSubmit(addApp)
                    Button("Add") { addApp() }
                        .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button("While on AC power") { add(.onACPower) }
                Button("While CPU is busy (above 50%)") { add(.cpuAbove(50)) }
            }

            Section("Allowed / blocked apps") {
                if rules.rules.isEmpty {
                    Text("Allow or block apps from the menu and they'll show up here.")
                        .settingsCaption()
                } else {
                    ForEach(rules.rules) { rule in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(rule.displayName)
                                Text(rule.bundleIdentifier ?? rule.processName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            HarfPill(
                                label: rule.policy.shortLabel,
                                variant: rule.policy.isCurrentlyAllowing ? .positive : .neutral)
                            Button(role: .destructive) {
                                rules.remove(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Clear all rules", role: .destructive) { rules.removeAll() }
                }
            }

            Section("AI agents") {
                Toggle(
                    "Auto-sleep when a watched agent finishes",
                    isOn: $store.settings.autoSleepWhenAgentFinishes)
                Text(
                    "When an AI agent (Claude Code, Cursor…) keeps the Mac awake until its task is done, watch it automatically and sleep once it finishes. Otherwise the menu just offers a one-click watch."
                )
                .settingsCaption()
            }

            Section("Strict takeover") {
                Toggle(
                    "Let Decaffeinate own the idle timer", isOn: $store.settings.strictTakeoverMode)
                Text(
                    "Holds a system-sleep assertion so macOS never idle-sleeps on its own — Decaffeinate becomes the only thing that decides when to sleep. If it ever quits, normal macOS sleep resumes automatically."
                )
                .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }

    private func enabledBinding(_ rule: TriggerRule) -> Binding<Bool> {
        Binding(
            get: { store.settings.triggers.first(where: { $0.id == rule.id })?.enabled ?? false },
            set: { newValue in
                if let i = store.settings.triggers.firstIndex(where: { $0.id == rule.id }) {
                    store.settings.triggers[i].enabled = newValue
                }
            })
    }

    private func isActive(_ rule: TriggerRule) -> Bool {
        guard let reason = appState.activeTriggerReason else { return false }
        switch rule.condition {
        case .onACPower: return reason == "On AC power"
        case .cpuAbove: return reason.hasPrefix("CPU is busy")
        case .appRunning(let name): return reason.contains(name)
        }
    }

    private func add(_ condition: TriggerCondition) {
        store.settings.triggers.append(TriggerRule(condition: condition))
    }
    private func addApp() {
        let name = newAppName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        add(.appRunning(name))
        newAppName = ""
    }
    private func remove(_ rule: TriggerRule) {
        store.settings.triggers.removeAll { $0.id == rule.id }
    }
}

// ── Rest & Restart: uptime, the restart recommendation, and the difference
//    between display-off / sleep / shutdown / restart. ──
private struct FreshnessSettings: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var restHistory: RestHistoryStore

    private var adviceColor: Color {
        switch appState.restartAdvice {
        case .fresh: return .positive
        case .consider, .overdue: return .warning
        case .urgent: return .critical
        }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text("Up \(appState.uptimeLabel ?? "—") since last restart")
                        .font(HarfFont.title).foregroundStyle(Color.ink1)
                    Label {
                        Text(
                            RestartAdvisor.message(
                                appState.restartAdvice, uptimeLabel: appState.uptimeLabel ?? "—"))
                    } icon: {
                        Image(systemName: appState.restartAdvice.symbol)
                    }
                    .font(HarfFont.body).foregroundStyle(adviceColor)
                    Text(RestartAdvisor.reason(appState.restartAdvice)).settingsCaption()
                }
                .padding(.vertical, Space.s1)
            }

            Section("Last rest") {
                restRow("Last sleep", restHistory.lastSystemSleep?.date)
                restRow("Last screen rest", restHistory.lastDisplayOff?.date)
                restRow("Last restart", restHistory.lastRestart?.date)
            }

            Section("Recommendation") {
                LabeledSlider(
                    "Recommend a restart after",
                    value: Binding(
                        get: { Double(store.settings.restartRecommendationDays) },
                        set: { store.settings.restartRecommendationDays = Int($0) }),
                    range: 1...30, unit: "days", width: 56)
                Text(
                    "Most experts suggest restarting about weekly. A hard reminder still appears near macOS's ~49-day uptime limit, where networking can fail."
                )
                .settingsCaption()
            }

            Section("What each one does") {
                stateCard(
                    "Display off",
                    "Only the screen sleeps — everything keeps running. Refreshes nothing.")
                stateCard(
                    "Sleep",
                    "Pauses the Mac with your work held in RAM (~0.21 W on Apple silicon). Instant wake — but it doesn't clear memory leaks, caches, or stuck state."
                )
                stateCard(
                    "Restart",
                    "Resets the Mac: clears RAM and caches, resets the kernel, WindowServer and network, and applies pending updates. Sleep can't do this — aim for about weekly."
                )
                stateCard(
                    "Shut down",
                    "Clears everything and powers off — best for long storage or travel. For daily use, sleep + a weekly restart keeps a Mac fresh."
                )
                Text(
                    "A healthy Mac rests: sleep it daily, restart it about weekly. Sources: Apple Support, Macworld, Intego, Eclectic Light, Tom's Hardware."
                )
                .settingsCaption()
            }

            if !restHistory.events.isEmpty {
                Section("Recent activity") {
                    ForEach(restHistory.events.prefix(12)) { event in
                        HStack(spacing: Space.s2) {
                            Image(systemName: event.kind.symbol)
                                .foregroundStyle(Color.ink3).frame(width: 18)
                            Text(event.kind.label).foregroundStyle(Color.ink1)
                            Spacer()
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(Color.ink3)
                        }
                    }
                    Button("Clear activity", role: .destructive) { restHistory.clear() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func restRow(_ label: String, _ date: Date?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(
                date.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: Date()) }
                    ?? "—"
            )
            .foregroundStyle(.secondary)
        }
    }

    private func stateCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(HarfFont.bodyMedium).foregroundStyle(Color.ink1)
            Text(body).settingsCaption()
        }
        .padding(.vertical, 2)
    }
}

// ── History: the forced-sleep log + a rough "wake avoided" estimate ──
private struct HistorySettings: View {
    @EnvironmentObject var history: SleepHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if history.events.isEmpty {
                ContentUnavailableView(
                    "No sleeps yet",
                    systemImage: "moon.zzz",
                    description: Text(
                        "When Decaffeinate forces your Mac to sleep, every one shows up here with the reason."
                    )
                )
            } else {
                VStack(alignment: .leading, spacing: Space.s1) {
                    Text(
                        "\(history.events.count) forced sleep\(history.events.count == 1 ? "" : "s") · \(history.batteryCount) on battery"
                    )
                    .font(HarfFont.title).foregroundStyle(Color.ink1)
                    Text(
                        "≈ \(history.estimatedMinutesAvoided) min of needless wake avoided (rough estimate)."
                    )
                    .font(.caption).foregroundStyle(Color.ink3)
                }
                .padding(Space.s4)
                Hairline()
                List {
                    ForEach(history.events) { event in
                        HStack(spacing: Space.s2) {
                            Image(systemName: event.onBattery ? "battery.50" : "powerplug")
                                .foregroundStyle(Color.ink3).frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.reason).foregroundStyle(Color.ink1).lineLimit(1)
                                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(Color.ink3)
                            }
                            Spacer()
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear history", role: .destructive) { history.clear() }.padding(8)
                }
            }
        }
    }
}

private struct AboutView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        VStack(spacing: Space.s3) {
            DecaffeinateMark(size: 64)
            Text("Decaffeinate").font(HarfFont.h2).foregroundStyle(Color.ink1)
            Text("The truth about what's keeping your Mac awake — and the power to make it sleep.")
                .font(HarfFont.lede)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            softwareUpdate

            Link(
                "github.com/harf-promo/decaffeinate",
                destination: URL(string: "https://github.com/harf-promo/decaffeinate")!
            )
            .font(HarfFont.caption).tint(Color.accentText)
            Button("Show welcome again") {
                OnboardingPresenter.shared.present(settingsStore: appState.settingsStore)
            }
            .buttonStyle(.link).font(HarfFont.caption).tint(Color.ink2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.s5)
    }

    @ViewBuilder private var softwareUpdate: some View {
        VStack(spacing: Space.s2) {
            Text("Version \(AppInfo.version)").eyebrow(.ink4)
            if updater.isAvailable {
                if updater.updateAvailable {
                    Label("An update is available", systemImage: "arrow.down.circle.fill")
                        .font(HarfFont.caption).foregroundStyle(Color.positive)
                }
                Text("Last checked: \(lastChecked)")
                    .font(HarfFont.caption).foregroundStyle(Color.ink3)
                Button("Check for Updates…") { updater.checkForUpdatesUserInitiated() }
                    .padding(.top, 2)
                Toggle("Automatically check for updates", isOn: $updater.automaticChecksEnabled)
                    .font(HarfFont.caption).fixedSize()
            }
        }
        .padding(.vertical, Space.s2)
    }

    private var lastChecked: String {
        guard let date = updater.lastCheckedAt else { return "Never" }
        return Format.relative(since: date)
    }
}

// ── A labeled slider with a trailing value — used across the settings forms. ──
private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var unit: String
    var enabled: Bool = true
    var width: CGFloat = 52

    init(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double = 1,
        unit: String, enabled: Bool = true, width: CGFloat = 52
    ) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.enabled = enabled
        self.width = width
    }

    var body: some View {
        HStack {
            Text(title)
            Slider(value: $value, in: range, step: step)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) \(unit)")
            Text("\(Int(value)) \(unit)").monospacedDigit().frame(
                width: width, alignment: .trailing)
        }
        .disabled(!enabled)
    }
}

extension View {
    /// The muted caption under a settings control — one consistent voice.
    fileprivate func settingsCaption() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

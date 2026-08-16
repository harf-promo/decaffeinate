import KeyboardShortcuts
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
            sidebarLabel(L10n.localized("Settings"))
            ForEach([SettingsPane.general, .notifications, .schedule, .automation, .freshness]) {
                sidebarRow($0)
            }
            sidebarLabel(L10n.localized("Info")).padding(.top, Space.s3)
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
                Text(L10n.localized(item.title))
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
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
        case .notifications: NotificationsSettings()
        case .schedule: ScheduleSettings()
        case .automation: AutomationSettings()
        case .freshness: FreshnessSettings()
        case .history: HistorySettings()
        case .about: AboutView()
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, notifications, schedule, automation, freshness, history, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .notifications: return "Notifications"
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
        case .notifications: return "bell"
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
            Section {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.localized("Decaffeinate makes your idle Mac sleep."))
                        .font(.system(size: 13, weight: .semibold))
                    Text(
                        L10n.localized(
                            "You're in control: it forces sleep when you step away, and shows you exactly what's holding it awake."
                        )
                    )
                    .settingsCaption()
                }
            }

            Section(L10n.localized("Put the Mac to sleep")) {
                Toggle(L10n.localized("Auto-sleep when left idle"), isOn: s.decaffeinateEnabled)
                LabeledSlider(
                    L10n.localized("Sleep after"), value: s.idleThresholdMinutes, range: 1...60,
                    unit: L10n.localized("min"), enabled: store.settings.decaffeinateEnabled)
                Text(
                    L10n.localized(
                        "When you step away, Decaffeinate forces sleep after this much idle time — even if an app is trying to keep the Mac awake."
                    )
                )
                .settingsCaption()
                if store.settings.idleThresholdMinutes < 3 {
                    Text(
                        L10n.localized(
                            "Very short — your Mac may sleep while you\u{2019}re still reading.")
                    )
                    .font(.caption).foregroundStyle(Color.warning)
                }

                Toggle(
                    L10n.localized("Warn before sleeping, with time to stay awake"),
                    isOn: s.showPreSleepWarning
                )
                .disabled(!store.settings.decaffeinateEnabled)
                Text(
                    L10n.localized(
                        "Shows a brief on-screen countdown with a \u{201C}Stay awake\u{201D} button before an idle sleep actually happens. Turn this off to sleep immediately, like before."
                    )
                )
                .settingsCaption()

                Toggle(L10n.localized("Sleep sooner on battery"), isOn: s.sleepSoonerOnBattery)
                    .disabled(!store.settings.decaffeinateEnabled)
                LabeledSlider(
                    L10n.localized("On battery, sleep after"),
                    value: s.batteryIdleThresholdMinutes, range: 1...30,
                    unit: L10n.localized("min"),
                    enabled: store.settings.decaffeinateEnabled
                        && store.settings.sleepSoonerOnBattery
                )
                if store.settings.sleepSoonerOnBattery,
                    store.settings.batteryIdleThresholdMinutes
                        >= store.settings.idleThresholdMinutes
                {
                    Text(
                        L10n.localized(
                            "This is at least your normal idle time, so it has no effect — lower it to sleep sooner on battery."
                        )
                    )
                    .font(.caption).foregroundStyle(Color.warning)
                }

                KeyboardShortcuts.Recorder(
                    L10n.localized("Global \u{201C}Sleep Now\u{201D} hotkey"), name: .sleepNow)
                Text(
                    L10n.localized(
                        "Set a system-wide shortcut to put the Mac to sleep from any app.")
                )
                .settingsCaption()

                KeyboardShortcuts.Recorder(
                    L10n.localized("Global \u{201C}Toggle keep awake\u{201D} hotkey"),
                    name: .toggleKeepAwake)
                Text(
                    L10n.localized(
                        "Set a system-wide shortcut to turn keep-awake on or off from any app.")
                )
                .settingsCaption()
            }

            Section(L10n.localized("Never sleep at a bad moment")) {
                Text(
                    L10n.localized(
                        "Won't interrupt calls, media, backups, updates, or apps you allowed.")
                )
                .settingsCaption()
                DisclosureGroup(L10n.localized("Advanced \u{2014} choose which")) {
                    Toggle(
                        L10n.localized("Pause during calls (microphone)"),
                        isOn: s.pauseForActiveCall)
                    Toggle(L10n.localized("Pause for active media"), isOn: s.pauseForActiveMedia)
                    Toggle(
                        L10n.localized("Pause during Time Machine backups"),
                        isOn: s.pauseForTimeMachine)
                    Toggle(
                        L10n.localized("Pause during macOS updates"), isOn: s.pauseForSystemUpdate)
                    Toggle(
                        L10n.localized("Respect apps set to \u{201C}Always allow\u{201D}"),
                        isOn: s.respectWhitelist
                    )
                    Text(
                        L10n.localized(
                            "The call guard is never time-limited. Media holds are released after you've been idle well past your sleep delay, so a forgotten background tab can't keep the Mac awake forever."
                        )
                    )
                    .settingsCaption()
                }
            }

            Section(L10n.localized("Battery & heat")) {
                LabeledSlider(
                    L10n.localized("Battery floor"),
                    value: Binding(
                        get: { Double(store.settings.batteryFloorPercent) },
                        set: { store.settings.batteryFloorPercent = Int($0) }),
                    range: 0...50, step: 5, unit: "%", width: 44)
                Text(
                    L10n.localized(
                        "The charge level where keep-awake gives up, so you never wake to a dead laptop."
                    )
                )
                .settingsCaption()
                Toggle(
                    L10n.localized("Sleep if it overheats in a bag (backpack guard)"),
                    isOn: s.thermalGuardEnabled)
                Text(
                    L10n.localized(
                        "Sleeps immediately if the Mac overheats while enclosed (e.g. in a bag) — all keep-awake holds are released."
                    )
                )
                .settingsCaption()
            }

            Section(L10n.localized("Keep awake (optional)")) {
                Toggle(L10n.localized("Hold the Mac awake on purpose"), isOn: s.caffeinateEnabled)
                Toggle(
                    L10n.localized("Also keep the display on"), isOn: s.caffeinateKeepsDisplayAwake
                )
                .disabled(!store.settings.caffeinateEnabled)
            }

            Section(L10n.localized("Startup & menu bar")) {
                if LoginItem.isAvailable {
                    Toggle(L10n.localized("Launch at login"), isOn: s.launchAtLogin)
                        .onChange(of: store.settings.launchAtLogin) { _, newValue in
                            // No-op when the OS already matches (the onAppear
                            // reconcile writes the live value back through this
                            // handler; re-registering can throw and would then
                            // wrongly flip the user's login item off).
                            if LoginItem.isEnabled == newValue { return }
                            // Revert the toggle if SMAppService registration fails
                            // so it always reflects the actual login-item state.
                            if !LoginItem.setEnabled(newValue) {
                                store.settings.launchAtLogin = !newValue
                            }
                        }
                        .onAppear {
                            // The OS owns this state (System Settings → Login
                            // Items can flip it behind our back) — reconcile the
                            // cached setting with the live status on every open.
                            if let live = LoginItem.isEnabled,
                                live != store.settings.launchAtLogin
                            {
                                store.settings.launchAtLogin = live
                            }
                        }
                }
                Toggle(
                    L10n.localized("Show the sleep countdown in the menu bar"),
                    isOn: s.showMenuBarCountdown)
                Toggle(
                    L10n.localized("Show the holder count in the menu bar"),
                    isOn: s.showHolderCountInMenuBar)
                Text(
                    L10n.localized(
                        "Shows how many apps are currently holding the Mac awake next to the icon."
                    )
                )
                .settingsCaption()
            }
        }
        .formStyle(.grouped)
    }
}

// ── Notifications: its own pane (split out of General — it earned the room:
//    4 toggles plus the live permission-repair status row post-v1.22). ──
private struct NotificationsSettings: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var appState: AppState
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            if appState.notificationAuthorization == .denied {
                Section {
                    HStack {
                        Label(L10n.localized("Notifications: Off"), systemImage: "bell.slash.fill")
                            .foregroundStyle(Color.warning)
                        Spacer()
                        Button(L10n.localized("Enable\u{2026}")) {
                            Notifier.openSystemNotificationSettings()
                        }
                    }
                    Text(
                        L10n.localized(
                            "Decaffeinate can\u{2019}t notify you until notifications are turned back on in System Settings \u{2014} the toggles below have nothing to post to."
                        )
                    )
                    .settingsCaption()
                }
            }
            Section(L10n.localized("Tell me when\u{2026}")) {
                Toggle(L10n.localized("A new app keeps the Mac awake"), isOn: s.notifyOnNewBlocker)
                Toggle(
                    L10n.localized("Decaffeinate puts the Mac to sleep"),
                    isOn: s.notifyOnForcedSleep)
                Toggle(
                    L10n.localized("A watched agent or build finishes"),
                    isOn: s.notifyOnAgentFinished)
                Toggle(L10n.localized("A restart is overdue"), isOn: s.notifyOnRestartOverdue)
            }
        }
        .formStyle(.grouped)
        .onAppear { appState.refreshNotificationAuthorization() }
    }
}

// ── Schedule: active hours + the live quiet window ──
private struct ScheduleSettings: View {
    @EnvironmentObject var store: SettingsStore
    @EnvironmentObject var appState: AppState
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            Section(L10n.localized("Active hours")) {
                Toggle(
                    L10n.localized("Don't force sleep during my active hours"),
                    isOn: s.scheduleEnabled)
                HStack {
                    Text(L10n.localized("From"))
                    Picker("", selection: s.activeHoursStart) {
                        ForEach(0..<24, id: \.self) { Text(ScheduleEngine.hourLabel($0)).tag($0) }
                    }
                    .labelsHidden().accessibilityLabel(L10n.localized("Active hours start"))
                    Text(L10n.localized("to"))
                    Picker("", selection: s.activeHoursEnd) {
                        ForEach(0..<24, id: \.self) { Text(ScheduleEngine.hourLabel($0)).tag($0) }
                    }
                    .labelsHidden().accessibilityLabel(L10n.localized("Active hours end"))
                }
                .disabled(!store.settings.scheduleEnabled)
                if store.settings.scheduleEnabled { scheduleStatusRow }
                Text(
                    L10n.localized(
                        "During these hours Decaffeinate stands down — it won't force sleep, so a long task or your own work is never cut off. macOS's own sleep still applies. Set the end earlier than the start for an overnight window."
                    )
                )
                .settingsCaption()
            }

            Section(L10n.localized("Quiet window")) {
                if let until = appState.quietUntil, appState.isQuietWindowActive {
                    HStack {
                        if let paused = appState.quietWindowPausedReason {
                            Label(
                                L10n.localized("Paused — %@", paused),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(Color.warning)
                        } else {
                            Label(
                                L10n.localized(
                                    "Holding awake until %@", ScheduleEngine.timeLabel(until)),
                                systemImage: "clock.fill")
                        }
                        Spacer()
                        Button(L10n.localized("Cancel")) { appState.clearQuietWindow() }
                    }
                } else {
                    Text(
                        L10n.localized(
                            "No quiet window active. Start one any time from the menu's “Stay awake until…”."
                        )
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
                L10n.localized("Start and end are the same — this schedule does nothing."),
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption).foregroundStyle(Color.warning)
        } else if ScheduleEngine.isWithinActiveHours(
            Date(), start: st.activeHoursStart, end: st.activeHoursEnd)
        {
            Label(
                L10n.localized(
                    "Active now — auto-sleep is paused until %@",
                    ScheduleEngine.hourLabel(st.activeHoursEnd)),
                systemImage: "pause.circle.fill"
            )
            .font(.caption).foregroundStyle(Color.positive)
        } else {
            Label(
                L10n.localized(
                    "Outside active hours — auto-sleep is on. Next pause at %@.",
                    ScheduleEngine.hourLabel(st.activeHoursStart)),
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
    @State private var cpuThreshold: Double = 50

    var body: some View {
        Form {
            Section(L10n.localized("Keep awake while…")) {
                if store.settings.triggers.isEmpty {
                    Text(
                        L10n.localized(
                            "No triggers yet. Add one below to keep the Mac awake whenever a condition holds — the battery floor and backpack guard still override it."
                        )
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
                            HarfPill(label: L10n.localized("Active"), variant: .live, dot: true)
                                .help(reason)
                        }
                        Button(role: .destructive) {
                            remove(rule)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(
                            L10n.localized("Remove trigger: %@", rule.condition.label))
                    }
                }
            }

            Section(L10n.localized("Add a trigger")) {
                HStack {
                    TextField(
                        L10n.localized("App name (e.g. Zoom, Final Cut Pro)"), text: $newAppName
                    )
                    .onSubmit(addApp)
                    Button(L10n.localized("Add")) { addApp() }
                        .disabled(newAppName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Button(L10n.localized("While on AC power")) { add(.onACPower) }
                VStack(alignment: .leading, spacing: Space.s1) {
                    HStack {
                        LabeledSlider(
                            L10n.localized("Keep awake when CPU above"),
                            value: $cpuThreshold,
                            range: 10...90, step: 5, unit: "%", width: 44)
                        Button(L10n.localized("Add")) { add(.cpuAbove(Int(cpuThreshold))) }
                            .buttonStyle(HarfButtonStyle(variant: .ghost, size: .small))
                            .fixedSize()
                            .disabled(hasCpuAboveTrigger)
                    }
                    Text(
                        hasCpuAboveTrigger
                            ? L10n.localized(
                                "A CPU trigger is already active — remove it first to change the threshold."
                            )
                            : L10n.localized(
                                "Holds the Mac awake while any process pushes total CPU above this threshold. The battery floor and backpack guard still override it."
                            )
                    )
                    .settingsCaption()
                }
            }

            Section(L10n.localized("App sleep permissions")) {
                Text(
                    L10n.localized(
                        "Choices you\u{2019}ve made from the menu. "
                            + "\u{201C}Always allow\u{201D} lets an app hold the Mac awake; "
                            + "\u{201C}Sleep anyway\u{201D} makes Decaffeinate force sleep regardless."
                    )
                )
                .settingsCaption()
                if rules.rules.isEmpty {
                    Text(
                        L10n.localized(
                            "Choose \u{201C}Always allow\u{201D} or \u{201C}Sleep anyway\u{201D} "
                                + "for an app from the menu and it\u{2019}ll show up here."
                        )
                    )
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
                                label: L10n.localized(rule.policy.shortLabel),
                                variant: rule.policy.isCurrentlyAllowing ? .positive : .neutral)
                            Button(role: .destructive) {
                                rules.remove(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(L10n.localized("Remove rule: %@", rule.displayName))
                        }
                    }
                    ConfirmableDestructiveButton(
                        title: L10n.localized("Clear all rules"),
                        confirmLabel: L10n.localized("Clear all rules"),
                        message: L10n.localized(
                            "Remove every app sleep permission? This can\u{2019}t be undone.")
                    ) { rules.removeAll() }
                }
            }

            Section(L10n.localized("AI agents")) {
                Toggle(
                    L10n.localized("Auto-sleep when a watched agent finishes"),
                    isOn: $store.settings.autoSleepWhenAgentFinishes)
                Text(
                    L10n.localized(
                        "When an AI agent (Claude Code, Cursor…) keeps the Mac awake until its task is done, watch it automatically and sleep once it finishes. Otherwise the menu just offers a one-click watch."
                    )
                )
                .settingsCaption()
            }

            // Marked "Advanced" — the audit called this the single most
            // behavior-altering toggle in the app, and it used to look like
            // any other switch on the page.
            Section {
                Toggle(
                    L10n.localized("Let Decaffeinate decide every sleep"),
                    isOn: $store.settings.strictTakeoverMode)
                Text(
                    L10n.localized(
                        "Decaffeinate becomes the only thing that decides when your Mac sleeps — macOS won't idle-sleep on its own. If Decaffeinate ever quits, normal sleep resumes automatically."
                    )
                )
                .settingsCaption()
            } header: {
                HStack(spacing: Space.s2) {
                    Text(L10n.localized("Take full control of sleep"))
                    HarfPill(label: L10n.localized("Advanced"), variant: .warning)
                }
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

    private var hasCpuAboveTrigger: Bool {
        store.settings.triggers.contains {
            if case .cpuAbove = $0.condition { return true }
            return false
        }
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
    @State private var lastWakeReason: String?

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
                    Text(L10n.localized("Up %@ since last restart", appState.uptimeLabel ?? "—"))
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

            Section(L10n.localized("Last rest")) {
                restRow(L10n.localized("Last sleep"), restHistory.lastSystemSleep?.date)
                restRow(L10n.localized("Last screen rest"), restHistory.lastDisplayOff?.date)
                restRow(L10n.localized("Last restart"), restHistory.lastRestart?.date)
                if let wake = lastWakeReason {
                    HStack {
                        Text(L10n.localized("Last wake"))
                        Spacer()
                        Text(wake).foregroundStyle(Color.ink2)
                    }
                }
            }

            if let digest = appState.restDigest {
                Section(L10n.localized("While you were away")) {
                    Label(digest, systemImage: "moon.stars")
                        .font(HarfFont.body).foregroundStyle(Color.ink2)
                }
            }

            Section(L10n.localized("Recommendation")) {
                LabeledSlider(
                    L10n.localized("Recommend a restart after"),
                    value: Binding(
                        get: { Double(store.settings.restartRecommendationDays) },
                        set: { store.settings.restartRecommendationDays = Int($0) }),
                    range: 1...30, unit: L10n.localized("days"), width: 56)
                Text(
                    L10n.localized(
                        "Most experts suggest restarting about weekly. A hard reminder still appears near macOS's ~49-day uptime limit, where networking can fail."
                    )
                )
                .settingsCaption()
            }

            Section(L10n.localized("What each one does")) {
                stateCard(
                    L10n.localized("Display off"),
                    L10n.localized(
                        "Only the screen sleeps — everything keeps running. Refreshes nothing."))
                stateCard(
                    L10n.localized("Sleep"),
                    L10n.localized(
                        "Pauses the Mac with your work held in RAM (~0.21 W on Apple silicon). Instant wake — but it doesn't clear memory leaks, caches, or stuck state."
                    )
                )
                stateCard(
                    L10n.localized("Restart"),
                    L10n.localized(
                        "Resets the Mac: clears RAM and caches, resets the kernel, WindowServer and network, and applies pending updates. Sleep can't do this — aim for about weekly."
                    )
                )
                stateCard(
                    L10n.localized("Shut down"),
                    L10n.localized(
                        "Clears everything and powers off — best for long storage or travel. For daily use, sleep + a weekly restart keeps a Mac fresh."
                    )
                )
                Text(
                    L10n.localized(
                        "A healthy Mac rests: sleep it daily, restart it about weekly. Sources: Apple Support, Macworld, Intego, Eclectic Light, Tom's Hardware."
                    )
                )
                .settingsCaption()
            }

            if !restHistory.events.isEmpty {
                Section(L10n.localized("Recent activity")) {
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
                    ConfirmableDestructiveButton(
                        title: L10n.localized("Clear activity"),
                        confirmLabel: L10n.localized("Clear activity"),
                        message: L10n.localized(
                            "Clear the recent rest activity log? This can\u{2019}t be undone.")
                    ) { restHistory.clear() }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // Best-effort: resolve the last wake reason from pmset off the main
            // actor. Nil when unavailable — the row just doesn't appear.
            lastWakeReason = await appState.latestWakeReason()
        }
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

// ── History: the forced-sleep log + a rough "wake avoided" estimate, plus a
//    "which app held your Mac awake longest this week" ranked list. ──
private struct HistorySettings: View {
    @EnvironmentObject var history: SleepHistoryStore
    @EnvironmentObject var awakeTime: AwakeTimeStore

    /// App name → total held seconds over the last 7 days, ranked highest-first.
    private var weeklyRanking: [(appName: String, seconds: TimeInterval)] {
        awakeTime.weeklyRanking()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if history.events.isEmpty && weeklyRanking.isEmpty {
                ContentUnavailableView(
                    L10n.localized("No history yet"),
                    systemImage: "moon.zzz",
                    description: Text(
                        L10n.localized(
                            "When Decaffeinate forces your Mac to sleep, or an app holds it awake, it shows up here."
                        )
                    )
                )
            } else {
                if !history.events.isEmpty {
                    VStack(alignment: .leading, spacing: Space.s1) {
                        Text(
                            history.events.count == 1
                                ? L10n.localized(
                                    "1 forced sleep · %d on battery", history.batteryCount)
                                : L10n.localized(
                                    "%d forced sleeps · %d on battery", history.events.count,
                                    history.batteryCount)
                        )
                        .font(HarfFont.title).foregroundStyle(Color.ink1)
                        Text(
                            L10n.localized(
                                "≈ %d min of measured sleep started by Decaffeinate.",
                                history.measuredMinutesAsleep)
                        )
                        .font(.caption).foregroundStyle(Color.ink3)
                        if history.unmeasuredSleepCount > 0 {
                            Text(
                                history.unmeasuredSleepCount == 1
                                    ? L10n.localized("1 sleep not yet measured.")
                                    : L10n.localized(
                                        "%d sleeps not yet measured.",
                                        history.unmeasuredSleepCount)
                            )
                            .font(.caption).foregroundStyle(Color.ink3)
                        }
                    }
                    .padding(Space.s4)
                    Hairline()
                }
                // One List with two Sections (rather than two separate scroll
                // regions) so both the forced-sleep log and the weekly ranking
                // share the same scrollable area within the fixed-size window.
                List {
                    if !history.events.isEmpty {
                        Section(L10n.localized("Forced sleeps")) {
                            ForEach(history.events) { event in
                                HStack(spacing: Space.s2) {
                                    Image(systemName: event.onBattery ? "battery.50" : "powerplug")
                                        .foregroundStyle(Color.ink3).frame(width: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(event.reason).foregroundStyle(Color.ink1).lineLimit(1)
                                        Text(
                                            event.date.formatted(
                                                date: .abbreviated, time: .shortened)
                                        )
                                        .font(.caption).foregroundStyle(Color.ink3)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    if !weeklyRanking.isEmpty {
                        Section(L10n.localized("This week \u{2014} longest awake")) {
                            ForEach(weeklyRanking, id: \.appName) { entry in
                                HStack(spacing: Space.s2) {
                                    Image(systemName: "hourglass")
                                        .foregroundStyle(Color.ink3).frame(width: 18)
                                    Text(entry.appName).foregroundStyle(Color.ink1).lineLimit(1)
                                    Spacer()
                                    Text(Format.duration(entry.seconds))
                                        .font(.caption).foregroundStyle(Color.ink3)
                                }
                            }
                        }
                    }
                }
                HStack(spacing: Space.s3) {
                    Spacer()
                    if !weeklyRanking.isEmpty {
                        ConfirmableDestructiveButton(
                            title: L10n.localized("Clear weekly awake time"),
                            confirmLabel: L10n.localized("Clear weekly awake time"),
                            message: L10n.localized(
                                "Clear the weekly awake-time tally? This can\u{2019}t be undone.")
                        ) { awakeTime.clear() }
                    }
                    if !history.events.isEmpty {
                        ConfirmableDestructiveButton(
                            title: L10n.localized("Clear history"),
                            confirmLabel: L10n.localized("Clear history"),
                            message: L10n.localized(
                                "Clear the forced-sleep history? This can\u{2019}t be undone.")
                        ) { history.clear() }
                    }
                }
                .padding(8)
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
            Text("Decaffeinate").scaledFont(20, weight: .semibold, relativeTo: .title)
                .foregroundStyle(Color.ink1)
            Text(
                L10n.localized(
                    "The truth about what's keeping your Mac awake — and the power to make it sleep."
                )
            )
            .scaledFont(15)
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

            // Quiet discoverability line — the app's 4 Shortcuts/Siri intents
            // (Sleep Now, what's keeping it awake, keep awake, stop) otherwise
            // have no in-app mention at all. A fact, not a marketing banner.
            VStack(spacing: 2) {
                Text(L10n.localized("Works with Shortcuts & Siri"))
                    .font(HarfFont.caption).foregroundStyle(Color.ink2)
                Text(
                    L10n.localized(
                        "Sleep Now, keep-awake, and \u{201C}what\u{2019}s keeping it awake\u{201D} are available as Shortcuts actions and Siri phrases."
                    )
                )
                .font(.caption2).foregroundStyle(Color.ink4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Space.s5)
            }

            Button(L10n.localized("Show welcome again")) {
                OnboardingPresenter.shared.present(settingsStore: appState.settingsStore)
            }
            .buttonStyle(.link).font(HarfFont.caption).tint(Color.ink2)
            Button(L10n.localized("Copy diagnostics")) { appState.copyDiagnostics() }
                .buttonStyle(.link).font(HarfFont.caption).tint(Color.ink2)
                .help(
                    L10n.localized("Copy settings, rules, and the current scan for a bug report."))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.s5)
    }

    @ViewBuilder private var softwareUpdate: some View {
        VStack(spacing: Space.s2) {
            Text(L10n.localized("Version %@", AppInfo.version)).eyebrow(.ink4)
            if updater.isAvailable {
                updateStatusRow
                Toggle(
                    L10n.localized("Automatically check for updates"),
                    isOn: $updater.automaticChecksEnabled
                )
                .font(HarfFont.caption).fixedSize()
            }
        }
        .padding(.vertical, Space.s2)
    }

    @ViewBuilder private var updateStatusRow: some View {
        switch updater.state {
        case .idle:
            VStack(spacing: Space.s1) {
                if updater.lastCheckedAt == nil {
                    Text(L10n.localized("Not checked yet"))
                        .font(HarfFont.caption).foregroundStyle(Color.ink3)
                } else {
                    Text(L10n.localized("Last checked: %@", lastChecked))
                        .font(HarfFont.caption).foregroundStyle(Color.ink3)
                }
                Button(L10n.localized("Check for Updates…")) {
                    updater.checkForUpdatesUserInitiated()
                }
                .padding(.top, 2)
            }
        case .checking:
            HStack(spacing: Space.s2) {
                ProgressView().scaleEffect(0.7)
                HarfPill(label: L10n.localized("Checking"), variant: .info)
            }
            .frame(minHeight: 32)
        case .upToDate:
            VStack(spacing: Space.s1) {
                HStack(spacing: Space.s2) {
                    HarfPill(label: L10n.localized("Up to date"), variant: .positive, dot: true)
                    Text(L10n.localized("· %@", lastChecked))
                        .font(HarfFont.caption).foregroundStyle(Color.ink3)
                }
                Text(L10n.localized("%@ is the latest signed release", AppInfo.version))
                    .font(HarfFont.caption).foregroundStyle(Color.ink3)
                Button(L10n.localized("Check for Updates…")) {
                    updater.checkForUpdatesUserInitiated()
                }
                .padding(.top, 2)
            }
        case .updateAvailable:
            VStack(spacing: Space.s1) {
                HarfPill(
                    label: updater.availableVersion.map {
                        L10n.localized("%@ is available", $0)
                    } ?? L10n.localized("Update available"),
                    variant: .warning, dot: true)
                Button(L10n.localized("Install Update…")) { updater.checkForUpdatesUserInitiated() }
                    .padding(.top, 2)
            }
        case .failed(let reason):
            VStack(spacing: Space.s1) {
                HarfPill(label: L10n.localized("Couldn't check"), variant: .critical, dot: true)
                    .help(reason)
                    .accessibilityLabel(L10n.localized("Update check failed: %@", reason))
                Text(reason)
                    .font(HarfFont.caption).foregroundStyle(Color.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.s2) {
                    Button(L10n.localized("Try Again")) { updater.checkForUpdatesUserInitiated() }
                    Button(L10n.localized("Open Releases")) { updater.openReleases() }
                }
                .padding(.top, 2)
            }
        }
    }

    private var lastChecked: String {
        guard let date = updater.lastCheckedAt else { return L10n.localized("Never") }
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

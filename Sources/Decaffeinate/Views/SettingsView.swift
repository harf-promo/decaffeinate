import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "zzz") }
            SafetySettings()
                .tabItem { Label("Safety", systemImage: "shield.lefthalf.filled") }
            ScheduleSettings()
                .tabItem { Label("Schedule", systemImage: "calendar") }
            RulesSettings()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            HistorySettings()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            AdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 400)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject var store: SettingsStore
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            Section("Decaffeinate — put the Mac to sleep") {
                Toggle("Auto-sleep when left idle", isOn: s.decaffeinateEnabled)
                HStack {
                    Text("Sleep after")
                    Slider(value: s.idleThresholdMinutes, in: 1...60, step: 1)
                        .accessibilityLabel("Sleep after")
                        .accessibilityValue("\(Int(store.settings.idleThresholdMinutes)) minutes")
                    Text("\(Int(store.settings.idleThresholdMinutes)) min")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(!store.settings.decaffeinateEnabled)
                Text(
                    "When you step away, Decaffeinate forces sleep after this much idle time — even if an app is trying to keep the Mac awake."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Sleep sooner on battery", isOn: s.sleepSoonerOnBattery)
                    .disabled(!store.settings.decaffeinateEnabled)
                HStack {
                    Text("On battery, sleep after")
                    Slider(value: s.batteryIdleThresholdMinutes, in: 1...30, step: 1)
                        .accessibilityLabel("On battery, sleep after")
                        .accessibilityValue(
                            "\(Int(store.settings.batteryIdleThresholdMinutes)) minutes")
                    Text("\(Int(store.settings.batteryIdleThresholdMinutes)) min")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                .disabled(
                    !store.settings.decaffeinateEnabled || !store.settings.sleepSoonerOnBattery)
                if store.settings.sleepSoonerOnBattery,
                    store.settings.batteryIdleThresholdMinutes
                        >= store.settings.idleThresholdMinutes
                {
                    Text(
                        "This is at least your normal idle time, so it has no effect — lower it to sleep sooner on battery."
                    )
                    .font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Keep awake (optional)") {
                Toggle("Hold the Mac awake on purpose", isOn: s.caffeinateEnabled)
                Toggle("Also keep the display on", isOn: s.caffeinateKeepsDisplayAwake)
                    .disabled(!store.settings.caffeinateEnabled)
            }

            Section {
                Toggle("Notify me when a new app keeps the Mac awake", isOn: s.notifyOnNewBlocker)
                Toggle("Show the countdown in the menu bar", isOn: s.showMenuBarCountdown)
                if LoginItem.isAvailable {
                    Toggle("Launch at login", isOn: s.launchAtLogin)
                        .onChange(of: store.settings.launchAtLogin) { _, newValue in
                            LoginItem.setEnabled(newValue)
                        }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SafetySettings: View {
    @EnvironmentObject var store: SettingsStore
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            Section("Never sleep at a bad moment") {
                Toggle("Pause while the microphone is in use (calls)", isOn: s.pauseForActiveCall)
                Toggle("Pause for active media", isOn: s.pauseForActiveMedia)
                Toggle("Pause during Time Machine backups", isOn: s.pauseForTimeMachine)
                Toggle("Pause during macOS updates", isOn: s.pauseForSystemUpdate)
                Toggle("Respect apps I've allowed", isOn: s.respectWhitelist)
                Text(
                    "The call guard is never time-limited. Media holds are released after you've been idle well past your sleep delay, so a forgotten background tab can't keep the Mac awake forever."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            Section("Battery & heat") {
                HStack {
                    Text("Battery floor")
                    Slider(
                        value: Binding(
                            get: { Double(store.settings.batteryFloorPercent) },
                            set: { store.settings.batteryFloorPercent = Int($0) }
                        ), in: 0...50, step: 5
                    )
                    .accessibilityLabel("Battery floor")
                    .accessibilityValue("\(store.settings.batteryFloorPercent) percent")
                    Text("\(store.settings.batteryFloorPercent)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                Text("On battery, keep-awake holds are dropped below this charge.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Backpack guard (sleep if overheating)", isOn: s.thermalGuardEnabled)
                Text(
                    "If the Mac gets thermally stressed — e.g. lid closed in a bag — all keep-awake holds are released and it sleeps immediately."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct RulesSettings: View {
    @EnvironmentObject var rules: RulesEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if rules.rules.isEmpty {
                ContentUnavailableView(
                    "No rules yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Allow or block apps from the menu and they'll show up here.")
                )
            } else {
                List {
                    ForEach(rules.rules) { rule in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(rule.displayName).font(.body)
                                Text(rule.bundleIdentifier ?? rule.processName)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(rule.policy.shortLabel)
                                .font(.caption)
                                .foregroundStyle(rule.policy.isCurrentlyAllowing ? .green : .orange)
                            Button(role: .destructive) {
                                rules.remove(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear all rules", role: .destructive) { rules.removeAll() }
                        .padding(8)
                }
            }
        }
    }
}

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
                    .labelsHidden()
                    .accessibilityLabel("Active hours start")
                    Text("to")
                    Picker("", selection: s.activeHoursEnd) {
                        ForEach(0..<24, id: \.self) { Text(ScheduleEngine.hourLabel($0)).tag($0) }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Active hours end")
                }
                .disabled(!store.settings.scheduleEnabled)
                if store.settings.scheduleEnabled {
                    scheduleStatusRow
                }
                Text(
                    "During these hours Decaffeinate stands down — it won't force sleep, so a long task or your own work is never cut off. macOS's own sleep still applies. Set the end earlier than the start for an overnight window."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            Section("Quiet window") {
                if let until = appState.quietUntil, appState.isQuietWindowActive {
                    HStack {
                        if let paused = appState.quietWindowPausedReason {
                            Label(
                                "Paused — \(paused)", systemImage: "exclamationmark.triangle.fill"
                            )
                            .foregroundStyle(.orange)
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
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// A live read of whether the schedule is suppressing sleep right now, plus a
    /// warning when start == end makes the window a no-op.
    @ViewBuilder private var scheduleStatusRow: some View {
        let st = store.settings
        if st.activeHoursStart == st.activeHoursEnd {
            Label(
                "Start and end are the same — this schedule does nothing.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption).foregroundStyle(.orange)
        } else if ScheduleEngine.isWithinActiveHours(
            Date(), start: st.activeHoursStart, end: st.activeHoursEnd)
        {
            Label(
                "Active now — auto-sleep is paused until \(ScheduleEngine.hourLabel(st.activeHoursEnd))",
                systemImage: "pause.circle.fill"
            )
            .font(.caption).foregroundStyle(.tint)
        } else {
            Label(
                "Outside active hours — auto-sleep is on. Next pause at \(ScheduleEngine.hourLabel(st.activeHoursStart)).",
                systemImage: "checkmark.circle"
            )
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct AdvancedSettings: View {
    @EnvironmentObject var store: SettingsStore
    private var s: Binding<DecaffeinateSettings> { $store.settings }

    var body: some View {
        Form {
            Section("Strict takeover") {
                Toggle("Let Decaffeinate own the idle timer", isOn: s.strictTakeoverMode)
                Text(
                    "Holds a system-sleep assertion so macOS never idle-sleeps on its own — Decaffeinate becomes the only thing that decides when to sleep. If it ever quits, normal macOS sleep resumes automatically."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Decaffeinate").font(.title2.bold())
            Text("The truth about what's keeping your Mac awake — and the power to make it sleep.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Text("Version \(AppInfo.version) · MIT Licensed")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Link(
                "github.com/harf-promo/decaffeinate",
                destination: URL(string: "https://github.com/harf-promo/decaffeinate")!
            )
            .font(.caption)
            Button("Show welcome again") {
                OnboardingPresenter.shared.present(settingsStore: appState.settingsStore)
            }
            .buttonStyle(.link)
            .font(.caption)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

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
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "\(history.events.count) forced sleep\(history.events.count == 1 ? "" : "s") · \(history.batteryCount) on battery"
                    )
                    .font(.headline)
                    Text(
                        "≈ \(history.estimatedMinutesAvoided) min of needless wake avoided (rough estimate)."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                Divider()
                List {
                    ForEach(history.events) { event in
                        HStack(spacing: 8) {
                            Image(systemName: event.onBattery ? "battery.50" : "powerplug")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(event.reason).font(.callout).lineLimit(1)
                                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
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

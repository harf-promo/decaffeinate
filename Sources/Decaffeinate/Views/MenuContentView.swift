import SwiftUI

/// The whole menu-bar popover: status card, firewall prompts, quick actions,
/// the live assertion list, and a footer.
struct MenuContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
            StatusCardView()

            if !appState.pendingClassification.isEmpty {
                Divider()
                FirewallPromptSection()
            }

            Divider()
            QuickActions()

            Divider()
            WatchSection()

            Divider()
            AssertionListView()

            Divider()
            FooterView()
        }
        .frame(width: 340)
    }
}

/// Firewall: new, unclassified apps that just started holding the Mac awake.
struct FirewallPromptSection: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader("New sleep blocker", trailing: "decide")
            ForEach(appState.pendingClassification) { assertion in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sun.max.fill").foregroundStyle(.orange)
                        Text("\(assertion.displayName) is keeping your Mac awake")
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        Button("Allow") { appState.setPolicy(.allow, for: assertion) }
                            .buttonStyle(.borderedProminent)
                            .help("Let this app keep the Mac awake whenever it needs to.")
                        AllowForMenu(title: "For…", assertion: assertion)
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        Button("Let it sleep") { appState.setPolicy(.ignore, for: assertion) }
                            .help("Ignore this app's hold — the Mac may sleep while it runs.")
                        Spacer()
                        Button("Not now") { appState.dismissPending(assertion) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Dismiss without making a rule.")
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .background(Color.orange.opacity(0.06))
    }
}

/// Primary actions: Sleep Now + the two engine toggles.
struct QuickActions: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    private var settings: Binding<DecaffeinateSettings> { $settingsStore.settings }

    var body: some View {
        VStack(spacing: 8) {
            Button {
                appState.sleepNow()
            } label: {
                Label("Sleep Now", systemImage: "powersleep")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Put the Mac to sleep immediately, overriding every sleep block.")

            HStack(spacing: 8) {
                Toggle(isOn: settings.decaffeinateEnabled) {
                    Label("Auto-sleep", systemImage: "zzz")
                }
                .toggleStyle(.button)
                .disabled(appState.settings.caffeinateEnabled)
                .help("Force sleep after you've been idle, even if apps try to keep it awake.")

                Toggle(isOn: settings.caffeinateEnabled) {
                    Label("Keep awake", systemImage: "bolt")
                }
                .toggleStyle(.button)
                .help("Hold the Mac awake on purpose — the same safety rails still apply.")

                Spacer()

                if let remaining = appState.secondsUntilForcedSleep {
                    Text(Format.countdown(remaining))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .help("Time until the Mac is put to sleep.")
                }
            }
            .font(.caption)

            QuietWindowControl()

            // Make the core promise legible even when no live countdown is up —
            // but never promise a sleep we're currently holding off.
            if appState.settings.caffeinateEnabled {
                Text("Auto-sleep is paused while keeping awake")
                    .explanatory()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !appState.decision.canForceSleep,
                let reason = appState.decision.holdForceSleepReasons.first
            {
                Text("Auto-sleep paused — \(reason)")
                    .explanatory()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if appState.settings.decaffeinateEnabled, appState.secondsUntilForcedSleep == nil
            {
                Text(appState.idleSleepHint)
                    .explanatory()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }
}

/// A one-shot "stay awake until …" quiet window: hold the Mac awake for a preset
/// span, then auto-release. Collapses to a live "Awake until …" row with a cancel
/// while a window is in effect.
struct QuietWindowControl: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            if let until = appState.quietUntil, appState.isQuietWindowActive {
                if let paused = appState.quietWindowPausedReason {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Quiet window paused — \(paused)")
                        .font(.caption)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Image(systemName: "clock.fill").foregroundStyle(.tint)
                    Text("Awake until \(ScheduleEngine.timeLabel(until))")
                        .font(.caption)
                }
                Spacer()
                Button("Cancel") { appState.clearQuietWindow() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            } else {
                Menu {
                    Button("30 minutes") { appState.stayAwake(forMinutes: 30) }
                    Button("1 hour") { appState.stayAwake(forMinutes: 60) }
                    Button("2 hours") { appState.stayAwake(forMinutes: 120) }
                    Button("Until 6 PM") { appState.stayAwake(untilHour: 18) }
                } label: {
                    Label("Stay awake until…", systemImage: "clock")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Temporarily hold the Mac awake, then let it sleep automatically.")
                Spacer()
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Footer: idle threshold, settings, quit.
struct FooterView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        HStack(spacing: 12) {
            if let last = appState.lastSleepAt {
                Label(
                    "Slept \(Format.relative(since: last))", systemImage: "clock.arrow.circlepath"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if updater.isAvailable {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .help("Check for Updates…")
                .accessibilityLabel("Check for updates")
            }
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Decaffeinate")
            .accessibilityLabel("Quit Decaffeinate")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// "Sleep when my agent/build finishes" — pick a process to watch; the Mac
/// sleeps once it goes quiet.
struct WatchSection: View {
    @EnvironmentObject var appState: AppState

    private var isActive: Bool {
        if case .idle = appState.watchStatus { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader("Sleep when a task finishes")

            switch appState.watchStatus {
            case .idle:
                Menu {
                    if !appState.runningWatchCandidates.isEmpty {
                        Section("Running now") {
                            ForEach(appState.runningWatchCandidates, id: \.self) { name in
                                Button(name) { appState.setWatchTarget(.processName(name)) }
                            }
                        }
                    }
                    Section("Common tools") {
                        ForEach(appState.commonWatchCandidates, id: \.self) { name in
                            Button(name) { appState.setWatchTarget(.processName(name)) }
                        }
                    }
                } label: {
                    Label("Pick a build or agent…", systemImage: "binoculars")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

            case .waiting(let label):
                statusRow("hourglass", "Waiting for \(label) to start…")
            case .watching(let label, let cpu):
                let cpuText = cpu.map { String(format: " · %.0f%% CPU", $0) } ?? ""
                statusRow("binoculars.fill", "Watching \(label)\(cpuText)")
            case .completed(let label, _):
                if appState.isAutoSleepHeld {
                    statusRow("pause.circle.fill", "\(label) finished — sleep paused")
                } else {
                    statusRow("checkmark.circle.fill", "\(label) finished — sleeping soon")
                }
            }

            // Always explain the feature (it's the headline differentiator).
            Text(
                "Leave a long build or AI agent running, walk away — the Mac sleeps once it goes quiet."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if isActive {
                Button("Stop watching") { appState.setWatchTarget(nil) }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func statusRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(text).font(.callout).lineLimit(1)
        }
    }
}

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
                        Image(systemName: "bell.badge.fill").foregroundStyle(.orange)
                        Text("\(assertion.displayName) wants to keep your Mac awake")
                            .font(.callout.weight(.medium))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        Button("Allow") { appState.setPolicy(.allow, for: assertion) }
                        Button("1 hour") {
                            appState.setPolicy(
                                .allowUntil(Date().addingTimeInterval(3600)), for: assertion)
                        }
                        Button("Block") { appState.setPolicy(.ignore, for: assertion) }
                        Spacer()
                        Button("Ignore") { appState.dismissPending(assertion) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
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
                .help("Force sleep after you've been idle, even if apps try to keep it awake.")

                Toggle(isOn: settings.caffeinateEnabled) {
                    Label("Keep awake", systemImage: "bolt")
                }
                .toggleStyle(.button)
                .help("Hold the Mac awake on purpose (the opposite of this app's job).")

                Spacer()

                if appState.settings.decaffeinateEnabled, !appState.settings.caffeinateEnabled,
                    let remaining = appState.secondsUntilForcedSleep, appState.idleSeconds >= 30
                {
                    Text(Format.countdown(remaining))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)

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

/// Footer: idle threshold, settings, quit.
struct FooterView: View {
    @EnvironmentObject var appState: AppState

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
            SettingsLink {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .help("Quit Decaffeinate")
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
            SectionHeader("Sleep when finished")

            switch appState.watchStatus {
            case .idle:
                Menu {
                    ForEach(appState.watchCandidates, id: \.self) { name in
                        Button(name) { appState.setWatchTarget(.processName(name)) }
                    }
                } label: {
                    Label("Watch an app or agent…", systemImage: "binoculars")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Text("The Mac sleeps once the chosen build/agent goes quiet and you step away.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case .waiting(let label):
                statusRow("hourglass", "Waiting for \(label) to start…")
            case .watching(let label, let cpu):
                let cpuText = cpu.map { String(format: " · %.0f%% CPU", $0) } ?? ""
                statusRow("binoculars.fill", "Watching \(label)\(cpuText)")
            case .completed(let label, _):
                statusRow("checkmark.circle.fill", "\(label) finished — sleeping soon")
            }

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

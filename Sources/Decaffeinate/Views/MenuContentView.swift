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

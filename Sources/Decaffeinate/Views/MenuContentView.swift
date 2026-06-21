import SwiftUI

/// The menu-bar popover, in three zones so the footer (Settings/quit) is ALWAYS
/// reachable and the blocker list gets real room:
///   • pinned header — status card + the primary actions
///   • one scrolling body — what's keeping the Mac awake (+ inline approvals)
///   • pinned footer — slept-ago · update · Settings · quit
struct MenuContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // ── Pinned header ──
            StatusCardView()
            QuickActionBar()

            Hairline()

            // ── The one scroll ──
            ScrollView {
                AssertionListView()
                    .padding(.bottom, Space.s2)
            }
            .frame(maxHeight: .infinity)

            Hairline()

            // ── Pinned footer ──
            FooterView()
        }
        .frame(width: 360, height: 460)
        .background(Color.paper)
    }
}

/// The primary actions: Sleep Now (the one hero button) + a single "Keep awake"
/// menu that holds every secondary control, plus one cancelable line for the
/// active mode. Far fewer buttons than before — the rest lives in the menu.
struct QuickActionBar: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    private var settings: Binding<DecaffeinateSettings> { $settingsStore.settings }

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    appState.sleepNow()
                } label: {
                    Label("Sleep Now", systemImage: "powersleep")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HarfButtonStyle(variant: .primary, size: .large))
                .help("Put the Mac to sleep now, overriding every sleep block.")

                Menu {
                    Toggle("Keep awake now", isOn: settings.caffeinateEnabled)

                    Section("Stay awake until") {
                        Button("30 minutes") { appState.stayAwake(forMinutes: 30) }
                        Button("1 hour") { appState.stayAwake(forMinutes: 60) }
                        Button("2 hours") { appState.stayAwake(forMinutes: 120) }
                        Button("Until 6 PM") { appState.stayAwake(untilHour: 18) }
                    }

                    Section("Sleep automation") {
                        Toggle("Auto-sleep when idle", isOn: settings.decaffeinateEnabled)
                        Menu("Sleep when a task finishes…") {
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
                        }
                    }
                } label: {
                    Label("Keep awake", systemImage: "bolt")
                }
                .menuStyle(.borderlessButton)
                .tint(Color.ink1)
                .fixedSize()
                .help("Keep the Mac awake, on a timer, or until a task finishes.")
            }

            activeControl

            if let error = appState.lastError {
                Text(error)
                    .font(HarfFont.micro)
                    .foregroundStyle(Color.critical)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Space.s3)
    }

    private var isWatchActive: Bool {
        if case .idle = appState.watchStatus { return false }
        return true
    }

    /// One cancelable line for the active keep-awake / watch mode (the status
    /// card already names the *state*; this is the *control* to undo it).
    @ViewBuilder private var activeControl: some View {
        if appState.isQuietWindowActive {
            controlRow("clock.fill", .info, "Cancel quiet window") { appState.clearQuietWindow() }
        } else if isWatchActive {
            controlRow("binoculars.fill", .positive, "Stop watching") {
                appState.setWatchTarget(nil)
            }
        } else if appState.settings.caffeinateEnabled {
            controlRow("bolt.fill", .info, "Stop keeping awake") {
                settingsStore.settings.caffeinateEnabled = false
            }
        } else if let reason = appState.activeTriggerReason {
            // Trigger keep-awake is automatic — show why, no manual cancel.
            HStack(spacing: Space.s2) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.caption2).foregroundStyle(Color.info).accessibilityHidden(true)
                Text("Kept awake — \(reason)").font(HarfFont.caption).foregroundStyle(Color.ink2)
                    .lineLimit(1)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func controlRow(
        _ icon: String, _ tint: Color, _ label: String, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: icon).font(.caption2).foregroundStyle(tint).accessibilityHidden(true)
            Button(label, action: action)
                .buttonStyle(HarfButtonStyle(variant: .text, size: .small))
                .fixedSize()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Footer (pinned): last sleep, check-for-updates, Settings, quit — always
/// on-screen now that the body scrolls.
struct FooterView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        HStack(spacing: Space.s3) {
            if let last = appState.lastSleepAt {
                Label(
                    "Slept \(Format.relative(since: last))", systemImage: "clock.arrow.circlepath"
                )
                .font(HarfFont.micro)
                .foregroundStyle(Color.ink3)
            }
            Spacer()
            if updater.isAvailable {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.ink2)
                .help("Check for Updates…")
                .accessibilityLabel("Check for updates")
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(HarfFont.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink2)
            .help("Open Settings")
            .accessibilityLabel("Settings")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.ink2)
            .help("Quit Decaffeinate")
            .accessibilityLabel("Quit Decaffeinate")
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
    }
}

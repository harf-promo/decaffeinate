import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "zzz") }
            SafetySettings()
                .tabItem { Label("Safety", systemImage: "shield.lefthalf.filled") }
            RulesSettings()
                .tabItem { Label("Rules", systemImage: "list.bullet.rectangle") }
            AdvancedSettings()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 440, height: 380)
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
            }

            Section("Keep awake (optional)") {
                Toggle("Hold the Mac awake on purpose", isOn: s.caffeinateEnabled)
                Toggle("Also keep the display on", isOn: s.caffeinateKeepsDisplayAwake)
                    .disabled(!store.settings.caffeinateEnabled)
            }

            Section {
                Toggle("Notify me when a new app keeps the Mac awake", isOn: s.notifyOnNewBlocker)
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
                Toggle("Pause for active media or calls", isOn: s.pauseForActiveMedia)
                Toggle("Pause during Time Machine backups", isOn: s.pauseForTimeMachine)
                Toggle("Pause during macOS updates", isOn: s.pauseForSystemUpdate)
                Toggle("Respect apps I've allowed", isOn: s.respectWhitelist)
            }

            Section("Battery & heat") {
                HStack {
                    Text("Battery floor")
                    Slider(
                        value: Binding(
                            get: { Double(store.settings.batteryFloorPercent) },
                            set: { store.settings.batteryFloorPercent = Int($0) }
                        ), in: 0...50, step: 5)
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

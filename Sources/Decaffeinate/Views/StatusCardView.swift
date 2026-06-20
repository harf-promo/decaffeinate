import SwiftUI

/// The banner at the top of the menu: the big mug, the headline ("Sleeping in
/// 9:32" / "Chrome is keeping your Mac awake"), and live status chips.
struct StatusCardView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        // The most urgent conditions escalate the whole card to red, regardless
        // of mug state.
        if appState.thermalState == .critical { return .red }
        if appState.power.onBattery, let pct = appState.power.chargePercent,
            pct < appState.settings.batteryFloorPercent
        {
            return .red
        }
        switch appState.mug {
        case .free: return .green
        case .counting: return .accentColor
        case .blocked: return .orange
        case .caffeinated: return .purple
        }
    }

    /// Color washes need a touch more presence in dark mode to keep grouping.
    private var washOpacity: Double { colorScheme == .dark ? 0.16 : 0.09 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(nsImage: MugIcon.image(for: appState.mug, size: 28))
                    .renderingMode(.template)
                    .foregroundStyle(tint)
                    .frame(width: 34)
                    .accessibilityLabel(appState.mug.accessibilityLabel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.headline)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !appState.detail.isEmpty {
                        Text(appState.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            chips
        }
        .padding(12)
        .background(tint.opacity(washOpacity))
    }

    private var chips: some View {
        HStack(spacing: 6) {
            // Power
            if appState.power.onBattery, let pct = appState.power.chargePercent {
                Chip(
                    systemImage: appState.power.isCharging ? "battery.100.bolt" : "battery.50",
                    text: "\(pct)%",
                    tint: pct < appState.settings.batteryFloorPercent ? .red : .secondary)
            } else {
                Chip(systemImage: "powerplug", text: "AC power")
            }

            // Thermal
            thermalChip

            // Idle
            if appState.idleSeconds >= 60 {
                Chip(systemImage: "moon.zzz", text: "Idle " + Format.duration(appState.idleSeconds))
            }

            // Blockers
            if appState.systemBlockerCount > 0 {
                Chip(
                    systemImage: "sun.max.fill",
                    text: "\(appState.systemBlockerCount) holding awake",
                    tint: .orange)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var thermalChip: some View {
        switch appState.thermalState {
        case .serious:
            Chip(systemImage: "thermometer.high", text: "Hot", tint: .orange)
        case .critical:
            Chip(systemImage: "thermometer.high", text: "Overheating", tint: .red)
        default:
            EmptyView()
        }
    }
}

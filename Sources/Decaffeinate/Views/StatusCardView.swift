import SwiftUI

/// The banner at the top of the menu: the moon mark, the headline ("Sleeping in
/// 9:32" / "Chrome is keeping your Mac awake"), and live status chips. The mark
/// stays neutral ink (its *shape* carries the state); a thin status-coloured
/// leading rule does the glanceable colour — no full-card wash (clean in dark).
struct StatusCardView: View {
    @EnvironmentObject var appState: AppState

    /// The status accent for the leading rule (and battery/thermal escalation).
    private var accent: Color {
        if appState.thermalState == .critical { return .critical }
        if appState.power.onBattery, let pct = appState.power.chargePercent,
            pct < appState.settings.batteryFloorPercent
        {
            return .critical
        }
        switch appState.mug {
        case .free: return .harfGreen  // the one green mark per surface — "ready"
        case .counting: return .positive  // active state is teal, not brand green
        case .blocked: return .warning
        case .caffeinated: return .info
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: Space.s2) {
                HStack(spacing: Space.s3) {
                    Image(nsImage: MugIcon.image(for: appState.mug, size: 26))
                        .renderingMode(.template)
                        .foregroundStyle(Color.ink1)
                        .frame(width: 30)
                        .accessibilityLabel(appState.mug.accessibilityLabel)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.headline)
                            .font(HarfFont.title)
                            .foregroundStyle(Color.ink1)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if !appState.detail.isEmpty {
                            Text(appState.detail)
                                .font(HarfFont.caption)
                                .foregroundStyle(Color.ink3)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                chips
            }
            .padding(Space.s3)
        }
        .background(Color.paper)
    }

    private var chips: some View {
        HStack(spacing: Space.s2) {
            if appState.power.onBattery, let pct = appState.power.chargePercent {
                Chip(
                    systemImage: appState.power.isCharging ? "battery.100.bolt" : "battery.50",
                    text: "\(pct)%",
                    tint: pct < appState.settings.batteryFloorPercent ? .critical : .ink3)
            } else {
                Chip(systemImage: "powerplug", text: "AC power")
            }

            thermalChip

            if appState.idleSeconds >= 60 {
                Chip(systemImage: "moon.zzz", text: "Idle " + Format.duration(appState.idleSeconds))
            }

            if appState.systemBlockerCount > 0 {
                Chip(
                    systemImage: "sun.max.fill",
                    text: "\(appState.systemBlockerCount) holding awake",
                    tint: .warning)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var thermalChip: some View {
        switch appState.thermalState {
        case .serious:
            Chip(systemImage: "thermometer.high", text: "Hot", tint: .warning)
        case .critical:
            Chip(systemImage: "thermometer.high", text: "Overheating", tint: .critical)
        default:
            EmptyView()
        }
    }
}

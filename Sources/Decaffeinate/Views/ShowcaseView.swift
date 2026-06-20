import SwiftUI

/// A static, render-friendly composition of the menu used only for README
/// screenshots (`--render-previews`). It reuses the real `StatusCardView` and
/// `QuickActions` (which render cleanly in `ImageRenderer`) but replaces the
/// live assertion list — which uses `ScrollView` + `Menu` that `ImageRenderer`
/// can't draw — with static rows.
struct ShowcaseView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            StatusCardView()
            Divider()
            QuickActions()
            Divider()

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Keeping your Mac awake")
                ForEach(appState.assertions) { ShowcaseRow(assertion: $0) }
            }
            .padding(.bottom, 8)
        }
        .frame(width: 340)
        .background(.background)
    }
}

private struct ShowcaseRow: View {
    let assertion: PowerAssertion
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: assertion.kind.glyph)
                .foregroundStyle(assertion.kind.tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(assertion.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "ellipsis.circle").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var subtitle: String {
        var parts: [String] = [assertion.kind.label]
        if let attribution = assertion.attribution { parts.append(attribution) }
        if assertion.name != "Unnamed", !assertion.name.isEmpty {
            parts.append("“\(assertion.name)”")
        }
        if let held = appState.heldDuration(assertion) { parts.append(held) }
        return parts.joined(separator: " · ")
    }
}

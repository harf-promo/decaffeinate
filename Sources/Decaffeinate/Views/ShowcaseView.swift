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
                Text(assertion.subtitle(held: appState.heldDuration(assertion), includePID: false))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "ellipsis.circle").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }
}

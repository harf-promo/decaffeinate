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
            Hairline()
            QuickActions()
            Hairline()

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Keeping your Mac awake")
                ForEach(appState.assertions) { ShowcaseRow(assertion: $0) }
            }
            .padding(.bottom, Space.s2)
        }
        .frame(width: 340)
        .background(Color.paper)
    }
}

private struct ShowcaseRow: View {
    let assertion: PowerAssertion
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: assertion.reason.category.systemImage)
                .foregroundStyle(Color.ink2)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(assertion.displayName)
                    .font(HarfFont.bodyMedium)
                    .foregroundStyle(Color.ink1)
                    .lineLimit(1)
                Text(rowSubtitle)
                    .font(HarfFont.micro)
                    .foregroundStyle(Color.ink3)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.ink4)
        }
        .padding(.horizontal, Space.s3)
        .padding(.vertical, 5)
    }

    private var rowSubtitle: String {
        var parts = [assertion.reason.explanation]
        if let attribution = assertion.attribution { parts.append(attribution) }
        if let held = appState.heldDuration(assertion) { parts.append(held) }
        return parts.joined(separator: " · ")
    }
}

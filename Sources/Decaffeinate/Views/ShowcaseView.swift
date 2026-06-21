import SwiftUI

/// A static, render-friendly composition of the menu used only for README
/// screenshots (`--render-previews`). Reuses the real header + the shared
/// `BlockerRow` so the screenshot matches the live app; `ImageRenderer` draws
/// Menus as their label, which is fine for a still.
struct ShowcaseView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            StatusCardView()
            QuickActionBar()
            Hairline()

            VStack(alignment: .leading, spacing: 0) {
                SectionHeader("Keeping your Mac awake")
                ForEach(appState.assertions) { BlockerRow(assertion: $0) }
            }
            .padding(.bottom, Space.s2)
        }
        .frame(width: 360)
        .background(Color.paper)
    }
}

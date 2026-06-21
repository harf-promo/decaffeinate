import SwiftUI

/// The "what's keeping your Mac awake" list — the truth, straight from IOKit.
struct AssertionListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine

    private var systemBlockers: [PowerAssertion] {
        appState.assertions.filter(\.blocksSystemSleep)
    }
    private var others: [PowerAssertion] {
        appState.assertions.filter { !$0.blocksSystemSleep }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                "Keeping your Mac awake",
                trailing: appState.assertions.isEmpty ? "all clear" : nil)

            if appState.assertions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(systemBlockers) { AssertionRow(assertion: $0) }
                        if !others.isEmpty {
                            SectionHeader("Screen-only / background")
                            ForEach(others) { AssertionRow(assertion: $0) }
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            Text("Nothing is holding your Mac awake.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }
}

/// One assertion row with the reason, an inline allow/block menu, and a
/// tap-to-expand detail disclosure.
struct AssertionRow: View {
    let assertion: PowerAssertion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine
    @State private var showDetails = false

    private var policy: RulePolicy? { rules.policy(for: assertion) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: assertion.reason.category.systemImage)
                    .foregroundStyle(assertion.kind.tint)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(assertion.displayName)
                            .font(.callout.weight(.medium))
                            .lineLimit(1)
                        policyBadge
                    }
                    Text(rowSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(showDetails ? 90 : 0))
                    .accessibilityHidden(true)
                policyMenu
                    .accessibilitySortPriority(-1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("\(assertion.displayName). \(rowSubtitle)")
            .accessibilityValue(showDetails ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides details")
            .accessibilityAction {
                withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
            }

            if showDetails {
                AssertionDetailView(assertion: assertion)
            }
        }
    }

    /// Reason-led subtitle: "Playing media · via runningboardd · for 14m".
    private var rowSubtitle: String {
        var parts = [assertion.reason.explanation]
        if let attribution = assertion.attribution { parts.append(attribution) }
        if let held = appState.heldDuration(assertion) { parts.append(held) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var policyBadge: some View {
        switch policy {
        case .allow:
            tag("Allowed", .green)
        case .allowUntil:
            tag("Allowed · timed", .green)
        case .ignore:
            tag("Ignored", .orange)
        case .none:
            EmptyView()
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
    }

    private var policyMenu: some View {
        Menu {
            Button("Always allow to keep awake") {
                appState.setPolicy(.allow, for: assertion)
            }
            AllowForMenu(title: "Allow for…", assertion: assertion)
            Button("Let it sleep (ignore)") {
                appState.setPolicy(.ignore, for: assertion)
            }
            if policy != nil {
                Divider()
                Button("Clear rule") {
                    appState.clearRule(for: assertion)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Rules for \(assertion.displayName)")
    }
}

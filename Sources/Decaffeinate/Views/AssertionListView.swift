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

/// One assertion row with an inline allow/block menu.
struct AssertionRow: View {
    let assertion: PowerAssertion
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine

    private var policy: RulePolicy? { rules.policy(for: assertion) }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: assertion.kind.glyph)
                .foregroundStyle(assertion.kind.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(assertion.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    policyBadge
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            policyMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
    }

    private var subtitle: String {
        var parts: [String] = [assertion.kind.label]
        if let attribution = assertion.attribution {
            parts.append(attribution)
        }
        if assertion.name != "Unnamed", !assertion.name.isEmpty {
            parts.append("“\(assertion.name)”")
        }
        if let held = appState.heldDuration(assertion) {
            parts.append(held)
        }
        parts.append("PID \(assertion.pid)")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var policyBadge: some View {
        switch policy {
        case .allow:
            tag("Allowed", .green)
        case .allowUntil:
            tag("Allowed ⏱", .green)
        case .ignore:
            tag("Blocked", .orange)
        case .none:
            EmptyView()
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
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
            Menu("Allow for…") {
                ForEach(AllowDuration.allCases, id: \.self) { duration in
                    Button(duration.label) {
                        appState.setPolicy(
                            .allowUntil(duration.expiry(from: Date())), for: assertion)
                    }
                }
            }
            Button("Block (let Mac sleep)") {
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
    }
}

import SwiftUI

/// The "what's keeping your Mac awake" list — the truth, straight from IOKit.
/// Renders as plain content (the parent menu owns the single scroll). A blocker
/// that still needs a decision shows its approval buttons inline (no separate
/// firewall section — same row, highlighted).
struct AssertionListView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine

    private var systemBlockers: [PowerAssertion] {
        appState.assertions.filter(\.blocksSystemSleep)
    }
    private var others: [PowerAssertion] {
        appState.assertions.filter { !$0.blocksSystemSleep }
    }
    private func isPending(_ a: PowerAssertion) -> Bool {
        appState.pendingClassification.contains { $0.id == a.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(
                "Keeping your Mac awake",
                trailing: appState.assertions.isEmpty ? "all clear" : nil)

            if appState.assertions.isEmpty {
                emptyState
            } else {
                ForEach(systemBlockers) { BlockerRow(assertion: $0, pending: isPending($0)) }
                if !others.isEmpty {
                    SectionHeader("Screen-only / background")
                    ForEach(others) { BlockerRow(assertion: $0, pending: isPending($0)) }
                }
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Color.positive)
            Text("Nothing is holding your Mac awake.")
                .font(HarfFont.body)
                .foregroundStyle(Color.ink2)
        }
        .padding(Space.s3)
    }
}

/// One blocker, with its real app icon, a plain-language reason, who's behind it,
/// how long it's been held — and, when it still needs a decision, the inline
/// Allow / Block buttons. Tap to expand the full, copyable detail.
struct BlockerRow: View {
    let assertion: PowerAssertion
    var pending: Bool = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine
    @State private var showDetails = false

    private var policy: RulePolicy? { rules.policy(for: assertion) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.s2) {
                AppIconView(assertion: assertion, size: 26)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(assertion.displayName)
                            .font(HarfFont.bodyMedium)
                            .foregroundStyle(Color.ink1)
                            .lineLimit(1)
                        if !pending { policyBadge }
                    }
                    Text(contextLine)
                        .font(HarfFont.micro)
                        .foregroundStyle(Color.ink3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if pending { approvalButtons }
                }

                Spacer(minLength: 4)

                if !pending {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Color.ink4)
                        .rotationEffect(.degrees(showDetails ? 90 : 0))
                        .accessibilityHidden(true)
                    policyMenu.accessibilitySortPriority(-1)
                }
            }
            .padding(.horizontal, Space.s3)
            .padding(.vertical, Space.s2)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() } }
            .accessibilityElement(children: pending ? .contain : .combine)
            .accessibilityAddTraits(pending ? [] : .isButton)
            .accessibilityLabel("\(assertion.displayName). \(contextLine)")
            .accessibilityValue(pending ? "" : (showDetails ? "Expanded" : "Collapsed"))
            .accessibilityAction(.default) {
                withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() }
            }
            .background(pending ? Color.warningTint.opacity(0.45) : Color.clear)
            .overlay(alignment: .leading) {
                if pending { Rectangle().fill(Color.warning).frame(width: 3) }
            }

            if showDetails {
                AssertionDetailView(assertion: assertion)
            }
        }
    }

    /// "Playing media · via coreaudiod · held 14m · auto-releases in 84s".
    private var contextLine: String {
        var parts = [assertion.reason.explanation]
        if let attribution = assertion.attribution { parts.append(attribution) }
        if let held = appState.heldDuration(assertion) {
            parts.append("held " + held.replacingOccurrences(of: "for ", with: ""))
        }
        if let secs = assertion.reason.autoReleaseSeconds {
            parts.append("auto-releases in \(secs)s")
        }
        return parts.joined(separator: " · ")
    }

    private var approvalButtons: some View {
        HStack(spacing: Space.s2) {
            Button("Allow") { appState.setPolicy(.allow, for: assertion) }
                .buttonStyle(HarfButtonStyle(variant: .accent, size: .small))
                .fixedSize()
                .help("Let this app keep the Mac awake whenever it needs to.")
            AllowForMenu(title: "For…", assertion: assertion)
                .menuStyle(.borderlessButton)
                .tint(Color.ink2)
                .fixedSize()
            Button("Let it sleep") { appState.setPolicy(.ignore, for: assertion) }
                .buttonStyle(HarfButtonStyle(variant: .ghost, size: .small))
                .fixedSize()
                .help("Ignore this app's hold — the Mac may sleep while it runs.")
            Button("Not now") { appState.dismissPending(assertion) }
                .buttonStyle(HarfButtonStyle(variant: .text, size: .small))
                .fixedSize()
                .help("Dismiss without making a rule.")
        }
        .padding(.top, 2)
    }

    @ViewBuilder private var policyBadge: some View {
        switch policy {
        case .allow:
            HarfPill(label: "Allowed", variant: .positive)
        case .allowUntil:
            HarfPill(label: "Allowed · timed", variant: .positive)
        case .ignore:
            HarfPill(label: "Ignored", variant: .neutral)
        case .none:
            EmptyView()
        }
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
        .tint(Color.ink3)
        .fixedSize()
        .accessibilityLabel("Rules for \(assertion.displayName)")
    }
}

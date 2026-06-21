import SwiftUI

// =====================================================================
// The redesigned menu — built from the design council's verdict.
//
// One structure, two skins (see Theme.swift). It carries the universal
// fixes the council found in the real screenshots:
//   1. the header HUGS its content (no dead gap)
//   2. one quiet tracked meta-line, no coloured pills
//   3. green is one mark per surface (Sleep Now / active Allow)
//   4. "Allowed" → neutral tag + teal dot, not a green pill
//   5. raised, readable type floor
//   6. one row pattern, max two buttons, a single "…" for the rest
//
// Reads `@Environment(\.theme)`, so a direction renders by injecting a Theme.
// =====================================================================
struct RedesignMenuView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            RDHeader()
            RDActionBar()

            if !theme.usesCards { themedHairline }

            ScrollView {
                RDList()
                    .padding(.top, theme.usesCards ? theme.rowGap : Space.s2)
                    .padding(.bottom, theme.usesCards ? theme.rowGap : Space.s2)
            }
            .frame(maxHeight: .infinity)

            themedHairline
            RDFooter()
        }
        .frame(width: theme.popoverWidth, height: Self.menuHeight)
        .background(theme.paper)
    }

    private var themedHairline: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    /// A fixed-but-screen-aware height: tall enough for the list to breathe, but
    /// never taller than the space below the menu bar — so the footer (Settings /
    /// quit / update) can't be pushed off-screen on a small display.
    static var menuHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 720
        return min(460, max(360, available * 0.8))
    }
}

// ── Header: mark + outcome headline + one quiet meta-line, hugging its content ──
private struct RDHeader: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.s3) {
                DecaffeinateMark(size: 26)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.headline)
                        .font(theme.headlineFont)
                        .foregroundStyle(theme.ink1)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !appState.detail.isEmpty {
                        Text(appState.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.ink3)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(metaLine)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.ink4)
                .padding(.top, Space.s2)
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.top, Space.s4)
    }

    /// "BATTERY 82% · 2 APPS HOLDING · IDLE 4M" — neutral, never amber.
    private var metaLine: String {
        var parts: [String] = []
        if appState.power.onBattery, let pct = appState.power.chargePercent {
            parts.append("BATTERY \(pct)%")
        } else {
            parts.append("AC POWER")
        }
        let n = appState.activeHoldingCount
        if n > 0 { parts.append("\(n) APP\(n == 1 ? "" : "S") HOLDING") }
        if appState.idleSeconds >= 60 {
            parts.append("IDLE " + Format.duration(appState.idleSeconds).uppercased())
        }
        return parts.joined(separator: " · ")
    }
}

// ── Primary action: Sleep Now (the one green mark) + a single Keep-awake menu ──
private struct RDActionBar: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    private var settings: Binding<DecaffeinateSettings> { $settingsStore.settings }

    var body: some View {
        VStack(spacing: Space.s2) {
            HStack(spacing: Space.s2) {
                Button {
                    appState.sleepNow()
                } label: {
                    Label("Sleep Now", systemImage: "powersleep")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(RDPrimaryButton())
                .help("Put the Mac to sleep now, overriding every sleep block.")

                Menu {
                    Toggle("Keep awake now", isOn: settings.caffeinateEnabled)
                    Section("Stay awake until") {
                        Button("30 minutes") { appState.stayAwake(forMinutes: 30) }
                        Button("1 hour") { appState.stayAwake(forMinutes: 60) }
                        Button("2 hours") { appState.stayAwake(forMinutes: 120) }
                        Button("Until 6 PM") { appState.stayAwake(untilHour: 18) }
                    }
                    Section("Sleep automation") {
                        Toggle("Auto-sleep when idle", isOn: settings.decaffeinateEnabled)
                        Menu("Sleep when a task finishes…") {
                            if !appState.runningWatchCandidates.isEmpty {
                                Section("Running now") {
                                    ForEach(appState.runningWatchCandidates, id: \.self) { name in
                                        Button(name) { appState.setWatchTarget(.processName(name)) }
                                    }
                                }
                            }
                            Section("Common tools") {
                                ForEach(appState.commonWatchCandidates, id: \.self) { name in
                                    Button(name) { appState.setWatchTarget(.processName(name)) }
                                }
                            }
                        }
                    }
                } label: {
                    Label("Keep awake", systemImage: "bolt")
                }
                .menuStyle(.button)
                .buttonStyle(RDSecondaryButton())
                .fixedSize()
                .help("Keep the Mac awake, on a timer, or until a task finishes.")
            }

            RDActiveControls()

            if let error = appState.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.critical)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.top, Space.s5)
        .padding(.bottom, theme.usesCards ? Space.s2 : Space.s4)
    }
}

// ── Cancelable line for each active keep-awake / watch mode ──
private struct RDActiveControls: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsStore: SettingsStore

    private var isWatchActive: Bool {
        if case .idle = appState.watchStatus { return false }
        return true
    }

    var body: some View {
        VStack(spacing: Space.s1) {
            if appState.isQuietWindowActive {
                row("clock.fill", "Cancel quiet window") { appState.clearQuietWindow() }
            }
            if isWatchActive {
                row("binoculars.fill", "Stop watching") { appState.setWatchTarget(nil) }
            }
            if appState.settings.caffeinateEnabled {
                row("bolt.fill", "Stop keeping awake") {
                    settingsStore.settings.caffeinateEnabled = false
                }
            }
            if let reason = appState.activeTriggerReason {
                HStack(spacing: Space.s2) {
                    Image(systemName: "bolt.horizontal.circle.fill")
                        .font(.caption2).foregroundStyle(theme.accent).accessibilityHidden(true)
                    Text("Kept awake — \(reason)")
                        .font(.system(size: 12)).foregroundStyle(theme.ink2).lineLimit(1)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: icon).font(.caption2).foregroundStyle(theme.ink3)
                .accessibilityHidden(true)
            Button(label, action: action).buttonStyle(.plain).foregroundStyle(theme.ink2)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── The list: one section label + the blocker rows ──
private struct RDList: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState

    private var systemBlockers: [PowerAssertion] {
        appState.assertions.filter(\.blocksSystemSleep)
    }
    private var others: [PowerAssertion] {
        appState.assertions.filter { !$0.blocksSystemSleep }
    }
    private func isPending(_ a: PowerAssertion) -> Bool { appState.isPendingDecision(a) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.usesCards ? theme.rowGap : 0) {
            if appState.assertions.isEmpty {
                RDSectionLabel(text: "Keeping your Mac awake", trailing: "all clear")
                emptyState
            } else {
                RDSectionLabel(text: "Keeping your Mac awake", trailing: nil)
                rows(systemBlockers)
                if !others.isEmpty {
                    RDSectionLabel(text: "Screen-only / background", trailing: nil)
                        .padding(.top, theme.usesCards ? 0 : Space.s2)
                    rows(others)
                }
            }
        }
    }

    @ViewBuilder private func rows(_ list: [PowerAssertion]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { idx, a in
            RDRow(assertion: a, pending: isPending(a))
            if !theme.usesCards && idx < list.count - 1 {
                Rectangle().fill(theme.hairline).frame(height: 1)
                    .padding(.leading, theme.contentInset + Metrics.rowIcon + Space.s3)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.teal)
            Text("Nothing is holding your Mac awake.")
                .font(.system(size: 14)).foregroundStyle(theme.ink2)
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.vertical, Space.s3)
    }
}

private struct RDSectionLabel: View {
    @Environment(\.theme) private var theme
    let text: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(text).textCase(.uppercase).font(.system(size: 11, weight: .semibold))
                .tracking(0.8).foregroundStyle(theme.ink3)
            Spacer()
            if let trailing {
                Text(trailing).textCase(.uppercase).font(.system(size: 11, weight: .semibold))
                    .tracking(0.8).foregroundStyle(theme.ink4)
            }
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.bottom, Space.s1)
    }
}

// ── One blocker row: icon · name + tag · two-tone context · (pending) 2 buttons ──
private struct RDRow: View {
    @Environment(\.theme) private var theme
    let assertion: PowerAssertion
    var pending: Bool = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine
    @State private var showDetails = false

    private var policy: RulePolicy? { rules.policy(for: assertion) }

    var body: some View {
        VStack(spacing: 0) {
            content
            if showDetails && !pending {
                AssertionDetailView(assertion: assertion)
                    .padding(.horizontal, theme.usesCards ? Space.s3 : theme.contentInset)
            }
        }
        .background(rowBackground)
        .overlay(alignment: .leading) { pendingRail }
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius))
        .overlay(cardBorder)
        .padding(.horizontal, theme.contentInset)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Space.s3) {
            AppIconView(assertion: assertion, size: Metrics.rowIcon)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.s2) {
                    Text(assertion.displayName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.ink1).lineLimit(1)
                    if !pending { tag }
                }
                contextText
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                if pending { approvalButtons.padding(.top, Space.s1) }
            }

            Spacer(minLength: Space.s1)
            if !pending { rowMenu }
        }
        .padding(.horizontal, theme.usesCards ? Space.s3 : theme.contentInset)
        .padding(.vertical, theme.usesCards ? Space.s3 : Space.s2)
        .frame(minHeight: pending ? nil : theme.rowMinHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if !pending { withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() } }
        }
    }

    private var contextText: Text {
        var t = Text(assertion.reason.explanation).foregroundStyle(theme.ink2)
        var tail: [String] = []
        if let attribution = assertion.attribution { tail.append(attribution) }
        if let held = appState.heldDuration(assertion) {
            tail.append("held " + held.replacingOccurrences(of: "for ", with: ""))
        }
        if let secs = assertion.reason.autoReleaseSeconds {
            tail.append("auto-releases in \(secs)s")
        }
        if !tail.isEmpty {
            t = t + Text(" · " + tail.joined(separator: " · ")).foregroundStyle(theme.ink4)
        }
        return t.font(.system(size: 12))
    }

    @ViewBuilder private var tag: some View {
        switch policy {
        case .allow:
            allowedTag(timed: false)
        case .allowUntil:
            allowedTag(timed: true)
        case .ignore:
            Text("Ignored").textCase(.uppercase).font(.system(size: 10, weight: .semibold))
                .tracking(0.7).foregroundStyle(theme.ink4)
        case .none:
            EmptyView()
        }
    }

    private func allowedTag(timed: Bool) -> some View {
        HStack(spacing: Space.s1) {
            Circle().fill(theme.teal).frame(width: 5, height: 5)
            Text(timed ? "Allowed · timed" : "Allowed")
                .textCase(.uppercase).font(.system(size: 10, weight: .semibold))
                .tracking(0.7).foregroundStyle(theme.ink3)
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: Space.s2) {
            Button("Allow") { appState.setPolicy(.allow, for: assertion) }
                .buttonStyle(RDPrimaryButton(compact: true))
                .fixedSize()
                .accessibilityLabel("Allow \(assertion.displayName) to keep the Mac awake")
            Button("Let it sleep") { appState.setPolicy(.ignore, for: assertion) }
                .buttonStyle(RDSecondaryButton(compact: true))
                .fixedSize()
                .accessibilityLabel("Ignore \(assertion.displayName); let the Mac sleep")
            AllowForMenu(title: "For…", assertion: assertion)
                .menuStyle(.borderlessButton)
                .tint(theme.ink3)
                .fixedSize()
                .accessibilityLabel("Allow \(assertion.displayName) for a set time")
            Spacer(minLength: 0)
        }
    }

    private var rowMenu: some View {
        Menu {
            Button("Always allow to keep awake") { appState.setPolicy(.allow, for: assertion) }
            AllowForMenu(title: "Allow for…", assertion: assertion)
            Button("Let it sleep (ignore)") { appState.setPolicy(.ignore, for: assertion) }
            if policy != nil {
                Divider()
                Button("Clear rule") { appState.clearRule(for: assertion) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(theme.ink4)
        .fixedSize()
        .accessibilityLabel("Rules for \(assertion.displayName)")
    }

    @ViewBuilder private var rowBackground: some View {
        if theme.usesCards {
            RoundedRectangle(cornerRadius: theme.cardRadius)
                .fill(pending ? theme.cardActive : theme.card)
        } else if pending {
            theme.cardActive
        } else {
            Color.clear
        }
    }

    @ViewBuilder private var cardBorder: some View {
        if theme.usesCards {
            RoundedRectangle(cornerRadius: theme.cardRadius).stroke(theme.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder private var pendingRail: some View {
        if pending {
            if theme.usesCards {
                RoundedRectangle(cornerRadius: 2).fill(theme.accent)
                    .frame(width: 3).padding(.vertical, Space.s2)
            } else {
                Rectangle().fill(theme.accent).frame(width: 3)
            }
        }
    }
}

// ── Footer: slept-ago / update · Settings · quit ──
private struct RDFooter: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        HStack(spacing: Space.s3) {
            if updater.updateAvailable {
                Button {
                    updater.checkForUpdates()
                } label: {
                    Label("Update available", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(RDPrimaryButton(compact: true))
                .fixedSize()
                .help("A new version of Decaffeinate is ready — click to install.")
            } else if let last = appState.lastSleepAt {
                Label(
                    "Slept \(Format.relative(since: last))", systemImage: "clock.arrow.circlepath"
                )
                .font(.system(size: 11)).foregroundStyle(theme.ink3)
            }
            Spacer()
            if updater.isAvailable {
                iconButton("arrow.triangle.2.circlepath", "Check for updates") {
                    updater.checkForUpdates()
                }
            }
            SettingsLink {
                Label("Settings", systemImage: "gearshape").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(theme.ink2)
            .help("Open Settings").accessibilityLabel("Settings")
            iconButton("power", "Quit Decaffeinate") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.vertical, Space.s2)
    }

    private func iconButton(_ icon: String, _ label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.plain).foregroundStyle(theme.ink2)
            .help(label).accessibilityLabel(label)
    }
}

// =====================================================================
// Themed buttons — one grammar, three ranks, the single brand 4px corner.
// =====================================================================
struct RDPrimaryButton: ButtonStyle {
    @Environment(\.theme) private var theme
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        RDButtonBody(theme: theme, rank: .primary, compact: compact, configuration: configuration)
    }
}

struct RDSecondaryButton: ButtonStyle {
    @Environment(\.theme) private var theme
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        RDButtonBody(theme: theme, rank: .secondary, compact: compact, configuration: configuration)
    }
}

private struct RDButtonBody: View {
    enum Rank { case primary, secondary }
    let theme: Theme
    let rank: Rank
    let compact: Bool
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, compact ? Space.s3 : Space.s4)
            .padding(.vertical, compact ? 6 : 9)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: Radius.soft).fill(bg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.soft)
                    .stroke(border, lineWidth: border == .clear ? 0 : 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
            .opacity(enabled ? 1 : 0.55)
    }

    private var pressed: Bool { configuration.isPressed }

    private var bg: Color {
        switch rank {
        case .primary:
            return pressed
                ? Color.greenPress : (hovering ? Color.greenHover : theme.accent)
        case .secondary:
            return hovering ? theme.cardActive : .clear
        }
    }
    private var fg: Color {
        switch rank {
        case .primary: return Color.onGreen
        case .secondary: return theme.ink1
        }
    }
    private var border: Color {
        rank == .secondary ? theme.hairline : .clear
    }
}

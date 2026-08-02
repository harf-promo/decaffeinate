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
    @EnvironmentObject var appState: AppState

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
        .frame(width: theme.popoverWidth)
        .frame(minHeight: Self.menuHeight, maxHeight: Self.maxMenuHeight)
        .background(theme.paper)
        // Refresh the live notification-permission status each time the menu
        // opens, so a denial/revocation the app wasn't told about at request
        // time is caught promptly rather than only at the next Settings visit.
        .onAppear { appState.refreshNotificationAuthorization() }
    }

    private var themedHairline: some View {
        Rectangle().fill(theme.hairline).frame(height: 1)
    }

    /// A screen-aware **minimum** height: tall enough for the list to breathe
    /// at the default text size. `maxMenuHeight` caps growth so the footer
    /// (Settings / quit / update) can't be pushed off-screen on a small
    /// display — but between the two, the popover is free to grow with larger
    /// Dynamic Type sizes instead of clipping its content.
    static var menuHeight: CGFloat {
        let available = NSScreen.main?.visibleFrame.height ?? 720
        return min(460, max(360, available * 0.8))
    }

    /// The hard ceiling — never taller than the visible screen under the menu
    /// bar, regardless of how large the content grows at big Dynamic Type sizes.
    static var maxMenuHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 720) * 0.92
    }
}

// ── Header: mark + outcome headline + one quiet meta-line, hugging its content ──
// The protected top third — the single answer to "will it sleep?" — so the
// restart/uptime nudge (a much lower-priority, occasional signal) has moved
// to the footer, where it can't compete with the verdict for attention.
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
                        .scaledFont(theme.headlineSize, weight: .semibold, relativeTo: .title2)
                        .foregroundStyle(theme.ink1)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !appState.detail.isEmpty {
                        Text(appState.detail)
                            .scaledFont(13, relativeTo: .callout)
                            .foregroundStyle(theme.ink3)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            // Sentence case at a readable size — this is the most scannable
            // status on the whole surface (what's the power source, what's
            // holding it, how long idle), so it gets real body-text treatment
            // instead of a decorative tracked eyebrow.
            Text(metaLine)
                .scaledFont(12, weight: .medium, relativeTo: .footnote)
                .foregroundStyle(theme.ink3)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Space.s2)
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.top, Space.s4)
    }

    /// "Battery 82% · 2 apps holding · Idle 4m" — neutral, never amber.
    private var metaLine: String {
        var parts: [String] = []
        if appState.power.onBattery, let pct = appState.power.chargePercent {
            parts.append("Battery \(pct)%")
        } else {
            parts.append("AC power")
        }
        let n = appState.activeHoldingCount
        if n > 0 { parts.append("\(n) app\(n == 1 ? "" : "s") holding") }
        if appState.idleSeconds >= 60 {
            parts.append("Idle " + Format.duration(appState.idleSeconds))
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

                // "Keep awake…" folds in the durations and Sleep-when-done watch
                // targets so they're accessible but not shouting.
                Menu {
                    Section("Keep awake") {
                        // Timed holds are the first-class, self-releasing path —
                        // they auto-expire, so the Mac can never be left awake by
                        // a forgotten toggle. Indefinite is a deliberate opt-in.
                        Button("30 minutes") { appState.stayAwake(forMinutes: 30) }
                        Button("1 hour") { appState.stayAwake(forMinutes: 60) }
                        Button("2 hours") { appState.stayAwake(forMinutes: 120) }
                        Button(untilWorkHoursLabel) {
                            appState.stayAwake(untilHour: settingsStore.settings.activeHoursEnd)
                        }
                        Divider()
                        Toggle("Keep awake indefinitely", isOn: settings.caffeinateEnabled)
                    }
                    Section {
                        Button("Turn display off") { appState.displayOff() }
                    }
                    Section("Sleep when done") {
                        if !appState.runningWatchCandidates.isEmpty {
                            ForEach(appState.runningWatchCandidates, id: \.self) { name in
                                Button(name) { appState.setWatchTarget(.processName(name)) }
                            }
                        }
                        ForEach(appState.commonWatchCandidates, id: \.self) { name in
                            Button(name) { appState.setWatchTarget(.processName(name)) }
                        }
                    }
                } label: {
                    Label("Keep awake\u{2026}", systemImage: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(RDSecondaryButton())
                .fixedSize()
                .help(
                    "Keep the Mac awake on purpose, or sleep it the moment a build or agent finishes."
                )
            }

            autoSleepRow

            RDActiveControls()

            if let error = appState.lastError {
                Text(error)
                    .scaledFont(11, relativeTo: .caption2)
                    .foregroundStyle(Color.critical)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.top, Space.s5)
        .padding(.bottom, theme.usesCards ? Space.s2 : Space.s4)
        // Sleep Now bypasses the app's own "never cuts off calls" promise
        // unless we ask first — this is that ask. The mic-active check that
        // arms it lives in `AppState.sleepNow()`.
        .alert(
            "You appear to be on a call",
            isPresented: Binding(
                get: { appState.pendingCallSleepConfirmation },
                set: { presented in
                    if !presented { appState.cancelSleepDuringCall() }
                })
        ) {
            Button("Cancel", role: .cancel) { appState.cancelSleepDuringCall() }
            Button("Sleep anyway", role: .destructive) { appState.confirmSleepDuringCall() }
        } message: {
            Text(
                "The microphone is in use, which usually means a call. Sleep anyway?"
            )
        }
    }

    /// Label for the "end of work day" quiet-window option — respects the user's
    /// configured active-hours end rather than hard-coding 6 PM.
    private var untilWorkHoursLabel: String {
        let h = settingsStore.settings.activeHoursEnd
        let suffix = h >= 12 ? "PM" : "AM"
        let display = h > 12 ? h - 12 : (h == 0 ? 12 : h)
        return "Until \(display) \(suffix)"
    }

    /// Auto-sleep toggle row — surfaces the master on/off without extra clutter.
    /// Keep-awake and Sleep-when-done controls live in the Keep awake… menu above.
    private var autoSleepRow: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "moon.zzz").scaledFont(12, relativeTo: .caption)
                .foregroundStyle(theme.ink3).accessibilityHidden(true)
            Text("Auto-sleep when idle")
                .scaledFont(13, relativeTo: .callout).foregroundStyle(theme.ink2)
            Spacer()
            Toggle("", isOn: settings.decaffeinateEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .help("Auto-sleep the Mac after you step away")
                .accessibilityLabel("Auto-sleep when idle")
                .accessibilityHint(
                    "Forces the Mac to sleep after you step away, overriding apps that hold it awake"
                )
        }
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
                let label = appState.watchTargetLabel
                row("binoculars.fill", label.map { "Stop watching \($0)" } ?? "Stop watching") {
                    appState.setWatchTarget(nil)
                }
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
                        .scaledFont(12, relativeTo: .caption).foregroundStyle(theme.ink2).lineLimit(1)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The firewall goes silently dead without this: if notifications
            // are denied (or later revoked in System Settings), say so instead
            // of just never notifying again with no explanation.
            if appState.notificationAuthorization == .denied {
                HStack(spacing: Space.s2) {
                    Image(systemName: "bell.slash.fill")
                        .font(.caption2).foregroundStyle(Color.warning).accessibilityHidden(true)
                    Text("Notifications: Off")
                        .scaledFont(12, relativeTo: .caption).foregroundStyle(theme.ink2)
                    Button("Enable") { Notifier.openSystemNotificationSettings() }
                        .buttonStyle(.plain)
                        .scaledFont(12, weight: .semibold, relativeTo: .caption)
                        .foregroundStyle(theme.accent)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Notifications are off")
                .accessibilityHint("Activate to open System Settings and enable them")
            }
        }
    }

    private func row(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: icon).font(.caption2).foregroundStyle(theme.ink3)
                .accessibilityHidden(true)
            Button(label, action: action).buttonStyle(.plain).foregroundStyle(theme.ink2)
                .scaledFont(12, weight: .medium, relativeTo: .caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// ── The list: one section label + the blocker rows ──
private struct RDList: View {
    @Environment(\.theme) private var theme
    @EnvironmentObject var appState: AppState
    @State private var showExplainer = false
    @State private var didAutoShow = false
    @State private var showAllHolders = false
    // The non-system section defaults collapsed — it's meaningfully lower
    // priority than "what's keeping your Mac awake" (it can't stop a sleep),
    // so it shouldn't compete with the primary section for visual weight.
    @State private var showOthers = false

    /// Beyond this many rows in the primary section, fold the rest behind a
    /// "show N more" row instead of an ever-growing unbounded list.
    private let foldThreshold = 6

    private var others: [PowerAssertion] { appState.sortedOtherBlockers }
    private func isPending(_ a: PowerAssertion) -> Bool { appState.isPendingDecision(a) }
    private func isPending(_ group: HoldGroup) -> Bool {
        group.members.contains { appState.isPendingDecision($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.usesCards ? theme.rowGap : 0) {
            if appState.assertions.isEmpty {
                RDSectionLabel(text: "Keeping your Mac awake", trailing: "all clear")
                emptyState
            } else {
                sectionHeader
                if showExplainer { explainerCard }
                if let verdict = appState.sleepBanner { verdictBanner(verdict) }
                groupRows(appState.groupedSystemBlockers)
                if !others.isEmpty {
                    othersDisclosure
                    if showOthers { rows(others) }
                }
            }
        }
        .onAppear {
            // Auto-open the explainer once, the first time there's something to explain.
            if !didAutoShow, !appState.settings.hasSeenAwakeExplainer, !appState.assertions.isEmpty
            {
                didAutoShow = true
                showExplainer = true
                appState.markAwakeExplainerSeen()
            }
        }
    }

    private var sectionHeader: some View {
        HStack {
            Text("Keeping your Mac awake").textCase(.uppercase)
                .scaledFont(11, weight: .semibold, relativeTo: .caption2).tracking(0.8)
                .foregroundStyle(theme.ink3)
                .lineLimit(1)
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showExplainer.toggle() }
            } label: {
                Image(systemName: "info.circle").scaledFont(12, relativeTo: .caption)
            }
            .buttonStyle(.plain).foregroundStyle(showExplainer ? theme.accent : theme.ink4)
            .help("What does this mean?")
            .accessibilityLabel("What's keeping your Mac awake?")
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.bottom, Space.s1)
    }

    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: Space.s1) {
            Text("What\u{2019}s keeping your Mac awake?")
                .scaledFont(12, weight: .semibold, relativeTo: .caption).foregroundStyle(theme.ink1)
            Text(
                "Each row shows something that asked macOS to stay awake. "
                    + "\u{2713} rows end on their own \u{2014} your Mac will sleep when the job is done. "
                    + "\u{26A0} rows hold indefinitely \u{2014} tap \u{22EF} for options. "
                    + "Tap a row for the full detail."
            )
            .scaledFont(12, relativeTo: .caption).foregroundStyle(theme.ink3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.s3)
        .background(RoundedRectangle(cornerRadius: Radius.soft).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.soft).stroke(theme.hairline, lineWidth: 1))
        .padding(.horizontal, theme.contentInset)
        .padding(.bottom, Space.s2)
    }

    /// One-line verdict banner across all system-sleep holds — a projection of the
    /// app's single `SleepOutlook`, so it can never contradict the header.
    private func verdictBanner(_ verdict: SleepVerdict) -> some View {
        HStack(spacing: Space.s2) {
            Image(systemName: verdict.glyph)
                .scaledFont(11, weight: .semibold, relativeTo: .caption2)
                .foregroundStyle(verdict.tone.color(theme))
                .accessibilityHidden(true)
            Text(verdict.text)
                .scaledFont(12, weight: .medium, relativeTo: .caption)
                .foregroundStyle(verdict.tone.color(theme))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.bottom, Space.s1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(verdict.text)
    }

    /// The primary rows, folded beyond `foldThreshold` — many-holder scaling
    /// (e.g. 15 agent sessions) shouldn't turn the menu into an unbounded
    /// scroll of full rows; the rest hide behind a "show N more" row. A group
    /// still awaiting an allow/ignore decision is never folded away, even
    /// past the threshold — the fold is a density fix, not a way to hide a
    /// pending approval the user hasn't seen yet.
    @ViewBuilder private func groupRows(_ list: [HoldGroup]) -> some View {
        let mustExpand =
            showAllHolders
            || (list.count > foldThreshold && list[foldThreshold...].contains(where: isPending))
        let visible = mustExpand ? list : Array(list.prefix(foldThreshold))
        ForEach(Array(visible.enumerated()), id: \.element.id) { idx, group in
            RDRow(group: group, pending: isPending(group))
            if !theme.usesCards && idx < visible.count - 1 {
                Rectangle().fill(theme.hairline).frame(height: 1)
                    .padding(.leading, theme.contentInset + Metrics.rowIcon + Space.s3)
            }
        }
        let folded = list.count - visible.count
        if folded > 0 {
            foldRow(count: folded) { withAnimation(.easeInOut(duration: 0.15)) { showAllHolders = true } }
        }
    }

    /// Non-system holds (screen-only / background) — always singleton rows,
    /// hidden behind `othersDisclosure` by default.
    @ViewBuilder private func rows(_ list: [PowerAssertion]) -> some View {
        ForEach(Array(list.enumerated()), id: \.element.id) { idx, a in
            RDRow(
                group: HoldGroup(
                    id: "solo:" + a.id, representative: a, members: [a],
                    isAgentSession: false, firstSeen: nil),
                pending: isPending(a))
            if !theme.usesCards && idx < list.count - 1 {
                Rectangle().fill(theme.hairline).frame(height: 1)
                    .padding(.leading, theme.contentInset + Metrics.rowIcon + Space.s3)
            }
        }
    }

    /// A "show N more" row — same visual grammar as `RDSectionLabel`, but
    /// tappable, so it reads as a natural continuation of the list rather than
    /// a new control.
    private func foldRow(count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s2) {
                Image(systemName: "chevron.down.circle").scaledFont(13, relativeTo: .callout)
                Text("Show \(count) more").scaledFont(12, weight: .medium, relativeTo: .caption)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.ink3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.contentInset)
        .padding(.vertical, Space.s2)
        .accessibilityLabel("Show \(count) more blockers")
    }

    /// The "screen-only / background" section header, as a disclosure toggle —
    /// these holds can't keep the system from sleeping, so they default
    /// collapsed instead of matching the primary section's visual weight.
    private var othersDisclosure: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { showOthers.toggle() }
        } label: {
            HStack {
                Image(systemName: showOthers ? "chevron.down" : "chevron.right")
                    .scaledFont(9, weight: .semibold, relativeTo: .caption2)
                Text("Screen-only / background").textCase(.uppercase)
                    .scaledFont(11, weight: .semibold, relativeTo: .caption2).tracking(0.8)
                    .lineLimit(1)
                Spacer()
                Text("\(others.count)")
                    .scaledFont(11, weight: .semibold, relativeTo: .caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(theme.ink4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, theme.contentInset)
        .padding(.top, theme.usesCards ? 0 : Space.s2)
        .padding(.bottom, Space.s1)
        .accessibilityLabel("Screen-only / background, \(others.count)")
        .accessibilityHint(showOthers ? "Double-tap to collapse" : "Double-tap to expand")
    }

    private var emptyState: some View {
        HStack(spacing: Space.s2) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(theme.teal)
            Text("Nothing is holding your Mac awake.")
                .scaledFont(14, relativeTo: .body).foregroundStyle(theme.ink2)
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
            Text(text).textCase(.uppercase).scaledFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(0.8).foregroundStyle(theme.ink3).lineLimit(1)
            Spacer()
            if let trailing {
                Text(trailing).textCase(.uppercase)
                    .scaledFont(11, weight: .semibold, relativeTo: .caption2)
                    .tracking(0.8).foregroundStyle(theme.ink4).lineLimit(1)
            }
        }
        .padding(.horizontal, theme.contentInset)
        .padding(.bottom, Space.s1)
    }
}

// ── One blocker row: icon · name + tag · two-tone context · (pending) 2 buttons ──
private struct RDRow: View {
    @Environment(\.theme) private var theme
    let group: HoldGroup
    var pending: Bool = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var rules: RulesEngine
    @State private var showDetails = false

    /// A stable stand-in for everything the row does; for an agent session this
    /// is the longest-lived member, so it doesn't flicker as pids churn.
    private var assertion: PowerAssertion { group.representative }
    private var policy: RulePolicy? { rules.policy(for: assertion) }

    /// "Claude Code · ~/myrepo" for an agent session, else the app's name.
    /// The row icon: a device-specific glyph for an unattributed audio hold (so
    /// AirPods / headphones / built-in read at a glance), else the app icon.
    @ViewBuilder private var rowIcon: some View {
        if assertion.realOwner == nil, assertion.bundleIdentifier == nil,
            let symbol = appState.audioDeviceSymbol(for: assertion)
        {
            Image(systemName: symbol)
                .scaledFont(15, relativeTo: .body)
                .foregroundStyle(theme.ink2)
                .frame(width: Metrics.rowIcon, height: Metrics.rowIcon)
        } else {
            AppIconView(assertion: assertion, size: Metrics.rowIcon)
        }
    }

    private var titleText: String {
        if group.isAgentSession, let crumb = appState.originCrumb(for: assertion) {
            return crumb
        }
        return assertion.displayName
    }

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
            rowIcon.padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Space.s2) {
                    Text(titleText)
                        .scaledFont(14, weight: .semibold, relativeTo: .callout)
                        .foregroundStyle(theme.ink1).lineLimit(1)
                    if !pending { tag }
                }
                contextText
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                // Plain-English answer: "Will sleep when the build finishes" / "Won't
                // sleep on its own — held until you act". Only for system-sleep holds
                // so a screen-only row never shows a spurious "won't sleep" warning.
                if !pending, assertion.blocksSystemSleep {
                    let v = appState.rowVerdict(for: assertion)
                    HStack(spacing: 4) {
                        Image(systemName: v.glyph)
                            .scaledFont(11, weight: .medium, relativeTo: .caption2)
                            .foregroundStyle(v.tone.color(theme))
                            .accessibilityHidden(true)
                        Text(v.text)
                            .scaledFont(12, relativeTo: .caption)
                            .foregroundStyle(v.tone.color(theme))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(v.text)
                    .padding(.top, 1)
                }
                if pending { approvalButtons.padding(.top, Space.s1) }
                if !pending, appState.shouldOfferWatch(for: assertion) { watchOffer }
            }

            Spacer(minLength: Space.s1)
            if !pending {
                // A persistent disclosure chevron — the only signal today that a
                // row is expandable was the one-time explainer card, gated behind
                // `hasSeenAwakeExplainer`. This is always visible and flips to
                // reflect the row's actual expanded state.
                Image(systemName: showDetails ? "chevron.down" : "chevron.right")
                    .scaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .foregroundStyle(theme.ink4)
                    .accessibilityHidden(true)
                rowMenu
            }
        }
        .padding(.horizontal, theme.usesCards ? Space.s3 : theme.contentInset)
        .padding(.vertical, theme.usesCards ? Space.s3 : Space.s2)
        .frame(minHeight: pending ? nil : theme.rowMinHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if !pending { withAnimation(.easeInOut(duration: 0.15)) { showDetails.toggle() } }
        }
        .accessibilityHint(pending ? "" : (showDetails ? "Double-tap to hide details" : "Double-tap to show details"))
    }

    private var contextText: some View {
        var t = Text(appState.displayReason(for: assertion)).foregroundStyle(theme.ink2)
        var tail: [String] = []
        if group.isAgentSession {
            // Origin is the title; show the STABLE held duration (anchored to the
            // session's first sighting, not the churny -t respawn) + live count.
            if let held = appState.sessionHeldDuration(for: assertion) {
                tail.append("held " + held.replacingOccurrences(of: "for ", with: ""))
            }
            if group.liveCount > 1 { tail.append("\(group.liveCount) live") }
        } else {
            if let origin = appState.originCrumb(for: assertion) {
                tail.append(origin)
            } else if let attribution = assertion.attribution {
                tail.append(attribution)
            }
            // Name the audio device, unless it's already this row's title (an
            // unattributed audio hold is titled by its device).
            if let device = appState.audioDeviceLabel(for: assertion), device != titleText {
                tail.append(device)
            }
            if let held = appState.heldDuration(assertion) {
                tail.append("held " + held.replacingOccurrences(of: "for ", with: ""))
            }
            if let secs = assertion.reason.autoReleaseSeconds {
                tail.append("auto-releases in \(secs)s")
            }
        }
        // CPU evidence: this holder has been idle so long it's likely a leaked hold.
        if let stale = appState.staleLabel(for: assertion) { tail.append(stale) }
        if !tail.isEmpty {
            t = t + Text(" · " + tail.joined(separator: " · ")).foregroundStyle(theme.ink4)
        }
        return t.scaledFont(12, relativeTo: .caption)
    }

    /// One-click "Sleep when it finishes" for an agentic `caffeinate -w` hold,
    /// plus a dismiss — non-nagging, menu-only.
    @ViewBuilder private var watchOffer: some View {
        if let target = appState.agentWaitTarget(for: assertion) {
            HStack(spacing: Space.s2) {
                Button {
                    appState.setWatchTarget(.pid(target.pid))
                } label: {
                    Label("Sleep when it finishes", systemImage: "binoculars")
                }
                .buttonStyle(RDSecondaryButton(compact: true))
                .fixedSize()
                .help("Watch \(target.label) and put the Mac to sleep once it's done.")
                Button {
                    appState.dismissWatchSuggestion(forHolder: assertion.pid)
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.ink4)
                .help("Dismiss")
                .accessibilityLabel("Dismiss suggestion")
                Spacer(minLength: 0)
            }
            .padding(.top, Space.s1)
        }
    }

    @ViewBuilder private var tag: some View {
        switch policy {
        case .allow, .allowUntil:
            // Route through RulePolicy.shortLabel so menu tag and Settings pill
            // always read the same word.
            let label = policy?.shortLabel ?? ""
            HStack(spacing: Space.s1) {
                Circle().fill(theme.teal).frame(width: 5, height: 5)
                Text(label)
                    .textCase(.uppercase).scaledFont(10, weight: .semibold, relativeTo: .caption2)
                    .tracking(0.7).foregroundStyle(theme.ink3).lineLimit(1)
            }
        case .ignore:
            Text(RulePolicy.ignore.shortLabel)
                .textCase(.uppercase).scaledFont(10, weight: .semibold, relativeTo: .caption2)
                .tracking(0.7).foregroundStyle(theme.ink4).lineLimit(1)
        case .none:
            EmptyView()
        }
    }

    private var approvalButtons: some View {
        HStack(spacing: Space.s2) {
            Button(RulePolicy.allow.menuActionLabel) {
                appState.setPolicy(.allow, for: assertion)
            }
            .buttonStyle(RDPrimaryButton(compact: true))
            .fixedSize()
            .accessibilityLabel(
                "Always allow \(assertion.displayName) to keep the Mac awake"
            )
            Button(RulePolicy.ignore.menuActionLabel) {
                appState.setPolicy(.ignore, for: assertion)
            }
            .buttonStyle(RDSecondaryButton(compact: true))
            .fixedSize()
            .accessibilityLabel(
                "Sleep anyway — ignore \(assertion.displayName) and force sleep when idle"
            )
            AllowForMenu(title: RulePolicy.allowUntil(Date()).menuActionLabel, assertion: assertion)
                .menuStyle(.borderlessButton)
                .tint(theme.ink3)
                .fixedSize()
                .accessibilityLabel("Allow \(assertion.displayName) for a set time")
            Spacer(minLength: 0)
        }
    }

    private var rowMenu: some View {
        Menu {
            Button(RulePolicy.allow.menuActionLabel) {
                appState.setPolicy(.allow, for: assertion)
            }
            AllowForMenu(title: "Allow for\u{2026}", assertion: assertion)
            Button(RulePolicy.ignore.menuActionLabel) {
                appState.setPolicy(.ignore, for: assertion)
            }
            if policy != nil {
                Button("Clear rule") { appState.clearRule(for: assertion) }
            }
            Divider()
            if let app = appState.frontableAppName(for: assertion) {
                Button("Bring \(app) to front") { appState.bringToFront(assertion) }
            }
            Button("Show in Activity Monitor") { appState.openActivityMonitor() }
            Button("Copy details") { appState.copyDetails(assertion) }
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

// ── Footer: restart nudge · slept-ago / update · Settings · quit ──
private struct RDFooter: View {
    @Environment(\.theme) private var theme
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var updater: UpdaterController

    var body: some View {
        VStack(spacing: 0) {
            // The uptime/restart nudge lives here, not the header — it's a much
            // lower-priority, occasional signal than "will it sleep?" and
            // shouldn't compete with the verdict for the top third's attention.
            if let hint = appState.restartHint {
                HStack(spacing: Space.s1) {
                    Image(systemName: "arrow.clockwise").scaledFont(10, relativeTo: .caption2)
                    Text(hint).lineLimit(1).truncationMode(.tail)
                }
                .scaledFont(11, relativeTo: .caption2)
                .foregroundStyle(appState.restartAdvice == .urgent ? Color.warning : theme.ink4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, theme.contentInset)
                .padding(.top, Space.s2)
            }

            HStack(spacing: Space.s3) {
                if updater.updateAvailable {
                    Button {
                        updater.checkForUpdatesUserInitiated()
                    } label: {
                        Label("Update available", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(RDPrimaryButton(compact: true))
                    .fixedSize()
                    .help("A new version of Decaffeinate is ready — click to install.")
                } else if let last = appState.lastSleepAt {
                    Label(
                        "Slept \(Format.relative(since: last))",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .scaledFont(11, relativeTo: .caption2).foregroundStyle(theme.ink3)
                }
                Spacer()
                // Routine "Check for Updates…" lives in Settings → About now; the
                // menu only surfaces the green button above when there's
                // genuinely an update.
                Button {
                    SettingsWindowOpener.open(openSettings)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .scaledFont(12, weight: .medium, relativeTo: .caption)
                }
                .buttonStyle(.plain).foregroundStyle(theme.ink2)
                .help("Open Settings").accessibilityLabel("Settings")
                iconButton("power", "Quit Decaffeinate") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, theme.contentInset)
            .padding(.vertical, Space.s2)
        }
    }

    private func iconButton(_ icon: String, _ label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) { Image(systemName: icon) }
            .buttonStyle(.plain).foregroundStyle(theme.ink2)
            .help(label).accessibilityLabel(label)
    }
}

/// Opens the `Settings` scene reliably from the menu-bar popover across macOS
/// 14–26. SwiftUI's `openSettings()` / `SettingsLink` silently no-op from a
/// `MenuBarExtra` on macOS 26 Tahoe — an `.accessory` app has no active render
/// tree behind the popover (verified: mjtsai.com 2025/06/18, Apple Forums 731628).
/// So: (1) bring the app forward, (2) ask SwiftUI to open Settings, and
/// (3) fall back to the AppKit responder-chain selector the `Settings` scene
/// installs. Both routes target the one Settings window, so whichever the running
/// OS honours wins and the other is a harmless re-focus. `showSettingsWindow:` is
/// the Ventura+ selector; the app's floor is macOS 14, so the pre-Ventura
/// `showPreferencesWindow:` isn't needed.
@MainActor
enum SettingsWindowOpener {
    static func open(_ openSettings: OpenSettingsAction) {
        NSApp.activate(ignoringOtherApps: true)  // .accessory app must front itself first
        openSettings()  // works on macOS 14/15
        let selector = NSSelectorFromString("showSettingsWindow:")
        if NSApp.responds(to: selector) {  // fallback for 26 where openSettings no-ops
            NSApp.sendAction(selector, to: nil, from: nil)
        }
    }
}

extension SleepTone {
    /// Map the outlook tone to the menu's design-system colours: teal for the
    /// "will sleep" states (green is reserved as one-mark punctuation for Sleep
    /// Now), amber only for the genuinely-won't-sleep states.
    func color(_ theme: Theme) -> Color {
        switch self {
        case .positive, .calm: return theme.teal
        case .warning: return Color.warning
        }
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
            .scaledFont(compact ? 12 : 14, weight: .medium, relativeTo: compact ? .caption : .callout)
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

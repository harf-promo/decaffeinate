import SwiftUI

/// A small info chip, e.g. "🔋 82%" or "Idle 4m" — a stamped Harf tag: sharp 4px
/// corner, hairline border in the tint, no fill.
struct Chip: View {
    var systemImage: String?
    var text: String
    var tint: Color = .ink3

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(HarfFont.micro)
        .foregroundStyle(tint)
        .padding(.horizontal, Space.s2)
        .padding(.vertical, 2)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.soft)
                .stroke(tint.opacity(0.35), lineWidth: 1))
    }
}

/// A reusable "Allow for…" submenu offering the standard duration presets.
/// Used by both the firewall prompt and the per-app row menu.
struct AllowForMenu: View {
    let title: String
    let assertion: PowerAssertion
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu(title) {
            ForEach(AllowDuration.allCases, id: \.self) { duration in
                Button(duration.label) {
                    appState.setPolicy(.allowUntil(duration.expiry(from: Date())), for: assertion)
                }
            }
        }
    }
}

/// The expandable per-assertion detail: the full "why + as much detail as
/// macOS exposes" — reason, resources, real owner, how long held, auto-release,
/// type, bundle path, and the raw system reason. All copyable.
struct AssertionDetailView: View {
    let assertion: PowerAssertion
    @EnvironmentObject var appState: AppState

    var body: some View {
        let reason = assertion.reason
        let provenance = appState.provenance(for: assertion.pid)
        VStack(alignment: .leading, spacing: Space.s2) {
            if !reason.resourceLabels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(reason.resourceLabels, id: \.self) { label in
                        Chip(systemImage: resourceIcon(label), text: label, tint: .info)
                    }
                }
            }
            // The enriched "why" — for a caffeinate hold this spells out exactly
            // what it's preventing and what it's waiting on.
            row("Why", appState.displayReason(for: assertion))

            // Which audio device — so several audio sources are distinguishable.
            let devices = appState.audioDevices(for: assertion)
            if !devices.isEmpty { row("Device", devices.joined(separator: ", ")) }

            // Where it came from — the window / agent / project behind the hold.
            if let p = provenance {
                if let started = p.originDisplayName { row("Started by", started) }
                if let folder = p.cwd.flatMap(ProcessProvenance.relativizeHome) {
                    row("Folder", folder)
                }
                if let tty = p.ttyName { row("Terminal", tty) }
            }

            // Who's really behind it — the daemon vs the real app, and the app it
            // was created on behalf of.
            row("Held by", assertion.processName)
            if let owner = assertion.realOwner {
                row(
                    "Real app", owner.bundleIdentifier.map { "\(owner.name) (\($0))" } ?? owner.name
                )
            }
            if assertion.viaRunningboard { row("Routed via", "runningboardd (background app)") }
            // Held duration anchored to the session's first sighting, so an agent's
            // `caffeinate -t` respawn doesn't reset it.
            if let secs = appState.sessionHeldSeconds(for: assertion) {
                row("Held for", Format.duration(secs))
            }
            if let anchor = appState.sessionAnchor(for: assertion) {
                row("Holding since", anchor.formatted(date: .abbreviated, time: .shortened))
            } else if let created = assertion.createdAt {
                row("Holding since", created.formatted(date: .abbreviated, time: .shortened))
            }
            if appState.isAgentSession(assertion), let created = assertion.createdAt {
                row(
                    "This process", "started " + created.formatted(date: .omitted, time: .shortened)
                )
            }
            // How the hold ends — until a task finishes / on a timer / indefinite.
            row("Ends", appState.holdLifetime(for: assertion).detailLabel)
            if let secs = reason.autoReleaseSeconds { row("Auto-releases", "in \(secs)s") }
            if let p = provenance, !p.holderArgv.isEmpty {
                row("Command", p.holderArgv.joined(separator: " "))
            }
            if let path = assertion.bundlePath { row("Where", path) }
            row("Type", assertion.assertionType)
            if let details = assertion.details, !details.isEmpty { row("App context", details) }
            if let raw = assertion.humanReadableReason, !raw.isEmpty { row("System reason", raw) }
            row("Assertion", assertion.name)
            row("PID", "\(assertion.pid)")
        }
        .font(HarfFont.caption)
        // Align under the row text, indented past the icon.
        .padding(.leading, Space.s3 + Metrics.rowIcon + Space.s2)
        .padding(.trailing, Space.s3)
        .padding(.vertical, Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paper2)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s2) {
            Text(key)
                .foregroundStyle(Color.ink4)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .foregroundStyle(Color.ink1)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func resourceIcon(_ label: String) -> String {
        switch label {
        case "Microphone": return "mic.fill"
        case "Speaker": return "speaker.wave.2.fill"
        case "Network": return "antenna.radiowaves.left.and.right"
        default: return "cpu"
        }
    }
}

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

/// The tracked UPPERCASE section eyebrow used between menu sections.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).eyebrow()
            Spacer()
            if let trailing {
                Text(trailing).eyebrow(.ink4)
            }
        }
        .padding(.horizontal, Space.s3)
        .padding(.top, Space.s2)
        .padding(.bottom, 2)
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

extension View {
    /// The small muted explanatory text style used under settings/menu controls.
    func explanatory() -> some View {
        font(HarfFont.caption).foregroundStyle(Color.ink3)
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
        VStack(alignment: .leading, spacing: 5) {
            if !reason.resourceLabels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(reason.resourceLabels, id: \.self) { label in
                        Chip(systemImage: resourceIcon(label), text: label, tint: .info)
                    }
                }
                .padding(.bottom, 2)
            }
            row("Why", reason.explanation)
            if let owner = assertion.realOwner { row("Real owner", owner.name) }
            if let held = appState.heldDuration(assertion) {
                row("Held", held.replacingOccurrences(of: "for ", with: ""))
            }
            if let secs = reason.autoReleaseSeconds { row("Auto-releases", "in \(secs)s") }
            row("Type", assertion.assertionType)
            if let raw = assertion.humanReadableReason, !raw.isEmpty { row("System reason", raw) }
            if let path = assertion.bundlePath { row("Bundle", path) }
            row("Assertion", assertion.name)
            row("PID", "\(assertion.pid)")
        }
        .font(HarfFont.micro)
        .padding(.horizontal, Space.s3)
        .padding(.vertical, Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paper2)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Space.s2) {
            Text(key).foregroundStyle(Color.ink4).frame(width: 86, alignment: .leading)
            Text(value).foregroundStyle(Color.ink2).textSelection(.enabled).lineLimit(3)
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

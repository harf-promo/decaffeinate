import SwiftUI

/// A small rounded info pill, e.g. "🔋 82%" or "Idle 4m".
struct Chip: View {
    var systemImage: String?
    var text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
            }
            Text(text)
        }
        .font(.caption2)
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Uppercased, muted section header used between menu sections.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }
}

extension AssertionKind {
    var tint: Color {
        switch self {
        case .systemSleep: return .orange
        case .displaySleep: return .blue
        case .other: return .secondary
        }
    }

    var glyph: String {
        switch self {
        case .systemSleep: return "sun.max.fill"
        case .displaySleep: return "display"
        case .other: return "circle.dotted"
        }
    }
}

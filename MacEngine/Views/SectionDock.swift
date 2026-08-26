import SwiftUI

struct DockSection<Tag: Hashable>: Identifiable {
    let tag: Tag
    let title: String
    let symbol: String

    var id: Tag { tag }
}

struct SectionDock<Tag: Hashable>: View {
    let sections: [DockSection<Tag>]
    @Binding var selection: Tag
    var tint: Color = Theme.cpu

    var body: some View {
        HStack(spacing: 3) {
            ForEach(sections) { section in
                DockButton(
                    section: section,
                    isSelected: section.tag == selection,
                    tint: tint
                ) {
                    selection = section.tag
                }
            }
        }
        .padding(4)
        .background(Theme.surface.opacity(0.9), in: .capsule)
        .overlay {
            Capsule().strokeBorder(Theme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 14, y: 5)
        .animation(.snappy(duration: 0.22), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sections")
    }
}

private struct DockButton<Tag: Hashable>: View {
    let section: DockSection<Tag>
    let isSelected: Bool
    let tint: Color
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: section.symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(section.title)
                    .font(.metricCaption)
                    .kerning(0.9)
                    .textCase(.uppercase)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(tint.opacity(isSelected ? 0.18 : 0))
                    .overlay {
                        Capsule().strokeBorder(tint.opacity(isSelected ? 0.55 : 0), lineWidth: 1)
                    }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var foreground: Color {
        if isSelected { return Theme.ink }
        return isHovering ? Theme.inkSecondary : Theme.inkTertiary
    }
}

struct EngineerGate: View {
    let what: String
    @Binding var engineerMode: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cpu")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
            Text(what)
                .font(.engineBody)
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Turn On Engineer Mode") { engineerMode = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

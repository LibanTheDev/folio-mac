import AppKit
import SwiftUI

extension Color {
    /// A color that resolves differently in light and dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

/// Warm "paper" palette.
enum Theme {
    static let canvas = Color.dynamic(light: 0xFBF8F3, dark: 0x1C1916)
    static let sidebar = Color.dynamic(light: 0xF3EEE6, dark: 0x221E1A)
    static let column = Color.dynamic(light: 0xF4EFE8, dark: 0x24201C)
    static let card = Color.dynamic(light: 0xFFFFFF, dark: 0x2C2722)
    static let border = Color.dynamic(light: 0xE6DED1, dark: 0x3A332B)
    static let ink = Color.dynamic(light: 0x2A231B, dark: 0xEFE7DA)
    static let muted = Color.dynamic(light: 0x8B7F6F, dark: 0xA49886)
    static let faint = Color.dynamic(light: 0xC2B8A9, dark: 0x6A6155)
    static let accent = Color.dynamic(light: 0x5B4631, dark: 0xD8B98D)
    static let onAccent = Color.dynamic(light: 0xFFFBF5, dark: 0x1C1916)
    static let accentSoft = Color.dynamic(light: 0xEADFCF, dark: 0x3A3128)
    static let chip = Color.dynamic(light: 0xF5F0E8, dark: 0x332D26)
    static let heart = Color.dynamic(light: 0x5B4631, dark: 0xE0A48C)

    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .padding(.vertical, 9)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
            .contentShape(Rectangle())
    }
}

struct PillButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, selected: selected)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.ink : Theme.muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Theme.accentSoft : hovering ? Theme.accentSoft.opacity(0.5) : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostBody(configuration: configuration)
    }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering || configuration.isPressed ? Theme.accentSoft.opacity(0.7) : Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.border))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, selected: selected)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .foregroundStyle(selected ? Theme.ink : Theme.muted)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Theme.accentSoft : hovering ? Theme.accentSoft.opacity(0.5) : .clear))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Small building blocks

struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.border))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + sz.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(Theme.serif(32, .medium))
                .foregroundStyle(Theme.ink)
            if let caption {
                Text(caption.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, caption: String? = nil) {
        self.init(title: title, caption: caption) { EmptyView() }
    }
}

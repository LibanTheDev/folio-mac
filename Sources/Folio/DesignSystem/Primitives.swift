import AppKit
import SwiftUI

// MARK: - Native vibrancy

/// Native `NSVisualEffectView` (real blur and vibrancy, not a bitmap).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var emphasized = false

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = state
        v.isEmphasized = emphasized
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.state = state
        v.isEmphasized = emphasized
    }
}

/// Configures the hosting `NSWindow` for a full-height, translucent, titlebar-integrated layout.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = false
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Glass surfaces

enum GlassLevel {
    /// Large floating panels (sidebar, inspector).
    case panel
    /// Cards sitting on the content background.
    case card
    /// Small controls (inputs, chips, segmented tracks).
    case control
}

struct GlassBackground: ViewModifier {
    var level: GlassLevel = .card
    var cornerRadius: CGFloat = DS.Radius.card
    var hovering = false
    var selected = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    switch level {
                    case .panel:
                        VisualEffectView(material: .sidebar, blending: .behindWindow)
                    case .card:
                        shape.fill(.regularMaterial)
                        shape.fill(DS.surface)
                    case .control:
                        shape.fill(DS.surfaceElevated)
                    }
                    if hovering { shape.fill(DS.surface.opacity(0.6)) }
                }
                .clipShape(shape)
            }
            // Hairline border, plus a soft specular highlight along the top edge.
            .overlay(shape.strokeBorder(selected ? DS.accent.opacity(0.85) : hovering ? DS.strokeStrong : DS.stroke, lineWidth: selected ? 1.5 : 1))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [DS.highlight, DS.highlight.opacity(0)], startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
                .blendMode(.plusLighter)
                .opacity(level == .control ? 0.6 : 1)
            )
            .shadow(color: .black.opacity(level == .panel ? 0.14 : hovering ? 0.10 : 0.05),
                    radius: level == .panel ? 18 : hovering ? 10 : 4,
                    y: level == .panel ? 6 : hovering ? 4 : 1.5)
    }
}

extension View {
    func glass(_ level: GlassLevel = .card, cornerRadius: CGFloat = DS.Radius.card, hovering: Bool = false, selected: Bool = false) -> some View {
        modifier(GlassBackground(level: level, cornerRadius: cornerRadius, hovering: hovering, selected: selected))
    }

    /// Hover-tracking glass card with a gentle lift.
    func hoverGlass(cornerRadius: CGFloat = DS.Radius.card, selected: Bool = false) -> some View {
        modifier(HoverGlass(cornerRadius: cornerRadius, selected: selected))
    }
}

private struct HoverGlass: ViewModifier {
    var cornerRadius: CGFloat
    var selected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .glass(.card, cornerRadius: cornerRadius, hovering: hovering, selected: selected)
            .offset(y: hovering && !reduceMotion ? -1.5 : 0)
            .onHover { hovering = $0 }
            .motion(Motion.gentle, value: hovering)
    }
}

/// Standard frosted card container.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.card)
    }
}

/// Content-area backdrop: translucent pearl/charcoal tint with a faint cool atmosphere.
struct AtmosphereBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            DS.background
            RadialGradient(colors: [DS.accent.opacity(scheme == .dark ? 0.10 : 0.08), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 700)
            RadialGradient(colors: [Color(hue: 0.62, saturation: 0.25, brightness: scheme == .dark ? 0.5 : 0.9).opacity(0.10), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, fullWidth: fullWidth)
    }

    private struct PrimaryBody: View {
        let configuration: ButtonStyleConfiguration
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(DS.onAccent)
                .padding(.vertical, 7.5)
                .padding(.horizontal, 14)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .background(
                    shape.fill(LinearGradient(colors: [DS.accentSecondary, DS.accent], startPoint: .top, endPoint: .bottom))
                        .brightness(configuration.isPressed ? -0.06 : hovering ? 0.03 : 0)
                )
                .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)))
                .shadow(color: DS.accent.opacity(0.25), radius: hovering ? 6 : 3, y: 1.5)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
    }
}

/// Frosted secondary button.
struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        GlassButtonBody(configuration: configuration)
    }

    private struct GlassButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(DS.textPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .glass(.control, cornerRadius: DS.Radius.control, hovering: hovering)
                .brightness(configuration.isPressed ? -0.04 : 0)
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Text-only button that gains a subtle fill on hover.
struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { GhostBody(configuration: configuration) }

    private struct GhostBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(hovering || configuration.isPressed ? DS.fill : .clear))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var selected = false
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration, selected: selected, size: size)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let size: CGFloat
        @State private var hovering = false
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(selected ? DS.accent : hovering ? DS.textPrimary : DS.textSecondary)
                .frame(width: size, height: size - 2)
                .background(RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(selected ? DS.selection : hovering || configuration.isPressed ? DS.fill : .clear))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Top-level navigation pill.
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
                .font(.system(size: 12, weight: selected ? .semibold : .medium))
                .foregroundStyle(selected ? DS.textPrimary : DS.textSecondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background {
                    if selected {
                        Capsule().fill(DS.surfaceElevated)
                            .overlay(Capsule().strokeBorder(DS.stroke))
                            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
                    } else if hovering {
                        Capsule().fill(DS.fill)
                    }
                }
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - Segmented control

struct GlassSegmented<Value: Hashable, Label: View>: View {
    @Binding var selection: Value
    let options: [Value]
    var disabled: (Value) -> Bool = { _ in false }
    @ViewBuilder var label: (Value) -> Label
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { Motion.perform { selection = option } } label: {
                    label(option)
                        .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                        .foregroundStyle(isOn ? DS.textPrimary : DS.textSecondary)
                        .padding(.horizontal, 9)
                        .frame(minWidth: 28, minHeight: 24)
                        .background {
                            if isOn {
                                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                                    .fill(DS.surfaceElevated)
                                    .shadow(color: .black.opacity(0.10), radius: 1.5, y: 0.5)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(disabled(option))
                .opacity(disabled(option) ? 0.4 : 1)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).fill(DS.fill))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous).strokeBorder(DS.stroke))
    }
}

// MARK: - Search field

struct GlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}
    var onEscape: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.textTertiary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused(focus)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onEscape)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.textTertiary)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .glass(.control, cornerRadius: DS.Radius.control, selected: focus.wrappedValue)
    }
}

// MARK: - Sheets

/// Standard frosted sheet chrome: title bar, content, and a footer of actions.
struct SheetContainer<Content: View, Footer: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.serif(20, .semibold))
                    if let subtitle { Text(subtitle).font(DS.Text.callout).foregroundStyle(DS.textSecondary) }
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 12)
            content
            Divider().overlay(DS.stroke)
            HStack(spacing: 8) { footer }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
        }
        .background(VisualEffectView(material: .popover, blending: .behindWindow))
        .background(DS.background.opacity(0.5))
        .foregroundStyle(DS.textPrimary)
        .tint(DS.accent)
    }
}

// MARK: - Headers

struct PageHeader<Trailing: View>: View {
    let title: String
    var caption: String?
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if let caption {
                    Text(caption.uppercased())
                        .font(DS.Text.eyebrow)
                        .tracking(0.9)
                        .foregroundStyle(DS.textTertiary)
                }
                Text(title)
                    .font(DS.Text.display)
                    .foregroundStyle(DS.textPrimary)
                if let subtitle {
                    Text(subtitle).font(DS.Text.body).foregroundStyle(DS.textSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, caption: String? = nil, subtitle: String? = nil) {
        self.init(title: title, caption: caption, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title).font(DS.Text.sectionTitle).foregroundStyle(DS.textPrimary)
            if let subtitle { Text(subtitle).font(DS.Text.callout).foregroundStyle(DS.textTertiary) }
            Spacer()
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - Tags

struct Chip: View {
    let text: String
    var selected = false
    var body: some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(selected ? DS.accent : DS.textSecondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(selected ? DS.selection : DS.fill))
            .overlay(Capsule().strokeBorder(DS.stroke.opacity(0.7)))
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

// MARK: - Progress

struct ProgressBar: View {
    var value: Double
    var tint: Color = DS.accent
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(DS.fill)
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .motion(Motion.spring, value: value)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

struct ProgressRing: View {
    var value: Double
    var lineWidth: CGFloat = 8
    var tint: Color = DS.accent

    var body: some View {
        ZStack {
            Circle().stroke(DS.fill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, value)))
                .stroke(AngularGradient(colors: [DS.accentSecondary, tint, tint], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .motion(Motion.spring, value: value)
    }
}

// MARK: - Empty state

struct EmptyStateView<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(DS.textTertiary)
                .frame(width: 64, height: 64)
                .glass(.card, cornerRadius: 18)
            Text(title).font(DS.serif(20, .semibold))
            Text(message)
                .font(DS.Text.body)
                .foregroundStyle(DS.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) { actions }.padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(icon: String, title: String, message: String) {
        self.init(icon: icon, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Stat card

struct StatCard: View {
    let value: String
    let label: String
    var icon: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(DS.selection))
                Spacer()
            }
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(DS.Text.callout).foregroundStyle(DS.textSecondary)
            if let footnote {
                Text(footnote).font(DS.Text.micro).foregroundStyle(DS.textTertiary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hoverGlass()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Sidebar row

struct SidebarRow: View {
    let title: String
    let icon: String
    var count: Int?
    let selected: Bool
    var muted = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12.5, weight: .regular))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 18)
                    .foregroundStyle(selected ? DS.accent : DS.textSecondary)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(muted ? DS.textSecondary : DS.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(DS.textTertiary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.small + 1, style: .continuous)
                    .fill(selected ? DS.selection : hovering ? DS.fill : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(Motion.gentle, value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SidebarSectionTitle: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(DS.textTertiary)
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 5)
    }
}

// MARK: - Text fields

struct GlassFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.system(size: 12.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 6.5)
            .glass(.control, cornerRadius: DS.Radius.small + 1)
    }
}

/// Labelled form row used in sheets and settings.
struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(DS.Text.caption.weight(.medium)).foregroundStyle(DS.textSecondary)
            content
        }
    }
}

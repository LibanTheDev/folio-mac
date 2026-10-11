import AppKit
import SwiftUI

extension Color {
    /// A color that resolves differently in light and dark appearance.
    static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

/// Folio design tokens. Views use these semantic names, never raw colors.
enum DS {
    // MARK: Surfaces
    /// Base tint laid over the window's vibrancy in the content area (pearl / deep charcoal).
    static let background = Color.dynamic(light: 0xF2F4F8, dark: 0x15171B, lightAlpha: 0.80, darkAlpha: 0.84)
    /// Tint applied on top of a material to make a frosted card.
    static let surface = Color.dynamic(light: 0xFFFFFF, dark: 0x2A2E35, lightAlpha: 0.55, darkAlpha: 0.45)
    /// Stronger surface for small elevated controls (inputs, popovers).
    static let surfaceElevated = Color.dynamic(light: 0xFFFFFF, dark: 0x30353D, lightAlpha: 0.82, darkAlpha: 0.75)
    /// Recessed area such as board columns.
    static let well = Color.dynamic(light: 0x1B2433, dark: 0xFFFFFF, lightAlpha: 0.035, darkAlpha: 0.035)
    /// Neutral fill for chips and segmented tracks.
    static let fill = Color.dynamic(light: 0x1B2433, dark: 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.07)

    // MARK: Lines
    static let stroke = Color.dynamic(light: 0x1B2433, dark: 0xFFFFFF, lightAlpha: 0.09, darkAlpha: 0.10)
    static let strokeStrong = Color.dynamic(light: 0x1B2433, dark: 0xFFFFFF, lightAlpha: 0.16, darkAlpha: 0.18)
    /// Specular edge highlight along the top of glass.
    static let highlight = Color.dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, lightAlpha: 0.85, darkAlpha: 0.13)

    // MARK: Text
    static let textPrimary = Color.dynamic(light: 0x1C1F24, dark: 0xE8EBF0)
    static let textSecondary = Color.dynamic(light: 0x5A616C, dark: 0xA2A9B4)
    static let textTertiary = Color.dynamic(light: 0x8E95A0, dark: 0x6C737E)

    // MARK: Accent
    static let accent = Color.dynamic(light: 0x3A78D0, dark: 0x86B4EE)
    static let accentSecondary = Color.dynamic(light: 0x6FA2E6, dark: 0x5C8FD6)
    static let onAccent = Color.dynamic(light: 0xFFFFFF, dark: 0x0D141F)
    static let selection = Color.dynamic(light: 0x3A78D0, dark: 0x86B4EE, lightAlpha: 0.13, darkAlpha: 0.18)
    static let favorite = Color.dynamic(light: 0xC9506E, dark: 0xEE8FA6)

    // MARK: Semantic status
    static let statusWant = Color.dynamic(light: 0x5B6B86, dark: 0xA3B4D0)
    static let statusReading = Color.dynamic(light: 0xB7791F, dark: 0xE8B25E)
    static let statusRead = Color.dynamic(light: 0x3F8A62, dark: 0x83C9A0)
    static let statusDNF = Color.dynamic(light: 0xA65454, dark: 0xE09090)

    // MARK: Data visualization
    /// Categorical series, assigned in this fixed order (validated for CVD separation in both modes).
    /// Light and dark are separate steps of the same hues, not an automatic flip.
    static let chartSeries: [Color] = [
        .dynamic(light: 0x2A78D6, dark: 0x3987E5),  // blue
        .dynamic(light: 0xEB6834, dark: 0xD95926),  // orange
        .dynamic(light: 0x1BAF7A, dark: 0x199E70),  // aqua
        .dynamic(light: 0xEDA100, dark: 0xC98500),  // yellow
        .dynamic(light: 0xE87BA4, dark: 0xD55181),  // magenta
        .dynamic(light: 0x008300, dark: 0x008300),  // green
        .dynamic(light: 0x4A3AA7, dark: 0x9085E9),  // violet
        .dynamic(light: 0xE34948, dark: 0xE66767),  // red
    ]
    /// Neutral for "Other" buckets.
    static let chartOther = Color.dynamic(light: 0xA3A9B3, dark: 0x6C727C)
    /// Single-series magnitude color (sequential blue).
    static let chartPrimary = Color.dynamic(light: 0x2A78D6, dark: 0x3987E5)
    /// Recessive grid lines.
    static let chartGrid = Color.dynamic(light: 0x1B2433, dark: 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.08)

    // MARK: Shape
    enum Radius {
        static let small: CGFloat = 6
        static let control: CGFloat = 8
        static let card: CGFloat = 12
        static let panel: CGFloat = 14
    }

    // MARK: Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let page: CGFloat = 28
    }

    // MARK: Typography
    /// Restrained serif (New York) reserved for literary headings: page titles and book titles.
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    enum Text {
        static let display = DS.serif(30, .semibold)
        static let title = DS.serif(21, .semibold)
        static let sectionTitle = Font.system(size: 15, weight: .semibold)
        static let headline = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 13)
        static let callout = Font.system(size: 12)
        static let caption = Font.system(size: 11)
        static let micro = Font.system(size: 10)
        static let eyebrow = Font.system(size: 10, weight: .semibold)
    }
}

// MARK: - Motion

enum Motion {
    static let standard = Animation.snappy(duration: 0.25)
    static let gentle = Animation.easeOut(duration: 0.18)
    static let spring = Animation.spring(duration: 0.35, bounce: 0.18)

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// `withAnimation` that respects the system Reduce Motion setting.
    static func perform<R>(_ animation: Animation = standard, _ body: () throws -> R) rethrows -> R {
        if reduceMotion { return try body() }
        return try withAnimation(animation, body)
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V
    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that becomes a no-op when Reduce Motion is on.
    func motion<V: Equatable>(_ animation: Animation = Motion.standard, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

import SwiftUI

/// Color tokens per docs/DESIGN_SPEC.md §3.1. Each token exposes a light and
/// dark value and resolves against the current `colorScheme` so the app
/// follows the system appearance by default.
enum Theme {

    // MARK: - Tokens

    static func bg(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x121110) : Color(hex: 0xF6F4F1)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x1B1A18) : Color(hex: 0xFFFFFF)
    }

    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF2F0EC) : Color(hex: 0x171614)
    }

    static func ink2(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF2F0EC, opacity: 0.60) : Color(hex: 0x171614, opacity: 0.60)
    }

    static func ink3(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF2F0EC, opacity: 0.32) : Color(hex: 0x171614, opacity: 0.36)
    }

    static func line(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF2F0EC, opacity: 0.12) : Color(hex: 0x171614, opacity: 0.10)
    }

    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xDE8E60) : Color(hex: 0xA4552E)
    }

    static func accentSoft(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xDE8E60, opacity: 0.15) : Color(hex: 0xA4552E, opacity: 0.10)
    }

    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0x242120) : Color(hex: 0xFFFDFB)
    }

    static func paperLine(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xF2F0EC, opacity: 0.17) : Color(hex: 0x171614, opacity: 0.13)
    }

    static func highlight(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: 0xE2B23E, opacity: 0.32) : Color(hex: 0xE2B23E, opacity: 0.55)
    }

    static func shadowColor(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.08)
    }

    static func shadowRadius(_ scheme: ColorScheme) -> CGFloat { 14 }

    // MARK: - Signature colors (§3.3)

    enum SignatureColor: String, CaseIterable, Codable, Identifiable, Hashable {
        case ink, blue, clay, green

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .ink: return "Ink"
            case .blue: return "Blue"
            case .clay: return "Clay"
            case .green: return "Green"
            }
        }

        func color(_ scheme: ColorScheme) -> Color {
            switch self {
            case .ink: return Theme.ink(scheme)
            case .blue: return Color(hex: 0x2C5EA8)
            case .clay: return Color(hex: 0xA4552E)
            case .green: return Color(hex: 0x2F6B4F)
            }
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

/// Convenience so views can read tokens as `theme.ink` etc. without threading
/// `colorScheme` through every call site.
struct ThemeTokens {
    let scheme: ColorScheme
    var bg: Color { Theme.bg(scheme) }
    var surface: Color { Theme.surface(scheme) }
    var ink: Color { Theme.ink(scheme) }
    var ink2: Color { Theme.ink2(scheme) }
    var ink3: Color { Theme.ink3(scheme) }
    var line: Color { Theme.line(scheme) }
    var accent: Color { Theme.accent(scheme) }
    var accentSoft: Color { Theme.accentSoft(scheme) }
    var paper: Color { Theme.paper(scheme) }
    var paperLine: Color { Theme.paperLine(scheme) }
    var highlight: Color { Theme.highlight(scheme) }
    var shadowColor: Color { Theme.shadowColor(scheme) }
}

private struct ThemeTokensKey: EnvironmentKey {
    static let defaultValue = ThemeTokens(scheme: .light)
}

extension EnvironmentValues {
    var theme: ThemeTokens {
        get { self[ThemeTokensKey.self] }
        set { self[ThemeTokensKey.self] = newValue }
    }
}

/// Applies `\.theme` from the current `colorScheme` automatically. Put this
/// once near the root and every descendant can read `@Environment(\.theme)`.
struct ThemeProvider: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        content.environment(\.theme, ThemeTokens(scheme: colorScheme))
    }
}

extension View {
    func withThemeProvider() -> some View { modifier(ThemeProvider()) }

    /// Card/paper drop shadow per DESIGN_SPEC §3.1.
    func paperShadow(_ theme: ThemeTokens) -> some View {
        self
            .shadow(color: theme.shadowColor, radius: 1, x: 0, y: 1)
            .shadow(color: theme.shadowColor, radius: 14, x: 0, y: 10)
    }
}

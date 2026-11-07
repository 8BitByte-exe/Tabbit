import SwiftUI
import UIKit

/// Tabbit's design tokens: soft clay surfaces lit from the top-left on clean white
/// (light) or charcoal (dark), with one mint brand color that's the same in both modes.
///
/// Every color, radius, spacing, shadow, font and animation used by the views
/// lives here. Views use the components in Components.swift instead of
/// repeating shadow code.
///
/// Depth means "you can touch this": raised clay is for buttons and tappable cards,
/// flat plates are for information, and inset wells are for typing and toggles.
enum Theme {

    // MARK: - Palette

    /// One color as hex for light and dark mode, with optional opacity.
    /// Kept as numbers so unit tests can check WCAG contrast without UIKit.
    struct Swatch {
        let light: UInt32
        let dark: UInt32
        var lightOpacity: Double = 1
        var darkOpacity: Double = 1

        /// The SwiftUI color, switching automatically with light/dark mode.
        var color: Color {
            return Color(uiColor: uiColor)
        }

        var uiColor: UIColor {
            let swatch = self
            return UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return Theme.uiColor(hex: swatch.dark, opacity: swatch.darkOpacity)
                }
                return Theme.uiColor(hex: swatch.light, opacity: swatch.lightOpacity)
            }
        }
    }

    /// All colors. Text colors pass WCAG AA (4.5:1) on every surface in both
    /// modes; ThemeContrastTests checks this in CI.
    enum Palette {
        // Surfaces: neutral, bright white in light mode and charcoal in dark mode.
        static let background = Swatch(light: 0xF3F4F6, dark: 0x1B1B1D)
        /// Raised clay fades from `surfaceHigh` (top-left, toward the light) to
        /// `surfaceLow` (bottom-right).
        static let surfaceHigh = Swatch(light: 0xFFFFFF, dark: 0x2A2A2D)
        static let surfaceLow = Swatch(light: 0xF0F1F4, dark: 0x202022)
        /// Pressed-in wells: fields, tracks, pressed buttons.
        static let inset = Swatch(light: 0xE8EAEE, dark: 0x141416)
        /// Flat information panels, with a hairline edge instead of a shadow.
        static let plate = Swatch(light: 0xFFFFFF, dark: 0x242427)
        static let hairline = Swatch(light: 0xE2E4E9, dark: 0x323236)

        // Text and icons (never pure black or white).
        static let text = Swatch(light: 0x1D1F23, dark: 0xECECEE)
        static let secondaryText = Swatch(light: 0x5A5F68, dark: 0xA3A3AA)

        // The brand mint: identical in light and dark mode. Only ever a fill,
        // with `onAccent` (dark) text and icons on it.
        static let accentHigh = Swatch(light: 0xA8EECB, dark: 0xA8EECB)
        static let accentLow = Swatch(light: 0x6ED6A4, dark: 0x6ED6A4)
        static let onAccent = Swatch(light: 0x112018, dark: 0x112018)
        /// Shadows under mint fills are softly mint-tinted in light mode, so the color stays clean.
        static let accentShade = Swatch(light: 0x3FBF85, dark: 0x000000, lightOpacity: 0.28, darkOpacity: 0.6)

        // Status fills (with `onPastel` text and always an icon).
        static let cautionFill = Swatch(light: 0xF7DFA8, dark: 0xF2D08A)
        static let dangerFill = Swatch(light: 0xF8CFCB, dark: 0xF2B8B3)

        // Status text, for short inline messages next to an icon.
        static let warning = Swatch(light: 0x8A5300, dark: 0xF2C063)
        static let danger = Swatch(light: 0xB3261E, dark: 0xFF8F87)

        // Lighting: one light source at the top-left.
        static let highlight = Swatch(light: 0xFFFFFF, dark: 0x3A3A3F, lightOpacity: 1, darkOpacity: 0.5)
        static let shade = Swatch(light: 0xB5BBC6, dark: 0x000000, lightOpacity: 0.5, darkOpacity: 0.6)
        /// A soft lit edge on the light side of raised clay.
        static let edge = Swatch(light: 0xFFFFFF, dark: 0x3C3C41, lightOpacity: 0.9, darkOpacity: 0.55)
        /// A visible outline for Reduce Transparency / Increase Contrast.
        static let outline = Swatch(light: 0x9AA0AA, dark: 0x5C5C63)

        /// Chart bars that aren't highlighted.
        static let chartMuted = Swatch(light: 0xE1E4E9, dark: 0x3A3A3F)
    }

    /// Shorthand for the SwiftUI colors.
    enum Colors {
        static let background = Palette.background.color
        static let surfaceHigh = Palette.surfaceHigh.color
        static let surfaceLow = Palette.surfaceLow.color
        static let inset = Palette.inset.color
        static let plate = Palette.plate.color
        static let hairline = Palette.hairline.color
        static let text = Palette.text.color
        static let secondaryText = Palette.secondaryText.color
        static let accentHigh = Palette.accentHigh.color
        static let accentLow = Palette.accentLow.color
        static let onAccent = Palette.onAccent.color
        static let accentShade = Palette.accentShade.color
        static let cautionFill = Palette.cautionFill.color
        static let dangerFill = Palette.dangerFill.color
        static let warning = Palette.warning.color
        static let danger = Palette.danger.color
        static let highlight = Palette.highlight.color
        static let shade = Palette.shade.color
        static let edge = Palette.edge.color
        static let outline = Palette.outline.color
        static let chartMuted = Palette.chartMuted.color
        static let onPastel = Theme.onPastel.color
    }

    enum Gradients {
        /// Raised clay: lighter toward the light (top-left), a touch darker away from it.
        static let surface = LinearGradient(
            colors: [Colors.surfaceHigh, Colors.surfaceLow], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let accent = LinearGradient(
            colors: [Colors.accentHigh, Colors.accentLow], startPoint: .topLeading, endPoint: .bottomTrailing)
        /// The soft lit edge, fading out well before the shaded side.
        static let edge = LinearGradient(
            colors: [Colors.edge, Color.clear], startPoint: .topLeading, endPoint: .center)
    }

    /// Soft pastel fills (avatars, category badges, chart segments). Dark text
    /// (`onPastel`) on any of them is at least 8:1.
    static let pastels: [Swatch] = [
        Swatch(light: 0xB9E8CF, dark: 0x9CD9B9),
        Swatch(light: 0xBFD9F5, dark: 0xA3C6EC),
        Swatch(light: 0xF6D3B5, dark: 0xEDC09B),
        Swatch(light: 0xE6CCF2, dark: 0xD5B5E6),
        Swatch(light: 0xF5C9CF, dark: 0xEBB0B9),
        Swatch(light: 0xD6E4B0, dark: 0xC3D594),
        Swatch(light: 0xC3EEEA, dark: 0xA6DFD9),
        Swatch(light: 0xF2E2A8, dark: 0xE6D18A),
        // Neutral, for "Other".
        Swatch(light: 0xDDE1E6, dark: 0xC4CAD2),
        Swatch(light: 0xD4D9F7, dark: 0xB9C1EE),
        Swatch(light: 0xFAD3E6, dark: 0xF0B9D3),
        Swatch(light: 0xCDEFF7, dark: 0xACE0EE),
    ]

    /// Text on pastel and status fills (both modes).
    static let onPastel = Swatch(light: 0x1D1F23, dark: 0x1D1F23)

    static func pastel(_ index: Int) -> Color {
        let count = pastels.count
        return pastels[((index % count) + count) % count].color
    }

    // MARK: - Shape

    enum Radius {
        static let card: CGFloat = 28
        static let tile: CGFloat = 20
        static let field: CGFloat = 18
        static let small: CGFloat = 12
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        /// Side margin for screens.
        static let screen: CGFloat = 20
    }

    enum Size {
        static let buttonHeight: CGFloat = 56
        static let compactButtonHeight: CGFloat = 44
        /// Minimum tap target (Apple's guideline is 44pt).
        static let tapTarget: CGFloat = 48
        static let fieldHeight: CGFloat = 50
        static let tabBarHeight: CGFloat = 68
        /// Height of the custom navigation header on pushed screens.
        static let headerHeight: CGFloat = 60
    }

    // MARK: - Shadows

    /// A drop-shadow pair: highlight toward the top-left, shade toward the bottom-right.
    struct Elevation {
        let offset: CGFloat
        /// SwiftUI shadow radius (about half of a design tool's "blur").
        let radius: CGFloat
    }

    enum Elevations {
        static let card = Elevation(offset: 6, radius: 12)
        static let control = Elevation(offset: 4, radius: 9)
        static let floating = Elevation(offset: 7, radius: 16)
        static let small = Elevation(offset: 3, radius: 6)
    }

    /// Inner shading of pressed and inset surfaces. Each side fades out before the
    /// middle, so the lit side never gets a dark line.
    enum Inner {
        static let lineWidth: CGFloat = 10
        static let blur: CGFloat = 5
        static let offset: CGFloat = 2
    }

    // MARK: - Motion

    enum Motion {
        /// Press feedback: quick and soft.
        static let press = Animation.easeOut(duration: 0.16)
        /// Sinking in: fast, so even a quick tap shows it.
        static let pressIn = Animation.easeOut(duration: 0.08)
        /// Coming back up: a little slower, so the press reads clearly.
        static let pressOut = Animation.easeOut(duration: 0.22)
        /// How long a quick tap holds the pressed look (seconds).
        static let minimumPress: Double = 0.14
        /// Appearing/disappearing content and value changes.
        static let standard = Animation.snappy(duration: 0.3)
        /// Opening and closing drop-downs: smooth, no bounce.
        static let expand = Animation.smooth(duration: 0.32)
        static let bouncy = Animation.bouncy(duration: 0.4)
        static let pressedScale: CGFloat = 0.97
    }

    // MARK: - Typography (SF Rounded, scales with Dynamic Type)

    enum Fonts {
        static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let title3 = Font.system(.title3, design: .rounded).weight(.semibold)
        static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
        static let body = Font.system(.body, design: .rounded).weight(.medium)
        static let callout = Font.system(.callout, design: .rounded).weight(.medium)
        static let subheadline = Font.system(.subheadline, design: .rounded).weight(.medium)
        static let caption = Font.system(.caption, design: .rounded).weight(.semibold)
        static let button = Font.system(.headline, design: .rounded).weight(.bold)
        static let money = Font.system(.body, design: .rounded).weight(.semibold).monospacedDigit()
        static let bigMoney = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
        static let mediumMoney = Font.system(.title2, design: .rounded).weight(.bold).monospacedDigit()
        static let mono = Font.system(.footnote, design: .monospaced)
    }

    // MARK: - UIKit bridges

    static func uiColor(hex: UInt32, opacity: Double = 1) -> UIColor {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        return UIColor(red: red, green: green, blue: blue, alpha: CGFloat(opacity))
    }
}

/// Light / dark / follow the system. Stored in UserDefaults.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "appearance"

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

/// WCAG contrast math, used by the contrast unit tests.
enum ContrastMath {
    /// Relative luminance of an sRGB color (0 = black, 1 = white).
    static func luminance(_ hex: UInt32) -> Double {
        let channels = [(hex >> 16) & 0xFF, (hex >> 8) & 0xFF, hex & 0xFF].map { value -> Double in
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }

    /// WCAG contrast ratio between two colors (1 to 21).
    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let a = luminance(first)
        let b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// Haptics for presses, saves and swipes.
enum Haptics {
    @MainActor
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @MainActor
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

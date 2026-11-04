import SwiftUI
import UIKit

/// Tabbit's design tokens: soft, matte, clay-like surfaces lit from the top-left,
/// with a calm mint-sage green for money and primary actions.
///
/// Every color, radius, spacing, shadow, font and animation used by the views
/// lives here. Views use the components in Components.swift instead of
/// repeating shadow code.
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
        // Surfaces: a faint green-grey tint, so the whole app feels calm.
        static let background = Swatch(light: 0xE9EEEB, dark: 0x222725)
        /// Raised surfaces fade from `surfaceHigh` (top-left, toward the light)
        /// to `surfaceLow` (bottom-right): matte, never glossy.
        static let surfaceHigh = Swatch(light: 0xF2F6F3, dark: 0x2A302D)
        static let surfaceLow = Swatch(light: 0xE3E9E5, dark: 0x1F2422)
        /// Pressed-in wells: fields, tracks, selected segments, pressed buttons.
        static let inset = Swatch(light: 0xDEE5E0, dark: 0x1B201E)

        // Text and icons
        static let text = Swatch(light: 0x22302B, dark: 0xE6EEE9)
        static let secondaryText = Swatch(light: 0x51615A, dark: 0xA0AFA8)

        // Accent: mint-sage. Fills use the gradient with dark text on top;
        // green text and icons use `accentInk`.
        static let accentHigh = Swatch(light: 0xA8EECB, dark: 0xA8EECB)
        static let accentLow = Swatch(light: 0x6ED6A4, dark: 0x6ED6A4)
        static let onAccent = Swatch(light: 0x14251D, dark: 0x12221A)
        static let accentInk = Swatch(light: 0x1B6844, dark: 0x8FE5BC)
        /// Shadows under green buttons are tinted green, so the color stays clean.
        static let accentShade = Swatch(light: 0x3FA877, dark: 0x0B1E15, lightOpacity: 0.42, darkOpacity: 0.9)

        // Status (always paired with an icon or label)
        static let warning = Swatch(light: 0x835400, dark: 0xF0B85C)
        static let danger = Swatch(light: 0xA1352A, dark: 0xFF9C8F)

        // Lighting: one light source at the top-left.
        static let highlight = Swatch(light: 0xFFFFFF, dark: 0x333A36, lightOpacity: 0.95, darkOpacity: 0.85)
        static let shade = Swatch(light: 0xA6B8AF, dark: 0x101412, lightOpacity: 0.6, darkOpacity: 0.8)
        /// A crisp 1pt edge on the lit side of raised surfaces.
        static let edge = Swatch(light: 0xFFFFFF, dark: 0x3B4440, lightOpacity: 0.8, darkOpacity: 0.7)
        /// A visible outline for Reduce Transparency / Increase Contrast.
        static let outline = Swatch(light: 0x8FA097, dark: 0x5A6862)

        // Swipe-action fills. iOS draws their icons and labels in white, so these
        // stay dark enough for 4.5:1 in both modes.
        static let swipeEdit = Swatch(light: 0x2E7A57, dark: 0x2E7A57)
        static let swipeMove = Swatch(light: 0x3F6699, dark: 0x3F6699)
        static let swipeDelete = Swatch(light: 0xB23A2C, dark: 0xB23A2C)
    }

    /// Shorthand for the SwiftUI colors.
    enum Colors {
        static let background = Palette.background.color
        static let surfaceHigh = Palette.surfaceHigh.color
        static let surfaceLow = Palette.surfaceLow.color
        static let inset = Palette.inset.color
        static let text = Palette.text.color
        static let secondaryText = Palette.secondaryText.color
        static let accentHigh = Palette.accentHigh.color
        static let accentLow = Palette.accentLow.color
        static let onAccent = Palette.onAccent.color
        static let accentInk = Palette.accentInk.color
        static let accentShade = Palette.accentShade.color
        static let warning = Palette.warning.color
        static let danger = Palette.danger.color
        static let highlight = Palette.highlight.color
        static let shade = Palette.shade.color
        static let edge = Palette.edge.color
        static let outline = Palette.outline.color
        static let swipeEdit = Palette.swipeEdit.color
        static let swipeMove = Palette.swipeMove.color
        static let swipeDelete = Palette.swipeDelete.color
    }

    enum Gradients {
        /// Matte surface: lighter toward the light (top-left), a touch darker away from it.
        static let surface = LinearGradient(
            colors: [Colors.surfaceHigh, Colors.surfaceLow], startPoint: .topLeading, endPoint: .bottomTrailing)
        static let accent = LinearGradient(
            colors: [Colors.accentHigh, Colors.accentLow], startPoint: .topLeading, endPoint: .bottomTrailing)
        /// The crisp lit edge, fading out before the shaded side.
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
        Swatch(light: 0xD9E0DC, dark: 0xBFC9C3),
    ]

    /// Text on pastel fills (both modes).
    static let onPastel = Swatch(light: 0x1E2B25, dark: 0x1E2B25)

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
    }

    // MARK: - Shadows

    /// A drop-shadow pair: highlight toward the top-left, shade toward the bottom-right.
    struct Elevation {
        let offset: CGFloat
        /// SwiftUI shadow radius (about half of a design tool's "blur").
        let radius: CGFloat
    }

    enum Elevations {
        static let card = Elevation(offset: 7, radius: 10)
        static let control = Elevation(offset: 5, radius: 7)
        static let floating = Elevation(offset: 8, radius: 14)
        static let small = Elevation(offset: 3, radius: 4)
    }

    /// Inner shadow used by inset wells.
    enum Inner {
        static let lineWidth: CGFloat = 6
        static let blur: CGFloat = 4
        static let offset: CGFloat = 3
    }

    // MARK: - Motion

    enum Motion {
        /// Press feedback: quick, slightly springy.
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
        /// Appearing/disappearing content and value changes.
        static let standard = Animation.snappy(duration: 0.3)
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

    /// A rounded system font for UIKit (navigation bar), scaled for Dynamic Type.
    static func roundedUIFont(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: style)
        let system = UIFont.systemFont(ofSize: base.pointSize, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(.rounded) else {
            return system
        }
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    /// Navigation bar in the theme: background color, rounded titles, no hairline.
    @MainActor
    static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = Palette.background.uiColor
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [
            .foregroundColor: Palette.text.uiColor,
            .font: roundedUIFont(.headline, weight: .bold),
        ]
        appearance.largeTitleTextAttributes = [
            .foregroundColor: Palette.text.uiColor,
            .font: roundedUIFont(.largeTitle, weight: .bold),
        ]
        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = Palette.accentInk.uiColor
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

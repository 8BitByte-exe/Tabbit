import SwiftUI
import UIKit

/// Tabbit's design tokens: soft, tactile, clay-like surfaces lit from the top-left.
///
/// Every color, radius, spacing, shadow and font used by the views lives here.
/// Views use the components in Components.swift instead of repeating shadow code.
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
            let swatch = self
            return Color(uiColor: UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return Theme.uiColor(hex: swatch.dark, opacity: swatch.darkOpacity)
                }
                return Theme.uiColor(hex: swatch.light, opacity: swatch.lightOpacity)
            })
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

    /// All colors. Text colors pass WCAG AA (4.5:1) on every surface below in both
    /// modes; ThemeContrastTests checks this in CI.
    enum Palette {
        // Surfaces
        static let background = Swatch(light: 0xE6EAF0, dark: 0x2A2D34)
        /// Top and bottom of the puffy clay gradient on raised surfaces.
        static let surfaceTop = Swatch(light: 0xEEF1F5, dark: 0x31353D)
        static let surfaceBottom = Swatch(light: 0xE0E5EC, dark: 0x282B31)
        /// Pressed-in wells: text fields, selected segments, pressed buttons.
        static let inset = Swatch(light: 0xDCE1E8, dark: 0x24272D)

        // Text and icons
        static let text = Swatch(light: 0x2E3440, dark: 0xECEFF4)
        static let secondaryText = Swatch(light: 0x586273, dark: 0xA9B1BE)

        // Accent: soft coral. Fills use the gradient with dark text on top;
        // coral-colored text and icons use `accentInk`, which is deeper in light mode.
        static let accentTop = Swatch(light: 0xFF9A85, dark: 0xFF9A85)
        static let accentBottom = Swatch(light: 0xF57C64, dark: 0xF57C64)
        static let onAccent = Swatch(light: 0x2E3440, dark: 0x2A2D34)
        static let accentInk = Swatch(light: 0xA63A26, dark: 0xFF8A73)

        // Status (always paired with an icon and a label)
        static let success = Swatch(light: 0x27693F, dark: 0x7FD39B)
        static let warning = Swatch(light: 0x865700, dark: 0xF2B65A)

        // Lighting: one light source at the top-left.
        static let highlight = Swatch(light: 0xFFFFFF, dark: 0x3C4049, lightOpacity: 0.8, darkOpacity: 0.7)
        static let shade = Swatch(light: 0xA3B1C6, dark: 0x15171B, lightOpacity: 0.5, darkOpacity: 0.7)
        /// A visible edge for Reduce Transparency / Increase Contrast, where soft shadows aren't enough.
        static let outline = Swatch(light: 0x9AA5B5, dark: 0x5A616E)
    }

    /// Shorthand for the SwiftUI colors.
    enum Colors {
        static let background = Palette.background.color
        static let surfaceTop = Palette.surfaceTop.color
        static let surfaceBottom = Palette.surfaceBottom.color
        static let inset = Palette.inset.color
        static let text = Palette.text.color
        static let secondaryText = Palette.secondaryText.color
        static let accentTop = Palette.accentTop.color
        static let accentBottom = Palette.accentBottom.color
        static let onAccent = Palette.onAccent.color
        static let accentInk = Palette.accentInk.color
        static let success = Palette.success.color
        static let warning = Palette.warning.color
        static let highlight = Palette.highlight.color
        static let shade = Palette.shade.color
        static let outline = Palette.outline.color
    }

    enum Gradients {
        /// The puffy top-to-bottom gradient on raised surfaces.
        static let surface = LinearGradient(
            colors: [Colors.surfaceTop, Colors.surfaceBottom], startPoint: .top, endPoint: .bottom)
        static let accent = LinearGradient(
            colors: [Colors.accentTop, Colors.accentBottom], startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Shape

    enum Radius {
        static let card: CGFloat = 30
        static let button: CGFloat = 24
        static let field: CGFloat = 20
        static let small: CGFloat = 14
    }

    enum Spacing {
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
        /// Minimum height of buttons.
        static let buttonHeight: CGFloat = 56
        /// Minimum tap target (Apple's guideline is 44pt).
        static let tapTarget: CGFloat = 48
        static let fieldHeight: CGFloat = 48
    }

    // MARK: - Shadows

    /// A drop-shadow pair: highlight toward the top-left, shade toward the bottom-right.
    struct Elevation {
        /// Offset of each shadow, in points.
        let offset: CGFloat
        /// SwiftUI shadow radius (about half of a design tool's "blur").
        let radius: CGFloat
    }

    enum Elevations {
        /// Cards: offset 8, blur ~16.
        static let card = Elevation(offset: 8, radius: 8)
        /// Buttons and small controls.
        static let control = Elevation(offset: 5, radius: 5)
    }

    /// Inner highlight/shadow used for the clay edge and for inset wells.
    enum Inner {
        static let lineWidth: CGFloat = 6
        static let blur: CGFloat = 4
        static let offset: CGFloat = 3
    }

    // MARK: - Motion

    enum Motion {
        static let press = Animation.easeOut(duration: 0.15)
        static let pressedScale: CGFloat = 0.97
    }

    // MARK: - Typography (SF Rounded, scales with Dynamic Type)

    enum Fonts {
        static let largeTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let title = Font.system(.title2, design: .rounded).weight(.bold)
        static let headline = Font.system(.headline, design: .rounded).weight(.semibold)
        static let body = Font.system(.body, design: .rounded).weight(.medium)
        static let callout = Font.system(.callout, design: .rounded).weight(.medium)
        static let caption = Font.system(.caption, design: .rounded).weight(.medium)
        static let button = Font.system(.headline, design: .rounded).weight(.bold)
        static let money = Font.system(.body, design: .rounded).weight(.semibold).monospacedDigit()
        static let bigMoney = Font.system(.title, design: .rounded).weight(.bold).monospacedDigit()
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
    /// Call once at launch.
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

/// Soft haptics for presses and saves.
enum Haptics {
    @MainActor
    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    @MainActor
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

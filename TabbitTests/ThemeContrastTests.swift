import XCTest
@testable import Tabbit

/// Keeps the neumorphic palette readable: every text/icon color must reach WCAG AA
/// (4.5:1) on every surface it can sit on, in light and dark mode.
final class ThemeContrastTests: XCTestCase {

    private let foregrounds: [(String, Theme.Swatch)] = [
        ("text", Theme.Palette.text),
        ("secondaryText", Theme.Palette.secondaryText),
        ("accentInk", Theme.Palette.accentInk),
        ("success", Theme.Palette.success),
        ("warning", Theme.Palette.warning),
    ]

    private let surfaces: [(String, Theme.Swatch)] = [
        ("background", Theme.Palette.background),
        ("surfaceTop", Theme.Palette.surfaceTop),
        ("surfaceBottom", Theme.Palette.surfaceBottom),
        ("inset", Theme.Palette.inset),
    ]

    func testTextOnSurfacesMeetsAA() {
        for (foregroundName, foreground) in foregrounds {
            for (surfaceName, surface) in surfaces {
                let light = ContrastMath.ratio(foreground.light, surface.light)
                let dark = ContrastMath.ratio(foreground.dark, surface.dark)
                XCTAssertGreaterThanOrEqual(light, 4.5, "light: \(foregroundName) on \(surfaceName) is \(light)")
                XCTAssertGreaterThanOrEqual(dark, 4.5, "dark: \(foregroundName) on \(surfaceName) is \(dark)")
            }
        }
    }

    func testTextOnCoralButtonsMeetsAA() {
        for accent in [Theme.Palette.accentTop, Theme.Palette.accentBottom] {
            XCTAssertGreaterThanOrEqual(ContrastMath.ratio(Theme.Palette.onAccent.light, accent.light), 4.5)
            XCTAssertGreaterThanOrEqual(ContrastMath.ratio(Theme.Palette.onAccent.dark, accent.dark), 4.5)
        }
    }

    func testContrastMathMatchesKnownValues() {
        XCTAssertEqual(ContrastMath.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastMath.ratio(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
    }

    func testNoPureBlackOrWhiteText() {
        for (_, swatch) in foregrounds {
            for hex in [swatch.light, swatch.dark] {
                XCTAssertNotEqual(hex, 0x000000)
                XCTAssertNotEqual(hex, 0xFFFFFF)
            }
        }
    }
}

import XCTest
@testable import Tabbit

/// Keeps the palette readable: every text/icon color must reach WCAG AA
/// (4.5:1) on every surface it can sit on, in light and dark mode.
final class ThemeContrastTests: XCTestCase {

    private let foregrounds: [(String, Theme.Swatch)] = [
        ("text", Theme.Palette.text),
        ("secondaryText", Theme.Palette.secondaryText),
        ("warning", Theme.Palette.warning),
        ("danger", Theme.Palette.danger),
    ]

    private let surfaces: [(String, Theme.Swatch)] = [
        ("background", Theme.Palette.background),
        ("surfaceHigh", Theme.Palette.surfaceHigh),
        ("surfaceLow", Theme.Palette.surfaceLow),
        ("inset", Theme.Palette.inset),
        ("plate", Theme.Palette.plate),
    ]

    private func assertAA(_ foreground: Theme.Swatch, on surface: Theme.Swatch, _ name: String,
                          file: StaticString = #filePath, line: UInt = #line) {
        let light = ContrastMath.ratio(foreground.light, surface.light)
        let dark = ContrastMath.ratio(foreground.dark, surface.dark)
        XCTAssertGreaterThanOrEqual(light, 4.5, "light: \(name) is \(light)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(dark, 4.5, "dark: \(name) is \(dark)", file: file, line: line)
    }

    func testTextOnSurfacesMeetsAA() {
        for (foregroundName, foreground) in foregrounds {
            for (surfaceName, surface) in surfaces {
                assertAA(foreground, on: surface, "\(foregroundName) on \(surfaceName)")
            }
        }
    }

    func testTextOnMintMeetsAA() {
        assertAA(Theme.Palette.onAccent, on: Theme.Palette.accentHigh, "onAccent on accentHigh")
        assertAA(Theme.Palette.onAccent, on: Theme.Palette.accentLow, "onAccent on accentLow")
    }

    func testTextOnPastelsAndStatusFillsMeetsAA() {
        for (index, pastel) in Theme.pastels.enumerated() {
            assertAA(Theme.onPastel, on: pastel, "onPastel on pastel \(index)")
        }
        assertAA(Theme.onPastel, on: Theme.Palette.cautionFill, "onPastel on cautionFill")
        assertAA(Theme.onPastel, on: Theme.Palette.dangerFill, "onPastel on dangerFill")
    }

    func testMintIsTheSameInBothModes() {
        for swatch in [Theme.Palette.accentHigh, Theme.Palette.accentLow] {
            XCTAssertEqual(swatch.light, swatch.dark)
        }
    }

    func testContrastMathMatchesKnownValues() {
        XCTAssertEqual(ContrastMath.ratio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(ContrastMath.ratio(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
    }

    func testNoPureBlackOrWhiteText() {
        let all = foregrounds.map { entry in entry.1 } + [Theme.Palette.onAccent, Theme.onPastel]
        for swatch in all {
            for hex in [swatch.light, swatch.dark] {
                XCTAssertNotEqual(hex, 0x000000)
                XCTAssertNotEqual(hex, 0xFFFFFF)
            }
        }
    }
}

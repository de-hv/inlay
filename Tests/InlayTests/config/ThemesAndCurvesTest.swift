@testable import AppBundle
import Common
import Foundation
import Testing

/// [animations] curves, [theme] seed = 'wallpaper', and the colors set by hand
extension InlayTests {
    @Suite @MainActor struct ThemesAndCurvesTest {
        init() {
            setUpWorkspacesForTests()
        }

        // MARK: - Curves

        @Test func testPresets() {
            for (name, curve) in AnimationCurve.presets {
                assertEquals(curve.value(0), 0, additionalMsg: name)
                assertEquals(curve.value(1), 1, additionalMsg: name)
            }
            let linear = AnimationCurve.presets["linear"]!
            for step in 0 ... 10 { assertTrue(abs(linear.value(Double(step) / 10) - Double(step) / 10) < 1e-9) }
            // Overshot goes past the end before it lands
            let overshot = AnimationCurve.presets["overshot"]!
            assertTrue((1 ... 19).map { overshot.value(Double($0) / 20) }.contains { $0 > 1 })
            // Ease-out never goes back
            var last = -1.0
            for step in 0 ... 50 {
                let value = AnimationCurve.easeOut.value(Double(step) / 50)
                assertTrue(value >= last)
                last = value
            }
        }

        @Test func testParseCurvesAndSteps() {
            let result = parseConfig("""
                [animations]
                curve = 'bounce'
                open = { curve = 'overshot', duration = 220 }
                workspace = { duration = 120 }
                [animations.curves]
                bounce = [0.34, 1.56, 0.64, 1]
                """)
            assertEquals(result.errors, [])
            let animations = result.config.animations
            assertEquals(animations.curves["bounce"], AnimationCurve(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1))
            assertEquals(animations.effectiveCurve(.move), AnimationCurve(x1: 0.34, y1: 1.56, x2: 0.64, y2: 1))
            assertEquals(animations.effectiveCurve(.open), AnimationCurve.presets["overshot"])
            assertEquals(animations.effectiveDuration(.open), .milliseconds(220))
            assertEquals(animations.effectiveDuration(.workspace), .milliseconds(120))
            assertEquals(animations.effectiveDuration(.fullscreen), .milliseconds(180))
            assertEquals(animations.copy(\.enabled, false).effectiveDuration(.open), .zero)
            // The default: the curve of before
            assertEquals(parseConfig("").config.animations.effectiveCurve(.move), .easeOut)
        }

        @Test func testCurveErrors() {
            assertEquals(
                parseConfig("[animations]\ncurve = 'wobble'\n").strErrors,
                ["[ERROR] animations.curve: Unknown curve 'wobble'. Possible values: ease, ease-in-out, ease-out, linear, overshot, snappy, or a curve of [animations.curves]"],
            )
            assertEquals(
                parseConfig("[animations]\nopen = { curve = 'wobble' }\n").strErrors.count,
                1,
            )
            assertEquals(
                parseConfig("[animations.curves]\nbad = [1.5, 0, 0.5, 1]\n").strErrors,
                ["[ERROR] animations.curves.bad: x1 and x2 of a curve must be in [0, 1] range"],
            )
            assertEquals(
                parseConfig("[animations.curves]\nbad = [0.5, 1]\n").strErrors,
                ["[ERROR] animations.curves.bad: A curve is four numbers: [x1, y1, x2, y2]"],
            )
        }

        // MARK: - Theme

        @Test func testParseThemeSeedWallpaper() {
            let result = parseConfig("""
                [theme]
                palette = 'gruvbox'
                seed = 'wallpaper'
                """)
            assertEquals(result.errors, [])
            assertEquals(result.config.theme.seed, .wallpaper)
        }

        @Test func testManualColors() {
            assertEquals(ManualColors.keys(in: parseConfig("").config), [])
            let config = parseConfig("""
                [menu-bar.colors]
                focused = '#E06C75'
                [borders]
                active-color = '#61AFEF'
                """).config
            assertEquals(ManualColors.keys(in: config), [.menuBarFocused, .bordersActiveColor])
        }

        @Test func testThemeCmdArgs() {
            assertEquals(parseCommand("theme list").errorOrNil, nil)
            assertEquals(parseCommand("theme set gruvbox --reset-colors").errorOrNil, nil)
            assertEquals(parseCommand("theme set").errorOrNil, "'theme set' requires the name of a palette (see: inlay theme list)")
            assertEquals(parseCommand("theme list --reset-colors").errorOrNil, "--reset-colors requires 'set'")
        }

        // MARK: - The color of the wallpaper

        @Test func testDominantColor() {
            let teal = (0.2, 0.6, 0.55)
            let gray = (0.5, 0.5, 0.5)
            let orange = (0.95, 0.55, 0.2)
            // Mostly gray, more teal than orange: the grays don't count
            let pixels = Array(repeating: gray, count: 600) + Array(repeating: teal, count: 300) + Array(repeating: orange, count: 100)
            let color = WallpaperSeed.dominantColor(pixels)!
            assertTrue(abs(color.red - 0.2) < 0.01 && abs(color.green - 0.6) < 0.01 && abs(color.blue - 0.55) < 0.01)
            // Only grays: their average
            assertEquals(WallpaperSeed.dominantColor([gray, (0.3, 0.3, 0.3)])?.hex, Rgba(red: 0.4, green: 0.4, blue: 0.4).hex)
            assertNil(WallpaperSeed.dominantColor([]))
        }
    }
}

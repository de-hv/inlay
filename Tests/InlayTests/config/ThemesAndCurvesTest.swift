@testable import AppBundle
import Common
import Foundation
import Testing

/// [animations] curves, and the tables of the past: [theme] and [notifications]
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
            assertEquals(animations.effectiveDuration(.fullscreen), .milliseconds(220))
            assertEquals(animations.copy(\.enabled, false).effectiveDuration(.open), .zero)
            // The default: easeOutQuint
            assertEquals(parseConfig("").config.animations.effectiveCurve(.move), AnimationCurve.presets["quint"])
        }

        @Test func testCurveErrors() {
            assertEquals(
                parseConfig("[animations]\ncurve = 'wobble'\n").strErrors,
                ["[ERROR] animations.curve: Unknown curve 'wobble'. Possible values: ease, ease-in-out, ease-out, expo, linear, overshot, quick, quint, snappy, or a curve of [animations.curves]"],
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

        // MARK: - Tables of the past

        /// [theme] and [notifications] are gone: an old config still loads, with a warning for each
        @Test func testObsoleteTables() {
            let result = parseConfig("""
                config-version = 2
                [theme]
                palette = 'gruvbox'
                seed = 'wallpaper'
                [notifications]
                on-reload = 'diff'
                """)
            assertEquals(result.errors, [])
            assertEquals(result.strWarnings.count, 2, additionalMsg: result.strWarnings.joined(separator: "\n"))
            assertTrue(result.strWarnings.contains { $0.contains("theme: The palettes are gone") })
            assertTrue(result.strWarnings.contains { $0.contains("notifications: The notice of the reload is gone") })
            assertEquals(parseCommand("theme list").errorOrNil != nil, true)
        }
    }
}

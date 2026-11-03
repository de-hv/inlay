@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct AnimationsConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig(lua: "return { configVersion = 2 }")
            assertEquals(result.errors, [])
            assertEquals(result.config.animations, AnimationsConfig(enabled: true, duration: 160))
            assertEquals(result.config.animations.effectiveDuration, .milliseconds(160))
            // The built-in config agrees with the defaults
            assertEquals(defaultConfig.animations, AnimationsConfig())
        }

        /// The defaults of each kind only hold while the config sets neither curve nor duration
        @Test func testBaseCurveAndDurationOverrideTheDefaultsOfEachKind() {
            let animations = parseConfig(lua: "return { animations = { curve = 'linear', duration = 250, open = { duration = 300 } } }").config.animations
            assertEquals(animations.effectiveDuration(.open), .milliseconds(300))
            assertEquals(animations.effectiveCurve(.open), AnimationCurve.presets["linear"])
            for kind in [AnimationKind.move, .fullscreen, .workspace] {
                assertEquals(animations.effectiveDuration(kind), .milliseconds(250), additionalMsg: kind.rawValue)
                assertEquals(animations.effectiveCurve(kind), AnimationCurve.presets["linear"], additionalMsg: kind.rawValue)
            }
            let defaults = parseConfig(lua: "return {}").config.animations
            assertEquals(defaults.effectiveDuration(.open), .milliseconds(200))
            assertEquals(defaults.effectiveCurve(.fullscreen), AnimationCurve.presets["expo"])
        }

        @Test func testParse() {
            let result = parseConfig(lua: "return { animations = { enabled = false, duration = 250 } }")
            assertEquals(result.errors, [])
            // The duration of the table is the one of every kind: their curves stay the defaults
            assertEquals(result.config.animations, AnimationsConfig(
                enabled: false,
                duration: 250,
                open: AnimationStep(curve: "quint"),
                move: AnimationStep(curve: "quint"),
                fullscreen: AnimationStep(curve: "expo"),
                workspace: AnimationStep(curve: "expo"),
            ))
            for (value, expected) in [("'vertical'", WorkspaceSwitch.vertical), ("'auto'", .auto), ("'off'", .off), ("'horizontal'", .horizontal),
                                      ("false", .off), ("true", .horizontal)]
            {
                let parsed = parseConfig(lua: "return { animations = { workspaceSwitch = \(value) } }")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.animations.workspaceSwitch, expected, additionalMsg: value)
            }
            assertEquals(
                parseConfig(lua: "return { animations = { workspaceSwitch = 'diagonal' } }").strErrors,
                ["[ERROR] animations.workspaceSwitch: Can't parse workspaceSwitch 'diagonal'. Possible values: (horizontal|vertical|auto|off)"],
            )
            // Off: no animation, whatever the duration
            assertEquals(result.config.animations.effectiveDuration, .zero)
        }

        @Test func testRanges() {
            for value in [0, 180, 500] {
                assertEquals(parseConfig(lua: "return { animations = { duration = \(value) } }").errors, [])
            }
            assertEquals(
                parseConfig(lua: "return { animations = { duration = 501 } }").strErrors,
                ["[ERROR] animations.duration: duration must be in [0, 500] range"],
            )
            assertEquals(parseConfig(lua: "return { animations = { duration = -1 } }").errors.count, 1)
            assertEquals(parseConfig(lua: "return { animations = { speed = 1 } }").strErrors, ["[ERROR] animations.speed: Unknown key"])
        }
    }
}

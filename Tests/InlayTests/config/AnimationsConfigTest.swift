@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct AnimationsConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig("config-version = 2")
            assertEquals(result.errors, [])
            assertEquals(result.config.animations, AnimationsConfig(enabled: true, duration: 180))
            assertEquals(result.config.animations.effectiveDuration, .milliseconds(180))
            // The built-in config agrees with the defaults
            assertEquals(defaultConfig.animations, AnimationsConfig())
        }

        @Test func testParse() {
            let result = parseConfig("[animations]\nenabled = false\nduration = 250\n")
            assertEquals(result.errors, [])
            assertEquals(result.config.animations, AnimationsConfig(enabled: false, duration: 250))
            // Off: no animation, whatever the duration
            assertEquals(result.config.animations.effectiveDuration, .zero)
        }

        @Test func testRanges() {
            for value in [0, 180, 500] {
                assertEquals(parseConfig("animations.duration = \(value)").errors, [])
            }
            assertEquals(
                parseConfig("animations.duration = 501").strErrors,
                ["[ERROR] animations.duration: duration must be in [0, 500] range"],
            )
            assertEquals(parseConfig("animations.duration = -1").errors.count, 1)
            assertEquals(parseConfig("animations.speed = 1").strErrors, ["[ERROR] animations.speed: Unknown key"])
        }

        /// The settings window writes these keys. The defaults it shows must be the ones of the parser
        @Test func testSettingsKeysAgreeWithTheParser() {
            let defaults = AnimationsConfig()
            assertEquals(SettingsKey.animationsEnabled.defaultValue, .bool(defaults.enabled))
            assertEquals(SettingsKey.animationsDuration.defaultValue, .int(defaults.duration))
        }
    }
}

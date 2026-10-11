@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct BordersConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig("config-version = 2")
            assertEquals(result.errors, [])
            let borders = result.config.borders
            assertEquals(borders.enabled, true)
            assertEquals(borders.width, 4)
            assertEquals(borders.cornerRadius, 16)
            assertEquals(borders.activeColor, .systemAccent)
            assertEquals(borders.inactiveColor.description, "#8E8E9373")
            assertEquals(borders.floatingColor.description, "#BF5AF2")
            assertEquals(borders.modeColors, [:])
            // The built-in config agrees with the defaults
            assertEquals(defaultConfig.borders, BordersConfig())
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                [borders]
                    enabled = false
                    width = 6
                    corner-radius = 10
                    active-color = '#D19A66'
                    inactive-color = '#00000000'
                    floating-color = 'system-accent'
                [borders.mode-colors]
                    resize = '#30D158'
                    service = '#FF453A80'
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.borders, BordersConfig(
                enabled: false,
                width: 6,
                cornerRadius: 10,
                activeColor: .rgba(Rgba(hex: "#D19A66").orDie()),
                inactiveColor: .rgba(Rgba(red: 0, green: 0, blue: 0, alpha: 0)),
                floatingColor: .systemAccent,
                modeColors: [
                    "resize": .rgba(Rgba(hex: "#30D158").orDie()),
                    "service": .rgba(Rgba(hex: "#FF453A80").orDie()),
                ],
            ))
        }

        @Test func testRanges() {
            for (key, good, bad) in [("width", [1, 20], [0, 21, -1]), ("corner-radius", [0, 40], [-1, 41])] {
                for value in good {
                    assertEquals(parseConfig("borders.\(key) = \(value)").errors, [])
                }
                for value in bad {
                    assertEquals(parseConfig("borders.\(key) = \(value)").errors.count, 1)
                }
            }
            assertEquals(
                parseConfig("borders.width = 21").strErrors,
                ["[ERROR] borders.width: width must be in [1, 20] range"],
            )
            assertEquals(
                parseConfig("borders.corner-radius = 41").strErrors,
                ["[ERROR] borders.corner-radius: corner-radius must be in [0, 40] range"],
            )
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig(
                    """
                    [borders]
                        glow = true
                        width = '4'
                        enabled = 1
                        active-color = 'auto'
                        inactive-color = 'red'
                    [borders.mode-colors]
                        resize = 'auto'
                        service = 5
                    """,
                ).strErrors,
                [
                    // 'auto' has no meaning for a border
                    "[ERROR] borders.active-color: Can't parse color 'auto'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'",
                    "[ERROR] borders.enabled: Expected type is 'Bool'. But actual type is 'Int'",
                    "[ERROR] borders.glow: Unknown key",
                    "[ERROR] borders.inactive-color: Can't parse color 'red'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'",
                    "[ERROR] borders.mode-colors.resize: Can't parse color 'auto'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'",
                    "[ERROR] borders.mode-colors.service: Expected type is 'String'. But actual type is 'Int'",
                    "[ERROR] borders.width: Expected type is 'Int'. But actual type is 'String'",
                ],
            )
            assertEquals(parseConfig("borders = 1").strErrors, ["[ERROR] borders: Expected type is 'Table'. But actual type is 'Int'"])
            assertEquals(parseConfig("borders.mode-colors = 1").strErrors, ["[ERROR] borders.mode-colors: Expected type is 'Table'. But actual type is 'Int'"])
        }

        /// The settings window writes these keys. The defaults it shows must be the ones of the parser
        @Test func testSettingsKeysAgreeWithTheParser() {
            let defaults = BordersConfig()
            assertEquals(SettingsFeatures.borders, true)
            assertEquals(SettingsKey.bordersEnabled.defaultValue, .bool(defaults.enabled))
            assertEquals(SettingsKey.bordersWidth.defaultValue, .int(Int(defaults.width)))
            assertEquals(SettingsKey.bordersCornerRadius.defaultValue, .int(Int(defaults.cornerRadius)))
            assertEquals(SettingsKey.bordersActiveColor.defaultValue, .string(defaults.activeColor.description))
            assertEquals(SettingsKey.bordersInactiveColor.defaultValue, .string(defaults.inactiveColor.description))
            assertEquals(SettingsKey.bordersFloatingColor.defaultValue, .string(defaults.floatingColor.description))
            // Every key, written by the patcher into an empty config, is accepted by the parser
            var text = ""
            for (key, value) in [
                (SettingsKey.bordersEnabled, TomlValue.bool(false)),
                (.bordersWidth, .int(20)),
                (.bordersCornerRadius, .int(0)),
                (.bordersActiveColor, .string("#D19A66")),
                (.bordersInactiveColor, .string("#00000000")),
                (.bordersFloatingColor, .string("system-accent")),
            ] {
                text = (try? TomlPatcher.set(text, key.path, value)) ?? "<patch failed>"
            }
            let result = parseConfig(text)
            assertEquals(result.errors, [])
            assertEquals(result.config.borders.enabled, false)
            assertEquals(result.config.borders.width, 20)
            assertEquals(result.config.borders.cornerRadius, 0)
            assertEquals(result.config.borders.inactiveColor.description, "#00000000")
            assertEquals(result.config.borders.floatingColor, .systemAccent)
        }
    }
}

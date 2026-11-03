@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct MenuBarConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig("configVersion = 2")
            assertEquals(result.errors, [])
            let menuBar = result.config.menuBar
            assertEquals(menuBar.enabled, true)
            assertEquals(menuBar.theme, .liquid)
            assertEquals(menuBar.dimEmptyWorkspaces, true)
            assertEquals(menuBar.showMode, true)
            assertEquals(menuBar.colors, MenuBarColors(accent: .auto, focused: .auto, occupied: .auto, empty: .auto))
            assertEquals(menuBar.systemColors, false)
        }

        @Test func testSystemColors() {
            let result = parseConfig(
                """
                configVersion = 2
                [menuBar]
                    systemColors = true
                [menuBar.colors]
                    focused = '#D19A66'
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.menuBar.systemColors, true)
            // The colors are kept for when it's off again
            assertEquals(result.config.menuBar.colors.focused, .rgba(Rgba(hex: "#D19A66").orDie()))
            assertEquals(result.config.menuBar.effectiveColors, MenuBarColors())
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                configVersion = 2
                [menuBar]
                    enabled = false
                    theme = 'hypr'
                    dimEmptyWorkspaces = false
                    showMode = true
                [menuBar.colors]
                    accent = '#E06C75'
                    focused = 'system-accent'
                    occupied = '#abb2bf'
                    empty = '#CDD6F466'
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            let expected = MenuBarConfig(
                enabled: false,
                theme: .hypr,
                dimEmptyWorkspaces: false,
                showMode: true,
                colors: MenuBarColors(
                    accent: .rgba(Rgba(red: 0xE0 / 255, green: 0x6C / 255, blue: 0x75 / 255)),
                    focused: .systemAccent,
                    occupied: .rgba(Rgba(red: 0xAB / 255, green: 0xB2 / 255, blue: 0xBF / 255)),
                    empty: .rgba(Rgba(red: 0xCD / 255, green: 0xD6 / 255, blue: 0xF4 / 255, alpha: 0x66 / 255)),
                ),
            )
            assertEquals(result.config.menuBar, expected)
        }

        @Test func testThemes() {
            assertEquals(MenuBarTheme.allCases.map(\.rawValue), ["pills", "chips", "hypr", "minimal", "dots", "underline", "liquid", "dms"])
            for theme in MenuBarTheme.allCases {
                let result = parseConfig("configVersion = 2\nmenuBar.theme = '\(theme.rawValue)'")
                assertEquals(result.errors, [])
                assertEquals(result.warnings, [])
                assertEquals(result.config.menuBar.theme, theme)
            }
        }

        /// The item showed the icons of the apps once: the 'chips-icons' theme and the 'showAppIcons' key, which the
        /// settings window wrote to the config of the user. Such a config still loads
        @Test func testAppIconsOfThePast_acceptedWithAWarning() {
            let theme = parseConfig("configVersion = 2\n[menuBar]\ntheme = 'chips-icons'\nshowMode = true")
            assertEquals(theme.strErrors, [])
            assertEquals(theme.strWarnings, [
                "[WARNING] menuBar.theme: The menu bar item doesn't show app icons anymore: 'chips-icons' is treated as 'chips'. Please change it in the config",
            ])
            assertEquals(theme.config.menuBar, MenuBarConfig(theme: .chips, showMode: true))

            for value in ["true", "false"] {
                let key = parseConfig("configVersion = 2\n[menuBar]\ntheme = 'hypr'\nshowAppIcons = \(value)\ndimEmptyWorkspaces = false")
                assertEquals(key.strErrors, [])
                assertEquals(key.strWarnings, [
                    "[WARNING] menuBar.showAppIcons: The menu bar item doesn't show app icons anymore: 'showAppIcons' is ignored. Please drop it from the config",
                ])
                assertEquals(key.config.menuBar, MenuBarConfig(theme: .hypr, dimEmptyWorkspaces: false))
            }

            let both = parseConfig("configVersion = 2\nmenuBar.theme = 'chips-icons'\nmenuBar.showAppIcons = true")
            assertEquals(both.strErrors, [])
            assertEquals(both.warnings.count, 2)
            assertEquals(both.config.menuBar, MenuBarConfig(theme: .chips))
            // Warnings don't keep the config from being applied
            assertEquals(both.allowReloadConfig, true)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig("menuBar.theme = 'bubbles'").strErrors,
                ["[ERROR] menuBar.theme: Can't parse menu bar theme 'bubbles'. Possible values: (pills|chips|hypr|minimal|dots|underline|liquid|dms)"],
            )
            // The themes and the tables of the past are gone, with no compatibility
            for theme in ["square", "glyphs", "labels", "segments", "capsule"] {
                assertEquals(
                    parseConfig("menuBar.theme = '\(theme)'").strErrors,
                    ["[ERROR] menuBar.theme: Can't parse menu bar theme '\(theme)'. Possible values: (pills|chips|hypr|minimal|dots|underline|liquid|dms)"],
                )
            }
            assertEquals(parseConfig("[menuBar.labels]\n1 = 'Code'").strErrors, ["[ERROR] menuBar.labels: Unknown key"])
            assertEquals(parseConfig("[menuBar.symbols]\n1 = 'globe'").strErrors, ["[ERROR] menuBar.symbols: Unknown key"])
            assertEquals(parseConfig("menuBar.them = 'chips'").strErrors, ["[ERROR] menuBar.them: Unknown key"])
            assertEquals(parseConfig("menuBar.colors.focus = 'auto'").strErrors, ["[ERROR] menuBar.colors.focus: Unknown key"])
            assertEquals(
                parseConfig("menuBar.enabled = 'yes'").strErrors,
                ["[ERROR] menuBar.enabled: Expected type is 'Bool'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig("menuBar.showAppIcons = 1").strErrors,
                ["[ERROR] menuBar.showAppIcons: Expected type is 'Bool'. But actual type is 'Int'"],
            )
            assertEquals(parseConfig("configVersion = 2\nmenuBar.showAppIcons = 1").strWarnings, [])
            assertEquals(
                parseConfig("menuBar = 'chips'").strErrors,
                ["[ERROR] menuBar: Expected type is 'Table'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig("menuBar.colors.focused = 'red'").strErrors,
                ["[ERROR] menuBar.colors.focused: Can't parse color 'red'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent', 'auto'"],
            )
            // 'auto' for the accent: the marker of a binding mode is the one of the focused workspace
            let auto = parseConfig("configVersion = 2\nmenuBar.colors.accent = 'auto'")
            assertEquals(auto.strErrors, [])
            assertEquals(auto.config.menuBar.colors.accent, .auto)
            assertEquals(parseConfig("configVersion = 2\nmenuBar.colors.accent = 'system-accent'").config.menuBar.colors.accent, .systemAccent)
            assertEquals(
                parseConfig("menuBar.colors.empty = 0xFF0000").strErrors,
                ["[ERROR] menuBar.colors.empty: Expected type is 'String'. But actual type is 'Int'"],
            )
            // The value with an error is ignored
            assertEquals(parseConfig("menuBar.colors.focused = 'red'").config.menuBar.colors.focused, .auto)
        }
    }

    @Suite struct ConfigColorTest {
        @Test func testParse() {
            assertEquals(ConfigColor.parse("auto", allowAuto: true).okOrNil, .auto)
            assertEquals(ConfigColor.parse("auto", allowAuto: false).okOrNil, nil)
            assertEquals(ConfigColor.parse("system-accent", allowAuto: false).okOrNil, .systemAccent)
            assertEquals(ConfigColor.parse("#000000", allowAuto: false).okOrNil, .rgba(.black))
            assertEquals(ConfigColor.parse("#ffffff", allowAuto: false).okOrNil, .rgba(.white))
            assertEquals(ConfigColor.parse("#FFFFFFFF", allowAuto: false).okOrNil, .rgba(.white))
            assertEquals(ConfigColor.parse("#FF000080", allowAuto: false).okOrNil, .rgba(Rgba(red: 1, green: 0, blue: 0, alpha: 128.0 / 255)))
        }

        @Test func testInvalid() {
            for raw in ["", "#", "#FFF", "#FFFFF", "#FFFFFFF", "#FFFFFFFFF", "FFFFFF", "#GGGGGG", "#12 456", "#+12345", "0xFFFFFF",
                        "red", "Auto", "system_accent", " #FFFFFF", "#ＦＦＦＦＦＦ"]
            {
                assertEquals(ConfigColor.parse(raw, allowAuto: true).okOrNil, nil, additionalMsg: raw)
            }
        }

        @Test func testDescriptionRoundTrip() {
            for raw in ["auto", "system-accent", "#D19A66", "#8E8E9373", "#00000000", "#000000", "#FFFFFF"] {
                let color = ConfigColor.parse(raw, allowAuto: true).okOrNil
                assertEquals(color?.description, raw)
            }
            // The digits are normalized to upper case, and an opaque alpha is dropped
            assertEquals(ConfigColor.parse("#d19a66ff", allowAuto: true).okOrNil?.description, "#D19A66")
        }

        @Test func testResolve() {
            let accent = Rgba(red: 1, green: 0.5, blue: 0)
            assertEquals(ConfigColor.auto.resolve(auto: .white, systemAccent: accent), .white)
            assertEquals(ConfigColor.systemAccent.resolve(auto: .white, systemAccent: accent), accent)
            assertEquals(ConfigColor.rgba(.black).resolve(auto: .white, systemAccent: accent), .black)
        }

        @Test func testContrast() {
            assertEquals(Rgba.white.contrastingBlackOrWhite, .black)
            assertEquals(Rgba.black.contrastingBlackOrWhite, .white)
            assertEquals(Rgba(hex: "#D19A66")?.contrastingBlackOrWhite, .black)
            assertEquals(Rgba(hex: "#1E3A8A")?.contrastingBlackOrWhite, .white)
            assertEquals(Rgba(hex: "#FF000080")?.opacity(0.5).alpha, 64.0 / 255)
        }
    }
}

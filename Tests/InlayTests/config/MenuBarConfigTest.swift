@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct MenuBarConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig("config-version = 2")
            assertEquals(result.errors, [])
            let menuBar = result.config.menuBar
            assertEquals(menuBar.enabled, true)
            assertEquals(menuBar.theme, .chips)
            assertEquals(menuBar.dimEmptyWorkspaces, true)
            assertEquals(menuBar.showMode, false)
            assertEquals(menuBar.colors, MenuBarColors(accent: .systemAccent, focused: .auto, occupied: .auto, empty: .auto))
            // The built-in config agrees with the defaults
            assertEquals(defaultConfig.menuBar, MenuBarConfig())
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                config-version = 2
                [menu-bar]
                    enabled = false
                    theme = 'square'
                    dim-empty-workspaces = false
                    show-mode = true
                [menu-bar.colors]
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
                theme: .square,
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
            assertEquals(MenuBarTheme.allCases.map(\.rawValue), ["chips", "square", "minimal"])
            for theme in MenuBarTheme.allCases {
                let result = parseConfig("config-version = 2\nmenu-bar.theme = '\(theme.rawValue)'")
                assertEquals(result.errors, [])
                assertEquals(result.warnings, [])
                assertEquals(result.config.menuBar.theme, theme)
            }
        }

        /// The item showed the icons of the apps once: the 'chips-icons' theme and the 'show-app-icons' key, which the
        /// settings window wrote to the config of the user. Such a config still loads
        @Test func testAppIconsOfThePast_acceptedWithAWarning() {
            let theme = parseConfig("config-version = 2\n[menu-bar]\ntheme = 'chips-icons'\nshow-mode = true")
            assertEquals(theme.strErrors, [])
            assertEquals(theme.strWarnings, [
                "[WARNING] menu-bar.theme: The menu bar item doesn't show app icons anymore: 'chips-icons' is treated as 'chips'. Please change it in the config",
            ])
            assertEquals(theme.config.menuBar, MenuBarConfig(theme: .chips, showMode: true))

            for value in ["true", "false"] {
                let key = parseConfig("config-version = 2\n[menu-bar]\ntheme = 'square'\nshow-app-icons = \(value)\ndim-empty-workspaces = false")
                assertEquals(key.strErrors, [])
                assertEquals(key.strWarnings, [
                    "[WARNING] menu-bar.show-app-icons: The menu bar item doesn't show app icons anymore: 'show-app-icons' is ignored. Please drop it from the config",
                ])
                assertEquals(key.config.menuBar, MenuBarConfig(theme: .square, dimEmptyWorkspaces: false))
            }

            let both = parseConfig("config-version = 2\nmenu-bar.theme = 'chips-icons'\nmenu-bar.show-app-icons = true")
            assertEquals(both.strErrors, [])
            assertEquals(both.warnings.count, 2)
            assertEquals(both.config.menuBar, MenuBarConfig())
            // Warnings don't keep the config from being applied
            assertEquals(both.allowReloadConfig, true)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig("menu-bar.theme = 'pills'").strErrors,
                ["[ERROR] menu-bar.theme: Can't parse menu bar theme 'pills'. Possible values: (chips|square|minimal)"],
            )
            assertEquals(parseConfig("menu-bar.them = 'chips'").strErrors, ["[ERROR] menu-bar.them: Unknown key"])
            assertEquals(parseConfig("menu-bar.colors.focus = 'auto'").strErrors, ["[ERROR] menu-bar.colors.focus: Unknown key"])
            assertEquals(
                parseConfig("menu-bar.enabled = 'yes'").strErrors,
                ["[ERROR] menu-bar.enabled: Expected type is 'Bool'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig("menu-bar.show-app-icons = 1").strErrors,
                ["[ERROR] menu-bar.show-app-icons: Expected type is 'Bool'. But actual type is 'Int'"],
            )
            assertEquals(parseConfig("config-version = 2\nmenu-bar.show-app-icons = 1").strWarnings, [])
            assertEquals(
                parseConfig("menu-bar = 'chips'").strErrors,
                ["[ERROR] menu-bar: Expected type is 'Table'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig("menu-bar.colors.focused = 'red'").strErrors,
                ["[ERROR] menu-bar.colors.focused: Can't parse color 'red'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent', 'auto'"],
            )
            // 'auto' has no meaning for the accent
            assertEquals(
                parseConfig("menu-bar.colors.accent = 'auto'").strErrors,
                ["[ERROR] menu-bar.colors.accent: Can't parse color 'auto'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'"],
            )
            assertEquals(
                parseConfig("menu-bar.colors.empty = 0xFF0000").strErrors,
                ["[ERROR] menu-bar.colors.empty: Expected type is 'String'. But actual type is 'Int'"],
            )
            // The value with an error is ignored
            assertEquals(parseConfig("menu-bar.colors.focused = 'red'").config.menuBar.colors.focused, .auto)
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

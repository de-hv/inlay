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
            assertEquals(menuBar.showAppIcons, nil)
            assertEquals(menuBar.effectiveShowAppIcons, false)
            assertEquals(menuBar.dimEmptyWorkspaces, true)
            assertEquals(menuBar.showMode, false)
            assertEquals(menuBar.colors, MenuBarColors(accent: .systemAccent, focused: .auto, occupied: .auto, empty: .auto))
            // The built-in config agrees with the defaults
            assertEquals(defaultConfig.menuBar, MenuBarConfig())
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                [menu-bar]
                    enabled = false
                    theme = 'square'
                    show-app-icons = true
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
            let expected = MenuBarConfig(
                enabled: false,
                theme: .square,
                showAppIcons: true,
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
            for (raw, theme, icons) in [
                ("chips", MenuBarTheme.chips, false),
                ("chips-icons", .chipsIcons, true),
                ("square", .square, false),
                ("minimal", .minimal, false),
            ] {
                let result = parseConfig("menu-bar.theme = '\(raw)'")
                assertEquals(result.errors, [])
                assertEquals(result.config.menuBar.theme, theme)
                // The theme decides when show-app-icons is omitted
                assertEquals(result.config.menuBar.effectiveShowAppIcons, icons)
            }
            // The key wins over the theme
            let off = parseConfig("menu-bar.theme = 'chips-icons'\nmenu-bar.show-app-icons = false").config.menuBar
            assertEquals(off.effectiveShowAppIcons, false)
            let on = parseConfig("menu-bar.theme = 'minimal'\nmenu-bar.show-app-icons = true").config.menuBar
            assertEquals(on.effectiveShowAppIcons, true)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig("menu-bar.theme = 'pills'").strErrors,
                ["[ERROR] menu-bar.theme: Can't parse menu bar theme 'pills'. Possible values: (chips|chips-icons|square|minimal)"],
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

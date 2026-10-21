@testable import AppBundle
import Common
import Testing

extension InlayTests {
    /// [theme] palette: the colors of the menu bar item and of the borders. See: ThemePalette
    @Suite @MainActor struct ThemeConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            assertEquals(parseConfig("config-version = 2").config.theme.palette, .catppuccin)
            assertEquals(defaultConfig.theme, ThemeConfig())
            for palette in ThemePalette.allCases {
                let result = parseConfig("theme.palette = '\(palette.rawValue)'")
                assertEquals(result.errors, [])
                assertEquals(result.config.theme.palette, palette)
            }
            assertEquals(
                parseConfig("theme.palette = 'solarized'").strErrors,
                ["[ERROR] theme.palette: Can't parse palette 'solarized'. Possible values: (system|catppuccin|tokyo-night|gruvbox|nord|rose-pine|dracula|everforest)"],
            )
            assertEquals(SettingsKey.themePalette.defaultValue, .string(ThemeConfig().palette.rawValue))
        }

        /// Every palette but 'system' has a light and a dark variant, and they differ
        @Test func testEveryPaletteHasTwoVariants() {
            assertNil(ThemePalette.system.colors(isDark: true))
            assertNil(ThemePalette.system.colors(isDark: false))
            for palette in ThemePalette.allCases where palette != .system {
                let dark = palette.colors(isDark: true).orDie()
                let light = palette.colors(isDark: false).orDie()
                assertEquals(dark != light, true, additionalMsg: palette.rawValue)
                // The focused workspace and the active border share the main color
                assertEquals(dark.focused, dark.activeBorder, additionalMsg: palette.rawValue)
            }
        }

        /// The palette gives the colors that are 'auto'. A color written in [menu-bar.colors] wins
        @Test func testMenuBarColors() {
            let mocha = ThemePalette.catppuccin.colors(isDark: true).orDie()
            let latte = ThemePalette.catppuccin.colors(isDark: false).orDie()
            assertEquals(MenuBarColors().applying(.catppuccin, isDark: true).focused, .rgba(mocha.focused))
            assertEquals(MenuBarColors().applying(.catppuccin, isDark: false).focused, .rgba(latte.focused))
            let mine = MenuBarColors(focused: .rgba(Rgba(hex: "#61AFEF").orDie()))
            assertEquals(mine.applying(.catppuccin, isDark: true).focused, .rgba(Rgba(hex: "#61AFEF").orDie()))
            assertEquals(mine.applying(.catppuccin, isDark: true).occupied, .rgba(mocha.occupied))
            assertEquals(MenuBarColors().applying(.system, isDark: true), MenuBarColors())
            // With a palette the item has fixed colors: it isn't a template image anymore
            let palette = MenuBarPalette.resolve(MenuBarConfig(palette: .nord), style: .chips, isDarkBar: true, systemAccent: .white)
            assertEquals(palette.isTemplate, false)
            assertEquals(palette.focused, ThemePalette.nord.colors(isDark: true)?.focused)
        }

        /// The palette gives the border colors left at their default. The ones written in [borders] win
        @Test func testBorderColors() {
            let gruvbox = ThemePalette.gruvbox.colors(isDark: true).orDie()
            let borders = BordersConfig().applying(.gruvbox, isDark: true)
            assertEquals(borders.activeColor, .rgba(gruvbox.activeBorder))
            assertEquals(borders.inactiveColor, .rgba(gruvbox.inactiveBorder))
            assertEquals(borders.floatingColor, .rgba(gruvbox.floatingBorder))
            let mine = BordersConfig().copy(\.activeColor, .rgba(Rgba(hex: "#61AFEF").orDie())).applying(.gruvbox, isDark: true)
            assertEquals(mine.activeColor, .rgba(Rgba(hex: "#61AFEF").orDie()))
            assertEquals(mine.inactiveColor, .rgba(gruvbox.inactiveBorder))
            assertEquals(BordersConfig().applying(.system, isDark: true), BordersConfig())
        }
    }
}

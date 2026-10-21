@testable import AppBundle
import Common
import Testing

extension InlayTests {
    /// [theme] palette: the colors of the menu bar item and of the borders. See: ThemePalette
    @Suite @MainActor struct ThemeConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            assertEquals(parseConfig("config-version = 2").config.theme.palette, .oneDark)
            assertEquals(defaultConfig.theme, ThemeConfig())
            for palette in ThemePalette.allCases {
                let result = parseConfig("theme.palette = '\(palette.rawValue)'")
                assertEquals(result.errors, [])
                assertEquals(result.config.theme.palette, palette)
            }
            assertEquals(
                parseConfig("theme.palette = 'solarized'").strErrors,
                ["[ERROR] theme.palette: Can't parse palette 'solarized'. Possible values: (system|catppuccin|tokyo-night|gruvbox|nord|rose-pine|dracula|everforest|kanagawa|oxocarbon|ayu|one-dark|mono|material|flexoki)"],
            )
            assertEquals(SettingsKey.themePalette.defaultValue, .string(ThemeConfig().palette.rawValue))
            assertEquals(SettingsKey.themeSeed.defaultValue, .string(ThemeConfig().seed.description))
        }

        /// [theme] seed: the color that 'material' is made from
        @Test func testParseSeed() {
            assertEquals(ThemeConfig().seed, .rgba(MaterialPalette.baselineSeed))
            assertEquals(parseConfig("theme.seed = '#B5651D'").config.theme.seed, .rgba(Rgba(hex: "#B5651D").orDie()))
            assertEquals(parseConfig("theme.seed = 'system-accent'").config.theme.seed, .systemAccent)
            assertEquals(
                parseConfig("theme.seed = 'auto'").strErrors,
                ["[ERROR] theme.seed: Can't parse color 'auto'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'"],
            )
            // 'system-accent' is the accent color of the system, and the alpha doesn't count
            let accent = Rgba(hex: "#FF9500").orDie()
            assertEquals(ThemeConfig(seed: .systemAccent).seedColor(systemAccent: accent), accent)
            assertEquals(ThemeConfig(seed: .rgba(Rgba(hex: "#B5651D80").orDie())).seedColor(systemAccent: accent), Rgba(hex: "#B5651D").orDie())
        }

        /// The baseline seed gives the colors of the Material 3 baseline. Another seed keeps its hue, and the
        /// colors keep the lightness that Material gives to their role
        @Test func testMaterial() throws {
            assertEquals(ThemePalette.material.colors(isDark: true)?.focused.hex, "#D0BCFF")
            assertEquals(ThemePalette.material.colors(isDark: false)?.focused.hex, "#6750A4")
            let seed = Rgba(hex: "#B5651D").orDie()
            let dark = try #require(ThemePalette.material.colors(isDark: true, seed: seed))
            let light = try #require(ThemePalette.material.colors(isDark: false, seed: seed))
            assertEquals(dark != ThemePalette.material.colors(isDark: true), true)
            func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }
            let hue = Lch(seed).hue
            assertTrue(near(Lch(dark.focused).hue, hue, 6))
            assertTrue(near(Lch(dark.focused).lightness, 80, 1))
            assertTrue(near(Lch(light.focused).lightness, 40, 1))
            assertTrue(near(Lch(dark.inactiveBorder).lightness, 30, 1))
            // The palette is the same as the others: the main color is the active border, the accent the floating one
            assertEquals(dark.focused, dark.activeBorder)
            assertEquals(dark.accent, dark.floatingBorder)
            // The other palettes ignore the seed
            assertEquals(ThemePalette.nord.colors(isDark: true, seed: seed), ThemePalette.nord.colors(isDark: true))
            assertEquals(MenuBarColors().applying(.material, seed: seed, isDark: true).focused, .rgba(dark.focused))
            assertEquals(BordersConfig().applying(.material, seed: seed, isDark: false).activeColor, .rgba(light.focused))
        }

        /// sRGB -> CIELAB -> sRGB gives the color back
        @Test func testLchRoundTrip() {
            for hex in ["#6750A4", "#B5651D", "#00A86B", "#FFFFFF", "#000000", "#808080"] {
                assertEquals(Lch(Rgba(hex: hex).orDie()).rgba.hex, hex)
            }
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

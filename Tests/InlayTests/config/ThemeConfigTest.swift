@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// The key 'theme': the themes of Inlay and of the user, their colors under the ones of the config, and a theme
    /// for each appearance of macOS. See: ThemeResolver
    @Suite @MainActor struct ThemeConfigTest {
        private let folder: URL

        init() throws {
            setUpWorkspacesForTests()
            folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "inlay-themes-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder.appending(path: "themes"), withIntermediateDirectories: true)
        }

        /// The config in a folder of its own, with the themes of the user that are given
        private func parse(_ config: String, themes: [String: String] = [:]) throws -> ParseConfigResult {
            for (name, text) in themes {
                try text.write(to: folder.appending(path: "themes/\(name).lua"), atomically: true, encoding: .utf8)
            }
            let url = folder.appending(path: "inlay.lua")
            try config.write(to: url, atomically: true, encoding: .utf8)
            return parseConfig(LuaConfigLoader.load(file: url))
        }

        private func hex(_ color: ConfigColor?) -> String { color.map { "\($0)" } ?? "nil" }

        /// Without the key, the theme is 'material'. `theme = {}`: no theme, the defaults of the code
        @Test func testDefaultTheme() {
            let result = parseConfig(lua: "inlay.config({})")
            assertEquals(result.strErrors, [])
            assertEquals(result.strWarnings, [])
            assertEquals(result.config.borders, parseConfig(lua: "inlay.config({ theme = 'material' })").config.borders)
            assertEquals([result.config.borders.activeColor, result.config.borders.inactiveColor].map(hex), ["#B59DF7", "#999D9F"])
            assertEquals(result.config.menuBar.systemColors, true)
            assertEquals(hex(result.config.menuBar.colors.occupied), "#CAC4D0")
            assertEquals(result.config.lightAppearance, nil)
            assertEquals(result.themeFiles, [])

            let none = parseConfig(lua: "inlay.config({ theme = {} })")
            assertEquals(none.config.borders, BordersConfig())
            assertEquals(none.config.menuBar, MenuBarConfig())
        }

        /// A theme sets the glow and systemColors too, and another theme doesn't take them from 'material'
        @Test func testGlowAndSystemColors() throws {
            let result = try parse("inlay.config({ theme = 'neon' })", themes: [
                "neon": "return { borders = { activeColor = '#E070E0', glow = true, glowRadius = 14 }, menuBar = { systemColors = false } }",
            ])
            assertEquals(result.strErrors, [])
            assertEquals(result.config.borders.glow, true)
            assertEquals(result.config.borders.glowRadius, 14)
            assertEquals(result.config.menuBar.systemColors, false)
            assertEquals(parseConfig(lua: "inlay.config({ theme = 'nord' })").config.menuBar.systemColors, false)

            let wrong = try parse("inlay.config({ theme = 'bad' })", themes: ["bad": "return { borders = { glow = 'yes', glowRadius = 99 }, menuBar = { systemColors = 1 } }"])
            assertEquals(wrong.strErrors.count, 3, additionalMsg: wrong.strErrors.joined(separator: "\n"))
            assertEquals(wrong.config.borders.glowRadius, BordersConfig().glowRadius)
        }

        @Test func testBuiltInTheme() {
            let result = parseConfig(lua: "inlay.config({ theme = 'nord' })")
            assertEquals(result.strErrors, [])
            assertEquals(result.strWarnings, [])
            let borders = result.config.borders
            assertEquals([borders.activeColor, borders.inactiveColor, borders.floatingColor].map(hex), ["#88C0D0", "#4C566AB3", "#B48EAD"])
            assertEquals(hex(borders.fullscreenColor), "#EBCB8B")
            assertEquals(borders.modeColors.mapValues { "\($0)" }, ["resize": "#A3BE8C", "service": "#BF616A"])
            // The rest of the table keeps its defaults
            assertEquals(borders.width, BordersConfig().width)
            // The menu bar: the focused workspace; the other colors follow the menu bar
            let colors = result.config.menuBar.colors
            assertEquals([colors.focused, colors.accent, colors.occupied, colors.empty].map(hex), ["#88C0D0", "#B48EAD", "auto", "auto"])
        }

        /// Every theme of Inlay loads without a problem, and they are the ones that the reference lists
        @Test func testEveryBuiltInTheme() throws {
            assertEquals(builtInThemeNames, ["catppuccin", "everforest", "gruvbox", "kanagawa", "material", "nord", "rose-pine", "tokyo-night"])
            for name in builtInThemeNames {
                let result = parseConfig(lua: "inlay.config({ theme = '\(name)' })")
                assertEquals(result.strErrors, [], additionalMsg: name)
                assertEquals(result.strWarnings, [], additionalMsg: name)
                assertEquals(result.config.borders.activeColor != BordersConfig().activeColor, true, additionalMsg: name)
            }
            let reference = try String(contentsOf: projectRoot.appending(path: "docs/config-reference.lua"), encoding: .utf8)
            assertTrue(reference.contains(builtInThemeNames.map { "'\($0)'" }.joined(separator: "|")))
        }

        /// What the config says wins; the theme only fills the colors that it doesn't set
        @Test func testTheConfigWins() {
            let result = parseConfig(lua: """
                inlay.config({
                  theme = 'nord',
                  borders = { width = 6, activeColor = '#FF0000', modeColors = { service = '#00FF00' } },
                  menuBar = { colors = { empty = '#111111' } },
                })
                """)
            assertEquals(result.strErrors, [])
            let borders = result.config.borders
            assertEquals(borders.width, 6)
            assertEquals(hex(borders.activeColor), "#FF0000")
            assertEquals(hex(borders.inactiveColor), "#4C566AB3")
            assertEquals(borders.modeColors.mapValues { "\($0)" }, ["resize": "#A3BE8C", "service": "#00FF00"])
            assertEquals(hex(result.config.menuBar.colors.empty), "#111111")
            assertEquals(hex(result.config.menuBar.colors.focused), "#88C0D0")
        }

        /// A table: colors of its own, over another theme or over the defaults
        @Test func testThemeTable() {
            let partial = parseConfig(lua: "inlay.config({ theme = { borders = { activeColor = '#E06C75' } } })")
            assertEquals(partial.strErrors, [])
            assertEquals(hex(partial.config.borders.activeColor), "#E06C75")
            // What it doesn't set: the defaults
            assertEquals(partial.config.borders.inactiveColor, BordersConfig().inactiveColor)
            assertEquals(partial.config.borders.floatingColor, BordersConfig().floatingColor)
            assertEquals(partial.config.menuBar.colors, MenuBarColors())

            let extended = parseConfig(lua: "inlay.config({ theme = { extends = 'nord', borders = { activeColor = '#ECEFF4' } } })")
            assertEquals(extended.strErrors, [])
            assertEquals(hex(extended.config.borders.activeColor), "#ECEFF4")
            assertEquals(hex(extended.config.borders.floatingColor), "#B48EAD")
        }

        /// A theme of the user, in themes/ next to the config: it may extend another one, and it takes the place of a
        /// theme of Inlay with the same name
        @Test func testUserTheme() throws {
            let result = try parse("inlay.config({ theme = 'mio' })", themes: [
                "mio": "return { extends = 'nord', borders = { activeColor = '#E06C75' } }",
            ])
            assertEquals(result.strErrors, [])
            assertEquals(hex(result.config.borders.activeColor), "#E06C75")
            assertEquals(hex(result.config.borders.floatingColor), "#B48EAD")
            // Saving it reloads the config
            assertTrue(result.themeFiles.contains { $0.url?.lastPathComponent == "mio.lua" && $0.text != nil })

            let shadowing = try parse("inlay.config({ theme = 'nord' })", themes: ["nord": "return { borders = { activeColor = '#123456' } }"])
            assertEquals(hex(shadowing.config.borders.activeColor), "#123456")
            assertEquals(shadowing.config.borders.floatingColor, BordersConfig().floatingColor)
        }

        /// A theme that doesn't exist: a warning with the themes, and the defaults. Creating it reloads the config
        @Test func testUnknownTheme() throws {
            let result = try parse("inlay.config({ theme = 'nordd' })")
            assertEquals(result.strErrors, [])
            assertEquals(result.strWarnings.count, 1)
            assertEquals(result.strWarnings[0].contains("There is no theme 'nordd'"), true, additionalMsg: result.strWarnings[0])
            assertEquals(result.strWarnings[0].contains("nord, rose-pine"), true, additionalMsg: result.strWarnings[0])
            assertEquals(result.config.borders, BordersConfig())
            assertEquals(result.themeFiles.map { $0.url?.lastPathComponent }, ["nordd.lua"])
            assertEquals(result.themeFiles.first?.text, nil)

            assertEquals(parseConfig(lua: "inlay.config({ theme = '../inlay' })").strErrors.count, 1)
            assertEquals(parseConfig(lua: "inlay.config({ theme = 3 })").strErrors.count, 1)
        }

        /// A theme only has colors: anything else is an error, and the rest of the theme still applies
        @Test func testThemeOnlyHasColors() throws {
            let result = try parse("inlay.config({ theme = 'mio' })", themes: [
                "mio": "return { gaps = 4, borders = { width = 8, activeColor = 'blue', floatingColor = '#E06C75' } }",
            ])
            assertEquals(result.strErrors.count, 3, additionalMsg: result.strErrors.joined(separator: "\n"))
            assertTrue(result.strErrors.allSatisfy { $0.contains("themes/mio.lua") })
            assertEquals(hex(result.config.borders.floatingColor), "#E06C75")
            assertEquals(result.config.borders.width, BordersConfig().width)
            assertEquals(result.config.borders.activeColor, BordersConfig().activeColor)

            let inline = parseConfig(lua: "inlay.config({ theme = { menuBar = { theme = 'hypr', colors = { focused = 'auto' } } } })")
            assertEquals(inline.strErrors, ["[ERROR] theme.menuBar.theme: " + themeKeysMessage])
        }

        /// Lua that doesn't run, in a theme of the user: an error that names the file
        @Test func testBrokenUserTheme() throws {
            let result = try parse("inlay.config({ theme = 'mio' })", themes: ["mio": "return {"])
            assertEquals(result.strErrors.count, 1)
            assertEquals(result.strErrors[0].contains("themes/mio.lua"), true, additionalMsg: result.strErrors[0])
        }

        @Test func testExtendsLoop() throws {
            let result = try parse("inlay.config({ theme = 'a' })", themes: [
                "a": "return { extends = 'b' }",
                "b": "return { extends = 'a' }",
            ])
            assertEquals(result.strErrors.contains { $0.contains("loop") }, true, additionalMsg: result.strErrors.joined(separator: "\n"))
        }

        /// A theme for each appearance: the dark one is the config, the light one is kept aside
        @Test func testDarkAndLight() {
            let result = parseConfig(lua: """
                inlay.config({
                  theme = { dark = 'tokyo-night', light = 'rose-pine' },
                  borders = { width = 6, floatingColor = '#FFFFFF' },
                })
                """)
            assertEquals(result.strErrors, [])
            assertEquals(hex(result.config.borders.activeColor), "#7AA2F7")
            let light = result.config.lightAppearance
            assertEquals(hex(light?.borders.activeColor), "#286983")
            assertEquals(hex(light?.menuBar.colors.focused), "#286983")
            // The rest of the config, and its colors, are the same in both
            assertEquals(light?.borders.width, 6)
            assertEquals(hex(light?.borders.floatingColor), "#FFFFFF")
            // The tests run as dark
            assertEquals(hex(result.config.bordersForAppearance.activeColor), "#7AA2F7")

            assertEquals(parseConfig(lua: "inlay.config({ theme = { dark = 'nord' } })").strErrors.count, 1)
            assertEquals(parseConfig(lua: "inlay.config({ theme = { dark = 'nord', light = 'nord', extends = 'nord' } })").strErrors.count, 1)
        }
    }
}

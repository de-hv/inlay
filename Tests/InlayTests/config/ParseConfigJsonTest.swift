@testable import AppBundle
import Common
import Testing

extension InlayTests {
    /// parseConfig reads a table, whatever the format of the file: TOML and Lua give the same table
    @Suite @MainActor struct ParseConfigJsonTest {
        @Test func testTomlAndLuaGiveTheSameTable() {
            let toml = """
                config-version = 2
                start-at-login = true
                persistent-workspaces = ['1', '2']
                after-startup-command = []

                [gaps]
                    inner.horizontal = 8
                    outer.left       = 8

                [tiling]
                    split-ratio = 0.5

                [mode.main.binding]
                    cmd-alt-h = ['workspace 1', 'mode main']

                [[on-window-detected]]
                    if.app-id = 'com.mitchellh.ghostty'
                    run = ['layout tiling', 'move-node-to-workspace 1']
                """
            let lua = """
                return {
                  ['config-version'] = 2,
                  ['start-at-login'] = true,
                  ['persistent-workspaces'] = { '1', '2' },
                  ['after-startup-command'] = {},
                  gaps = { inner = { horizontal = 8 }, outer = { left = 8 } },
                  tiling = { ['split-ratio'] = 0.5 },
                  mode = { main = { binding = { ['cmd-alt-h'] = { 'workspace 1', 'mode main' } } } },
                  ['on-window-detected'] = {
                    { ['if'] = { ['app-id'] = 'com.mitchellh.ghostty' }, run = { 'layout tiling', 'move-node-to-workspace 1' } },
                  },
                }
                """
            var tomlErrors: [ConfigParseDiagnostic] = []
            let tomlTable = tomlToJson(toml, &tomlErrors)
            let luaConfig = LuaConfigLoader.load(lua)
            assertEquals(tomlErrors, [])
            assertEquals(luaConfig.errors, [])

            // {} of Lua is an empty table of keys, [] of TOML an empty array: the rest is the same
            var luaTable = luaConfig.table
            assertEquals(luaTable["after-startup-command"], .dict([:]))
            luaTable["after-startup-command"] = .array([])
            assertEquals(luaTable, tomlTable)

            let result = parseConfig(luaConfig)
            assertEquals(result.errors, [])
            assertEquals(result.config.persistentWorkspaces, ["1", "2"])
            assertEquals(result.config.tiling.splitRatio, 0.5)
            assertEquals(result.config.onWindowDetected.count, 1)
            assertEquals(result.config.modes["main"]?.bindings.count, 1)
        }

        /// {} is an empty array where the config expects one
        @Test func testEmptyTableIsAnEmptyArray() {
            let result = parseConfig(LuaConfigLoader.load("""
                return {
                  ['after-startup-command'] = {},
                  ['on-window-detected'] = {},
                  ['exec-on-workspace-change'] = {},
                  ['key-mapping'] = { ['key-notation-to-key-code'] = {} },
                }
                """))
            assertEquals(result.errors, [])
            assertEquals(result.config.onWindowDetected.count, 0)
        }

        /// The errors of running the Lua config stop the reload: the config in use stays
        @Test func testLuaErrorsPreventTheReload() {
            let result = parseConfig(LuaConfigLoader.load("return { gaps = "))
            assertEquals(result.allowReloadConfig, false)
            assertEquals(result.errors.map { $0.description(.error) }, ["[ERROR] inlay.lua:1: unexpected symbol near <eof>"])
        }
    }
}

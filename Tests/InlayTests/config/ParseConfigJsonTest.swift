@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// parseConfig reads a table, whatever the format of the file: TOML and Lua give the same table
    @Suite @MainActor struct ParseConfigJsonTest {
        @Test func testTomlAndLuaGiveTheSameTable() {
            let toml = """
                configVersion = 2
                startAtLogin = true
                persistentWorkspaces = ['1', '2']
                afterStartupCommand = []

                [gaps]
                    inner.horizontal = 8
                    outer.left       = 8

                [tiling]
                    splitRatio = 0.5

                [mode.main.binding]
                    cmd-alt-h = ['workspace 1', 'mode main']

                [[onWindowDetected]]
                    match.appId = 'com.mitchellh.ghostty'
                    run = ['layout tiling', 'move-node-to-workspace 1']
                """
            let lua = """
                return {
                  configVersion = 2,
                  startAtLogin = true,
                  persistentWorkspaces = { '1', '2' },
                  afterStartupCommand = {},
                  gaps = { inner = { horizontal = 8 }, outer = { left = 8 } },
                  tiling = { splitRatio = 0.5 },
                  mode = { main = { binding = { ['cmd-alt-h'] = { 'workspace 1', 'mode main' } } } },
                  onWindowDetected = {
                    { match = { appId = 'com.mitchellh.ghostty' }, run = { 'layout tiling', 'move-node-to-workspace 1' } },
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
            assertEquals(luaTable["afterStartupCommand"], .dict([:]))
            luaTable["afterStartupCommand"] = .array([])
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
                  afterStartupCommand = {},
                  onWindowDetected = {},
                  execOnWorkspaceChange = {},
                  keyMapping = { keyNotationToKeyCode = {} },
                }
                """))
            assertEquals(result.errors, [])
            assertEquals(result.config.onWindowDetected.count, 0)
        }

        /// The config that the app reads: inlay.lua and the modules of its folder
        @Test func testReadConfigWithModules() throws {
            let dir = FileManager.default.temporaryDirectory.appending(path: "inlay-read-config-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { _ = try? FileManager.default.removeItem(at: dir) }
            try "return { mode = { main = { binding = { ['cmd-alt-h'] = 'focus left' } } } }".write(to: dir.appending(path: "binds.lua"), atomically: true, encoding: .utf8)
            try "return inlay.merge({ configVersion = 2 }, require('binds'))".write(to: dir.appending(path: "inlay.lua"), atomically: true, encoding: .utf8)

            let result = readConfig(forceConfigUrl: dir.appending(path: "inlay.lua"))
            assertEquals(result.parseConfigResult.errors, [])
            assertEquals(result.parseConfigResult.config.modes["main"]?.bindings.count, 1)
            assertEquals(result.files.map { $0.url?.lastPathComponent }, ["inlay.lua", "binds.lua"])
            assertEquals(result.text, "return inlay.merge({ configVersion = 2 }, require('binds'))")
        }

        /// The errors of running the Lua config stop the reload: the config in use stays
        @Test func testLuaErrorsPreventTheReload() {
            let result = parseConfig(LuaConfigLoader.load("return { gaps = "))
            assertEquals(result.allowReloadConfig, false)
            assertEquals(result.errors.map { $0.description(.error) }, ["[ERROR] inlay.lua:1: unexpected symbol near <eof>"])
        }
    }
}

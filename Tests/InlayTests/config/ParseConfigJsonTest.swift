@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// parseConfig reads the table that inlay.lua returns
    @Suite @MainActor struct ParseConfigJsonTest {
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
            try "return inlay.merge({}, require('binds'))".write(to: dir.appending(path: "inlay.lua"), atomically: true, encoding: .utf8)

            let result = readConfig(forceConfigUrl: dir.appending(path: "inlay.lua"))
            assertEquals(result.parseConfigResult.errors, [])
            // The binding of the user, over the ones of the built-in config
            let bindings = result.parseConfigResult.config.modes["main"]?.bindings.values.map(\.descriptionWithKeyNotation) ?? []
            assertEquals(bindings.contains("cmd-alt-h"), true)
            assertEquals(bindings.contains("cmd-alt-shift-b"), true)
            assertEquals(result.files.map { $0.url?.lastPathComponent }, ["inlay.lua", "binds.lua"])
            assertEquals(result.text, "return inlay.merge({}, require('binds'))")
        }

        /// The errors of running the Lua config stop the reload: the config in use stays
        @Test func testLuaErrorsPreventTheReload() {
            let result = parseConfig(LuaConfigLoader.load("return { gaps = "))
            assertEquals(result.allowReloadConfig, false)
            assertEquals(result.errors.map { $0.description(.error) }, ["[ERROR] inlay.lua:1: unexpected symbol near <eof>"])
        }
    }
}

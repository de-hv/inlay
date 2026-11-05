@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct ConfigCommandTest {
        private let folder: URL

        init() throws {
            setUpWorkspacesForTests()
            folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "inlay-show-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        /// A config of the user in a folder of its own, as the config in use
        private func use(_ files: [String: String]) throws {
            for (name, text) in files {
                try text.write(to: folder.appending(path: name), atomically: true, encoding: .utf8)
            }
            configUrl = folder.appending(path: "inlay.lua")
        }

        private func run(_ command: String) async -> CmdResult {
            await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
        }

        @Test func testParse() {
            for command in ["config --show", "config --show borders", "config --show --mine", "config --show --keys", "config --show menuBar --json", "config --types", "config --config-path", "config --unlink"] {
                assertEquals(parseCommand(command).errorOrNil, nil, additionalMsg: command)
            }
            assertEquals(parseCommand("config").errorOrNil, "Mandatory flag is not specified (--show|--explain|--types|--config-path|--use|--unlink)")
            assertEquals(parseCommand("config --mine").errorOrNil, "Mandatory flag is not specified (--show|--explain|--types|--config-path|--use|--unlink)")
            assertEquals(parseCommand("config --types --mine").errorOrNil, "--mine flag requires --show flag")
            assertEquals(parseCommand("config --config-path --json").errorOrNil, "--json flag requires --show flag")
            assertEquals(parseCommand("config --show --keys --json").errorOrNil, "--keys and --json can't go together: --keys prints the paths of the keys, --json their values")
            assertEquals(parseCommand("config --show --types").errorOrNil, "Conflicting flags are specified: --show, --types")
            assertTrue(parseCommand("config --use").errorOrNil != nil)
        }

        /// The flags of AeroSpace only knew the key bindings: an error names the one that replaces them
        @Test func testRemovedFlags() {
            assertEquals(parseCommand("config --get gaps").errorOrNil, "'--get' is gone. The value of a key, and where it comes from: config --show gaps")
            assertEquals(parseCommand("config --all-keys").errorOrNil, "'--all-keys' is gone. Every key of the config: config --show --keys")
            assertEquals(parseCommand("config --major-keys").errorOrNil, "'--major-keys' is gone. Every key of the config: config --show --keys")
        }

        @Test func testConfigPath() async {
            let result = await run("config --config-path")
            assertEquals(result.exitCode.rawValue, 0)
            assertEquals(result.stdout, [configUrl.absoluteURL.path])
        }

        /// Every value, with where it comes from and its possible values
        @Test func testShow() async throws {
            try use(["inlay.lua": """
                return {
                  theme = { extends = 'gruvbox', menuBar = { systemColors = true } },
                  menuBar = { perMonitor = true },
                }
                """])
            let result = await run("config --show menuBar")
            assertEquals(result.exitCode.rawValue, 0)
            let text = result.stdout.joined(separator: "\n")
            assertEquals(text.hasPrefix("menuBar = {"), true, additionalMsg: text)
            let lines = text.split(separator: "\n").map(String.init)
            func line(_ key: String) -> String { lines.first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(key + " ") } ?? "" }
            assertEquals(line("perMonitor").contains("= true,") && line("perMonitor").contains("-- yours (inlay.lua:3) · true|false"), true, additionalMsg: line("perMonitor"))
            assertEquals(line("theme").contains("= 'hypr',") && line("theme").contains("-- Inlay"), true, additionalMsg: line("theme"))
            assertEquals(line("systemColors").contains("= true,") && line("systemColors").contains("-- theme"), true, additionalMsg: line("systemColors"))
            assertEquals(line("focused").contains("'#D8A657'") && line("focused").contains("-- theme"), true, additionalMsg: line("focused"))
            assertEquals(line("occupied").contains("'auto'") && line("occupied").contains("-- default"), true, additionalMsg: line("occupied"))

            // The whole config is valid Lua
            let all = await run("config --show")
            let lua = all.stdout.joined(separator: "\n")
            let loaded = LuaConfigLoader.load(lua)
            assertEquals(loaded.errors, [])
            assertEquals(loaded.table["menuBar"]?.asDictOrNil?["perMonitor"], .bool(true))
            assertEquals(loaded.table["workspaces"]?.asArrayOrNil?.count, 7)
        }

        @Test func testShowKeysAndJson() async throws {
            try use(["inlay.lua": "return {}"])
            let keys = await run("config --show --keys").stdout.joined(separator: "\n").split(separator: "\n").map(String.init)
            for key in ["borders.width", "borders.glowRadius", "menuBar.colors.occupied", "gaps.inner.horizontal", "theme", "workspaces", "mode.main.binding['cmd-alt-shift-b']"] {
                assertEquals(keys.contains(key), true, additionalMsg: key)
            }
            assertEquals(keys.contains { $0.contains("-") && !$0.contains("[") }, false, additionalMsg: "camelCase names only")

            let json = await run("config --show borders --json").stdout.joined()
            let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            assertEquals(object?["width"] as? Int, 2)
            assertEquals(object?["glowRadius"] as? Int, 12)

            let missing = await run("config --show bordres")
            assertEquals(missing.exitCode.rawValue != 0, true)
            assertTrue(missing.stderr.joined().hasPrefix("The config has no key or table 'bordres'"))
        }

        /// Only what the user writes: what changes something, and what repeats the base
        @Test func testShowMine() async throws {
            try use([
                "inlay.lua": """
                    return inlay.merge({
                      menuBar = { perMonitor = true },
                    }, require('binds'))
                    """,
                "binds.lua": """
                    return { mode = { main = { binding = {
                      ['cmd-alt-shift-b'] = 'balance-sizes',
                      ['cmd-alt-t'] = 'exec-and-forget open -a Terminal',
                    } } } }
                    """,
            ])
            let text = await run("config --show --mine").stdout.joined(separator: "\n")
            let parts = text.components(separatedBy: "-- The same as without them")
            assertEquals(parts.count, 2, additionalMsg: text)
            assertEquals(parts[0].contains("menuBar.perMonitor = true  -- inlay.lua:2"), true, additionalMsg: text)
            assertEquals(parts[0].contains("mode.main.binding['cmd-alt-t'] = 'exec-and-forget open -a Terminal'  -- binds.lua:3"), true, additionalMsg: text)
            assertEquals(parts[1].contains("mode.main.binding['cmd-alt-shift-b'] = 'balance-sizes'  -- binds.lua:2"), true, additionalMsg: text)
        }

        /// The .luarc.json of the config folder, which points at the types of the app
        @Test func testTypes() throws {
            let types = folder.appending(path: "Inlay.app/Contents/Resources/types")
            try FileManager.default.createDirectory(at: types, withIntermediateDirectories: true)
            try "---@meta".write(to: types.appending(path: EditorTypes.fileName), atomically: true, encoding: .utf8)
            let config = folder.appending(path: "config")

            let written = EditorTypes.writeLuarc(typesFolder: types, configFolder: config)
            assertTrue((try? written.get())?.hasPrefix("Wrote ") == true)
            let luarc = try String(contentsOf: config.appending(path: ".luarc.json"), encoding: .utf8)
            assertEquals(luarc, EditorTypes.luarc(typesFolder: types))
            let json = try JSONSerialization.jsonObject(with: Data(luarc.utf8)) as? [String: Any]
            assertEquals(json?["workspace.library"] as? [String], [types.path])

            // One that exists is never overwritten
            try "{}".write(to: config.appending(path: ".luarc.json"), atomically: true, encoding: .utf8)
            assertTrue((try? EditorTypes.writeLuarc(typesFolder: types, configFolder: config).get())?.contains("is left as it is") == true)
            assertEquals(try String(contentsOf: config.appending(path: ".luarc.json"), encoding: .utf8), "{}")

            // Not the app: no types
            assertTrue(EditorTypes.writeLuarc(typesFolder: folder.appending(path: "nope"), configFolder: config).errorOrNil != nil)
        }
    }
}

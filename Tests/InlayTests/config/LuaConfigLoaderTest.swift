@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// Running inlay.lua, whose calls of inlay make the OrderedJson that the parsers read
    @Suite struct LuaConfigLoaderTest {
        /// The config folder, with inlay.lua and its modules
        private let dir: URL

        init() throws {
            dir = FileManager.default.temporaryDirectory.appending(path: "inlay-lua-config-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        private func write(_ text: String, _ name: String) throws {
            try Data(text.utf8).write(to: dir.appending(path: name))
        }

        private func load(_ text: String) -> LuaConfig { LuaConfigLoader.load(text) }

        private func messages(_ config: LuaConfig) -> [String] { config.errors.map { $0.description(.error) } }

        @Test func testScalarsAndTables() {
            let config = load("""
                inlay.config({
                  start_at_login = true,
                  gaps = { inner = { horizontal = 8 } },
                  split_ratio = 0.5,
                  duration = 300 / 2,
                  theme = 'hypr',
                  persistent_workspaces = { '1', '2', '3' },
                })
                """)
            assertEquals(config.errors, [])
            assertEquals(config.table, [
                "duration": .int(150),
                "gaps": .dict(["inner": .dict(["horizontal": .int(8)])]),
                "persistent_workspaces": .array([.string("1"), .string("2"), .string("3")]),
                "split_ratio": .double(0.5),
                "start_at_login": .bool(true),
                "theme": .string("hypr"),
            ])
            // The keys are sorted: the order of a Lua table is no order
            assertEquals(Array(config.table.keys), ["duration", "gaps", "persistent_workspaces", "split_ratio", "start_at_login", "theme"])
        }

        @Test func testEmptyTableIsATableOfKeys() {
            assertEquals(load("inlay.config({ after_startup_command = {} })").table, ["after_startup_command": .dict([:])])
            // A config without calls is an empty one
            assertEquals(load("-- nothing").table, [:])
            assertEquals(load("").errors, [])
        }

        @Test func testInvalidTables() {
            assertEquals(messages(load("inlay.config({ a = { 'x', y = 1 } })")), ["[ERROR] a: The table mixes keys and the items of an array"])
            assertEquals(messages(load("inlay.config({ a = { [1] = 'x', [3] = 'z' } })")),
                         ["[ERROR] a: The array has holes: its items must be 1, 2, 3… with no nil between them"])
            assertEquals(messages(load("inlay.config({ a = { [true] = 1 } })")),
                         ["[ERROR] a: A key is a boolean: keys are strings, or 1, 2, 3… in an array"])
            assertEquals(messages(load("inlay.config({ a = { 'x', print } })")), ["[ERROR] a[1]: Unsupported Lua type: function"])
            assertEquals(messages(load("local t = {}; t.self = t; inlay.config({ a = t })")), ["[ERROR] a.self: The table contains itself"])
            // An invalid value is left out: the rest of the config is kept
            assertEquals(load("inlay.config({ a = print, b = 1 })").table, ["b": .int(1)])
        }

        /// The format of before (a table that the file returns, put together with inlay.merge) says how to move on
        @Test func testTheOldFormatIsGone() {
            let returned = messages(load("return { gaps = 8 }"))
            assertEquals(returned.count, 1)
            assertTrue(returned[0].hasPrefix("[ERROR] inlay.lua returns a table: the config is no longer a table that it returns, but calls. Put the table in inlay.config({ … })"))
            assertEquals(messages(load("return 'gaps'")), ["[ERROR] inlay.lua returns a string: the config is the calls of inlay (inlay.config, inlay.bind…), and it returns nothing"])
            assertEquals(messages(load("local config = inlay.merge({}, {})")),
                         ["[ERROR] inlay.lua:1: inlay.merge is gone: require('name') runs name.lua, whose inlay.config, inlay.bind… calls are part of the config"])
            // A theme still returns its table
            assertEquals(LuaConfigLoader.load("return { borders = { width = 2 } }", kind: .table).table, ["borders": .dict(["width": .int(2)])])
            assertEquals(messages(LuaConfigLoader.load("local x = 1", kind: .table)), ["[ERROR] inlay.lua must return the table of the config. It returns: nil"])
            assertEquals(messages(LuaConfigLoader.load("return { 'a' }", kind: .table)), ["[ERROR] inlay.lua must return a table of keys, not an array"])
        }

        @Test func testErrorsHaveTheFileAndTheLine() {
            let syntax = load("inlay.config({\n  gaps = ,\n})")
            assertEquals(syntax.errors.map(\.preventConfigReload), [true])
            assertEquals(messages(syntax), ["[ERROR] inlay.lua:2: unexpected symbol near ','"])

            let runtime = load("local colors = nil\ninlay.config({ color = colors.primary })")
            assertEquals(messages(runtime), ["[ERROR] inlay.lua:2: attempt to index a nil value (local 'colors')"])
            assertEquals(runtime.table, [:])
        }

        @Test func testSandbox() {
            for global in ["os", "io", "debug", "package", "dofile", "loadfile"] {
                assertEquals(load("inlay.config({ x = type(\(global)) })").table, ["x": .string("nil")], additionalMsg: global)
            }
            assertEquals(load("inlay.config({ x = string.upper('a') .. math.floor(1.5) .. table.concat({ 'b' }) })").table, ["x": .string("A1b")])
            // load() only takes text: a precompiled chunk could break the state of Lua
            assertEquals(load("inlay.config({ x = select(2, load(string.dump(function() end))) })").table,
                         ["x": .string("attempt to load a binary chunk (mode is 't')")])
        }

        @Test func testEndlessLoopIsStopped() {
            assertEquals(messages(load("while true do end")), ["[ERROR] inlay.lua:1: the config runs for too long: is there an endless loop?"])
        }

        /// The functions of inlay make the same table of keys that the parsers read
        @Test func testFunctionsMakeTheTable() {
            let config = load("""
                inlay.config({ gaps = { inner = 8, outer = 8 }, theme = 'pills' })
                inlay.config({ gaps = { outer = 4 } })
                inlay.theme({ extends = 'nord' })
                inlay.workspace({ id = '1', key = 'h' })
                inlay.workspace({ id = '2', key = 'j' })
                inlay.bind('cmd-alt-h', 'focus left')
                inlay.bind('esc', { 'reload-config', 'mode main' }, { mode = 'service' })
                inlay.bind('cmd-alt-l', inlay.dsp.focus('right'))
                inlay.bind('cmd-alt-t', inlay.dsp.exec('open -a Terminal'))
                inlay.bind('cmd-alt-1', inlay.dsp.move_node_to_workspace(1))
                inlay.unbind('cmd-alt-shift-d')
                inlay.window_rule({ match = { app_id = 'a' }, run = 'layout floating' })
                inlay.window_rule('workspaces')
                inlay.on('start', 'exec-and-forget open -a Ghostty')
                inlay.on('start', { 'workspace 1' })
                inlay.on('focus_changed', {})
                inlay.on('workspace_changed', { '/bin/bash', '-c', 'true' })
                inlay.env('PATH', '/bin:${PATH}')
                inlay.curve('bounce', { 0.34, 1.56, 0.64, 1 })
                inlay.animation({ leaf = 'open', curve = 'quint', duration = 200 })
                inlay.animation({ leaf = 'global', duration = 160 })
                """)
            assertEquals(config.errors, [])
            // The same as the table of before
            let expected = LuaConfigLoader.load("""
                return {
                  gaps = { inner = 8, outer = 4 },
                  theme = { extends = 'nord' },
                  workspaces = { { id = '1', key = 'h' }, { id = '2', key = 'j' } },
                  mode = {
                    main = { binding = {
                      ['cmd-alt-h'] = 'focus left',
                      ['cmd-alt-l'] = 'focus right',
                      ['cmd-alt-t'] = 'exec-and-forget open -a Terminal',
                      ['cmd-alt-1'] = 'move-node-to-workspace 1',
                      ['cmd-alt-shift-d'] = false,
                    } },
                    service = { binding = { esc = { 'reload-config', 'mode main' } } },
                  },
                  on_window_detected = { { match = { app_id = 'a' }, run = 'layout floating' }, 'workspaces' },
                  after_startup_command = { 'exec-and-forget open -a Ghostty', 'workspace 1' },
                  on_focus_changed = {},
                  exec_on_workspace_change = { '/bin/bash', '-c', 'true' },
                  exec = { env_vars = { PATH = '/bin:${PATH}' } },
                  animations = { duration = 160, curves = { bounce = { 0.34, 1.56, 0.64, 1 } }, open = { curve = 'quint', duration = 200 } },
                }
                """, kind: .table).table
            assertEquals(config.table, expected)
        }

        @Test func testFunctionErrors() {
            assertEquals(messages(load("inlay.config({ 'a' })")), ["[ERROR] inlay.lua:1: inlay.config: it takes a table of keys, like { gaps = { inner = 8 } }"])
            assertEquals(messages(load("inlay.config({ a = { 1 } })\ninlay.config({ a = { b = 1 } })")),
                         ["[ERROR] inlay.lua:2: inlay.config: 'a' is an array in one table and a table of keys in another"])
            assertEquals(messages(load("inlay.bind('cmd-alt-h', 3)")), ["[ERROR] inlay.lua:1: inlay.bind: the command is a string, or a list of them"])
            assertEquals(messages(load("inlay.bind('cmd-alt-h', 'close', { mod = 'service' })")), ["[ERROR] inlay.lua:1: inlay.bind: 'mod' isn't an option"])
            assertEquals(messages(load("inlay.on('started', 'close')")),
                         ["[ERROR] inlay.lua:1: inlay.on: 'started' isn't an event: start, focus_changed, monitor_changed, mode_changed or workspace_changed"])
            assertEquals(messages(load("\ninlay.window_rule(1)")),
                         ["[ERROR] inlay.lua:2: inlay.window_rule: it takes a table, { match = { app_id = '…' }, run = 'layout floating' }, or 'workspaces'"])
        }

        /// Where each value was set: the file and the line of the call
        @Test func testOrigins() throws {
            try write("inlay.bind('cmd-alt-h', 'focus left')\n\ninlay.window_rule({ run = 'layout floating' })", "binds.lua")
            try write("require('binds')\ninlay.config({\n  gaps = { inner = 8 },\n})\ninlay.workspace({ id = '1' })", "inlay.lua")
            let config = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(config.errors, [])
            assertEquals(config.origins[["mode", "main", "binding", "cmd-alt-h"]], "binds.lua:1")
            assertEquals(config.origins[["on_window_detected"]], "binds.lua:3")
            assertEquals(config.origins[["on_window_detected", "1"]], "binds.lua:3")
            assertEquals(config.origins[["gaps", "inner"]], "inlay.lua:2")
            assertEquals(config.origins[["workspaces", "1"]], "inlay.lua:5")
        }

        @Test func testRequire() throws {
            try write("return { primary = '#B59DF7' }", "colors.lua")
            try write("local c = require('colors')\ninlay.config({ borders = { active_color = c.primary } })", "borders.lua")
            try FileManager.default.createDirectory(at: dir.appending(path: "conf"), withIntermediateDirectories: true)
            try write("inlay.config({ menu_bar = { colors = { focused = require('colors').primary } } })", "conf/menubar.lua")
            let main = "require('borders')\nrequire('conf.menubar')"
            try write(main, "inlay.lua")

            let config = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(config.errors, [])
            assertEquals(config.table, [
                "borders": .dict(["active_color": .string("#B59DF7")]),
                "menu_bar": .dict(["colors": .dict(["focused": .string("#B59DF7")])]),
            ])
            // Every file, once, in the order of the first require
            assertEquals(config.files.map { $0.url?.path.replacingOccurrences(of: dir.path + "/", with: "") }, [
                "inlay.lua", "borders.lua", "colors.lua", "conf/menubar.lua",
            ])
            assertEquals(config.files.first?.text, main)
        }

        @Test func testRequireErrors() throws {
            try write("require('bindz')", "inlay.lua")
            let missing = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(missing.errors.count, 1)
            #expect(messages(missing)[0].hasPrefix("[ERROR] inlay.lua:1: require: there is no bindz.lua in "))
            // Creating it must reload the config
            assertEquals(missing.files.map { $0.url?.lastPathComponent }, ["inlay.lua", "bindz.lua"])
            assertNil(missing.files.last?.text)

            for name in ["../secret", "a..b", ".a"] {
                try write("require('\(name)')", "inlay.lua")
                assertEquals(messages(LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))),
                             ["[ERROR] inlay.lua:1: require: '\(name)' isn't a file of the config folder: write its name without .lua (a.b for a/b.lua)"])
            }

            try write("return require('b')", "a.lua")
            try write("return require('a')", "b.lua")
            try write("require('a')", "inlay.lua")
            // return require(…) is a tail call: Lua forgets its line, the file is known
            assertEquals(messages(LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))), ["[ERROR] b.lua: require: a.lua requires itself"])

            // The module with the error is among the files: saving it again must reload the config
            try write("inlay.config({\n  gaps = ,\n})", "layout.lua")
            try write("require('layout')", "inlay.lua")
            let broken = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(messages(broken), ["[ERROR] layout.lua:2: unexpected symbol near ','"])
            assertEquals(broken.files.map { $0.url?.lastPathComponent }, ["inlay.lua", "layout.lua"])

            assertEquals(messages(load("local colors = require('colors')")), ["[ERROR] inlay.lua:1: require: this config has no folder"])
        }
    }
}

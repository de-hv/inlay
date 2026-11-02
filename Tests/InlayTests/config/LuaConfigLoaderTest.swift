@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// Running inlay.lua and turning what it returns into the OrderedJson that the parsers read
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
                return {
                  startAtLogin = true,
                  gaps = { inner = { horizontal = 8 } },
                  splitRatio = 0.5,
                  duration = 300 / 2,
                  theme = 'hypr',
                  persistentWorkspaces = { '1', '2', '3' },
                }
                """)
            assertEquals(config.errors, [])
            assertEquals(config.table, [
                "duration": .int(150),
                "gaps": .dict(["inner": .dict(["horizontal": .int(8)])]),
                "persistentWorkspaces": .array([.string("1"), .string("2"), .string("3")]),
                "splitRatio": .double(0.5),
                "startAtLogin": .bool(true),
                "theme": .string("hypr"),
            ])
            // The keys are sorted, like the ones of the TOML config
            assertEquals(Array(config.table.keys), ["duration", "gaps", "persistentWorkspaces", "splitRatio", "startAtLogin", "theme"])
        }

        @Test func testEmptyTableIsATableOfKeys() {
            assertEquals(load("return { afterStartupCommand = {} }").table, ["afterStartupCommand": .dict([:])])
        }

        @Test func testInvalidTables() {
            assertEquals(messages(load("return { a = { 'x', y = 1 } }")), ["[ERROR] a: The table mixes keys and the items of an array"])
            assertEquals(messages(load("return { a = { [1] = 'x', [3] = 'z' } }")),
                         ["[ERROR] a: The array has holes: its items must be 1, 2, 3… with no nil between them"])
            assertEquals(messages(load("return { a = { [true] = 1 } }")),
                         ["[ERROR] a: A key is a boolean: keys are strings, or 1, 2, 3… in an array"])
            assertEquals(messages(load("return { a = { 'x', print } }")), ["[ERROR] a[1]: Unsupported Lua type: function"])
            assertEquals(messages(load("local t = {}; t.self = t; return { a = t }")), ["[ERROR] a.self: The table contains itself"])
            // An invalid value is left out: the rest of the config is kept
            assertEquals(load("return { a = print, b = 1 }").table, ["b": .int(1)])
        }

        @Test func testItMustReturnATableOfKeys() {
            assertEquals(messages(load("local x = 1")), ["[ERROR] inlay.lua must return the table of the config. It returns: nil"])
            assertEquals(messages(load("return 'gaps'")), ["[ERROR] inlay.lua must return the table of the config. It returns: string"])
            assertEquals(messages(load("return { 'a' }")), ["[ERROR] inlay.lua must return a table of keys, not an array"])
        }

        @Test func testErrorsHaveTheFileAndTheLine() {
            let syntax = load("return {\n  gaps = ,\n}")
            assertEquals(syntax.errors.map(\.preventConfigReload), [true])
            assertEquals(messages(syntax), ["[ERROR] inlay.lua:2: unexpected symbol near ','"])

            let runtime = load("local colors = nil\nreturn { color = colors.primary }")
            assertEquals(messages(runtime), ["[ERROR] inlay.lua:2: attempt to index a nil value (local 'colors')"])
            assertEquals(runtime.table, [:])
        }

        @Test func testSandbox() {
            for global in ["os", "io", "debug", "package", "dofile", "loadfile"] {
                assertEquals(load("return { x = type(\(global)) }").table, ["x": .string("nil")], additionalMsg: global)
            }
            assertEquals(load("return { x = string.upper('a') .. math.floor(1.5) .. table.concat({ 'b' }) }").table, ["x": .string("A1b")])
            // load() only takes text: a precompiled chunk could break the state of Lua
            assertEquals(load("return { x = select(2, load(string.dump(function() end))) }").table,
                         ["x": .string("attempt to load a binary chunk (mode is 't')")])
        }

        @Test func testEndlessLoopIsStopped() {
            assertEquals(messages(load("while true do end")), ["[ERROR] inlay.lua:1: the config runs for too long: is there an endless loop?"])
        }

        @Test func testRequire() throws {
            try write("return { primary = '#B59DF7' }", "colors.lua")
            try write("local c = require('colors')\nreturn { borders = { activeColor = c.primary } }", "borders.lua")
            try write("return { menuBar = { colors = { focused = require('colors').primary } } }", "menubar.lua")
            let main = "return inlay.merge(require('borders'), require('menubar'))"
            try write(main, "inlay.lua")

            let config = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(config.errors, [])
            assertEquals(config.table, [
                "borders": .dict(["activeColor": .string("#B59DF7")]),
                "menuBar": .dict(["colors": .dict(["focused": .string("#B59DF7")])]),
            ])
            // Every file, once, in the order of the first require
            assertEquals(config.files.map { $0.url?.lastPathComponent }, ["inlay.lua", "borders.lua", "colors.lua", "menubar.lua"])
            assertEquals(config.files.first?.text, main)
        }

        @Test func testRequireErrors() throws {
            try write("return { binds = require('bindz') }", "inlay.lua")
            let missing = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(missing.errors.count, 1)
            #expect(messages(missing)[0].hasPrefix("[ERROR] inlay.lua:1: require: there is no bindz.lua in "))

            try write("return { binds = require('../secret') }", "inlay.lua")
            assertEquals(messages(LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))),
                         ["[ERROR] inlay.lua:1: require: '../secret' isn't a file of the config folder: write its name without .lua"])

            try write("return require('b')", "a.lua")
            try write("return require('a')", "b.lua")
            try write("return require('a')", "inlay.lua")
            // return require(…) is a tail call: Lua forgets its line, the file is known
            assertEquals(messages(LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))), ["[ERROR] b.lua: require: a.lua requires itself"])

            // The module with the error is among the files: saving it again must reload the config
            try write("return {\n  gaps = ,\n}", "layout.lua")
            try write("return require('layout')", "inlay.lua")
            let broken = LuaConfigLoader.load(file: dir.appending(path: "inlay.lua"))
            assertEquals(messages(broken), ["[ERROR] layout.lua:2: unexpected symbol near ','"])
            assertEquals(broken.files.map { $0.url?.lastPathComponent }, ["inlay.lua", "layout.lua"])

            assertEquals(messages(load("local colors = require('colors')")), ["[ERROR] inlay.lua:1: require: this config has no folder"])
        }

        @Test func testMerge() {
            let config = load("""
                local rules = { onWindowDetected = { { run = 'a' } } }
                local merged = inlay.merge(
                  { gaps = { inner = 8, outer = 8 }, onWindowDetected = { { run = 'first' } }, theme = 'pills' },
                  { gaps = { outer = 4 }, theme = 'hypr', afterStartupCommand = {} },
                  rules,
                  rules
                )
                return { merged = merged, untouched = #rules.onWindowDetected }
                """)
            assertEquals(config.errors, [])
            assertEquals(config.table, [
                "merged": .dict([
                    "afterStartupCommand": .dict([:]),
                    "gaps": .dict(["inner": .int(8), "outer": .int(4)]),
                    "onWindowDetected": .array([
                        .dict(["run": .string("first")]), .dict(["run": .string("a")]), .dict(["run": .string("a")]),
                    ]),
                    "theme": .string("hypr"),
                ]),
                // merge copies: the tables of the modules stay as they are
                "untouched": .int(1),
            ])

            assertEquals(messages(load("local config = inlay.merge({ a = { 1 } }, { a = { b = 1 } })")),
                         ["[ERROR] inlay.lua:1: inlay.merge: 'a' is an array in one table and a table of keys in another"])
            // A tail call, like most configs end
            assertEquals(messages(load("\nreturn inlay.merge({}, nil)")), ["[ERROR] inlay.lua: inlay.merge: argument 2 is a nil, not a table"])
        }
    }
}

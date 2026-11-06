@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// The config of the user over the built-in config, and 'workspaces'. See: mergedConfig, expandWorkspaces
    @Suite @MainActor struct ConfigLayersTest {
        init() { setUpWorkspacesForTests() }

        private func parse(_ text: String) -> ParseConfigResult {
            parseConfigOverBuiltIn(LuaConfigLoader.load(text))
        }

        private func binding(_ config: Config, _ key: String, mode: String = mainModeId) -> String? {
            config.modes[mode]?.bindings.values.first { $0.descriptionWithKeyNotation == key }?.commands.shellOfCommandsDescription
        }

        /// An empty config of the user is the built-in config
        @Test func testEmptyConfigIsTheBuiltInOne() {
            let result = parse("inlay.config({})")
            assertEquals(result.strErrors, [])
            assertEquals(result.strWarnings, [])
            assertEquals(result.config.persistentWorkspaces, defaultConfig.persistentWorkspaces)
            assertEquals(result.config.gaps, defaultConfig.gaps)
            assertEquals(result.config.onWindowDetected.count, defaultConfig.onWindowDetected.count)
            assertEquals(binding(result.config, "cmd-alt-ctrl-h"), "workspace 1; mode main")
        }

        /// A table is merged key by key; a value replaces the one of the built-in config
        @Test func testTablesAreMergedKeyByKey() {
            let result = parse("inlay.config({ menu_bar = { per_monitor = true }, gaps = { inner = { horizontal = 12 } }, tiling = { split_ratio = 0.6 } })")
            assertEquals(result.strErrors, [])
            assertEquals(result.config.menuBar.perMonitor, true)
            assertEquals(result.config.menuBar.theme, .hypr) // Of the built-in config
            assertEquals(result.config.tiling.splitRatio, 0.6)
            assertEquals(result.config.tiling.startupLayout, .dwindle) // Of the built-in config
            assertEquals(result.config.gaps.inner.horizontal, .constant(12))
            assertEquals(result.config.gaps.inner.vertical, .constant(8)) // Of the built-in config
        }

        /// A list replaces the one of the built-in config, and so does 'theme'
        @Test func testListsAndThemeReplace() {
            let result = parse("inlay.config({ after_startup_command = { 'balance-sizes' }, theme = 'nord' })")
            assertEquals(result.strErrors, [])
            assertEquals(result.config.afterStartupCommand.flatten().count, 1)
            assertEquals("\(result.config.borders.activeColor)", "#88C0D0")
        }

        /// A binding set to false removes the one of the built-in config; others are added or replaced
        @Test func testBindings() {
            let result = parse("""
                inlay.config({ mode = { main = { binding = {
                  ['cmd-alt-shift-b'] = false,
                  ['cmd-alt-shift-d'] = 'arrange-workspace grid',
                  ['cmd-alt-t'] = 'balance-sizes',
                } } } })
                """)
            assertEquals(result.strErrors, [])
            assertEquals(binding(result.config, "cmd-alt-shift-b"), nil)
            assertEquals(binding(result.config, "cmd-alt-shift-d"), "arrange-workspace grid")
            assertEquals(binding(result.config, "cmd-alt-t"), "balance-sizes")
            assertEquals(binding(result.config, "cmd-alt-left"), "focus left") // Of the built-in config
            assertEquals(binding(result.config, "esc", mode: "service"), "reload-config; mode main")
        }

        /// The rules of the user go first; the ones of the apps of the workspaces after the file dialogs
        @Test func testRulesOrder() {
            let result = parse("""
                inlay.config({
                  workspaces = { { id = 'a', key = 'q', apps = { 'com.example.app' } } },
                  on_window_detected = { { match = { app_id = 'com.example.mine' }, run = 'layout floating' } },
                })
                """)
            assertEquals(result.strErrors, [])
            let appIds = result.config.onWindowDetected.map { rule -> String in
                guard case .legacy(let matcher) = rule.matcher else { return "command" }
                return matcher.appId ?? (matcher.windowTitleRegexSubstring != nil ? "title" : "?")
            }
            assertEquals(Array(appIds.prefix(3)), ["com.example.mine", "title", "com.example.app"])
            assertEquals(appIds.last, "command") // The catch-all rule of the built-in config
            // '{}' adds no rules
            assertEquals(parse("inlay.config({ on_window_detected = {} })").config.onWindowDetected.count, defaultConfig.onWindowDetected.count)
        }

        /// 'workspaces' of the user replace the 7 of the built-in config, and make their keys
        @Test func testWorkspaces() {
            let result = parse("""
                inlay.config({
                  workspaces = {
                    { id = 'web', name = 'Browsers', key = 'w', monitor = 'secondary', apps = { 'com.google.Chrome' } },
                    { id = 'mail' },
                  },
                  workspace_keys = { move = false },
                })
                """)
            assertEquals(result.strErrors, [])
            assertEquals(Array(result.config.persistentWorkspaces), ["web", "mail"])
            assertEquals(result.config.workspaceNames, ["web": "Browsers"])
            assertEquals(result.config.workspaceToMonitorForceAssignment.keys.sorted(), ["mail", "web"])
            assertEquals(binding(result.config, "cmd-alt-ctrl-w"), "workspace web; mode main")
            assertEquals(binding(result.config, "cmd-alt-shift-w"), nil) // move = false
            // The 7 of the built-in config are gone, with their keys
            assertEquals(binding(result.config, "cmd-alt-ctrl-h"), nil)
            assertEquals(binding(result.config, "cmd-alt-shift-h"), nil)
            assertEquals(result.config.onWindowDetected.contains { rule in
                if case .legacy(let matcher) = rule.matcher { return matcher.appId == "com.google.Chrome" }
                return false
            }, true)
        }

        @Test func testWorkspacesErrors() {
            assertEquals(parse("inlay.config({ workspaces = { { name = 'x' } } })").strErrors, ["[ERROR] workspaces[0]: A workspace needs an 'id': its name in the commands, like 'workspace 1'"])
            assertEquals(parse("inlay.config({ workspaces = { { id = '1' }, { id = '1' } } })").strErrors, ["[ERROR] workspaces[1].id: The workspace '1' is already in the list"])
            assertEquals(parse("inlay.config({ workspaces = { { id = '1', color = 'red' } } })").strErrors, ["[ERROR] workspaces[0].color: Unknown key"])
            assertEquals(parse("inlay.config({ workspace_keys = { focus = 1 } })").strErrors, ["[ERROR] workspace_keys.focus: Expected the modifiers of the keys, like 'cmd-alt-ctrl', or false: no key bindings"])
        }

        /// builtInConfig = false: the config of the user alone, over the defaults of the code
        @Test func testWithoutTheBuiltInConfig() {
            let result = parse("inlay.config({ built_in_config = false, persistent_workspaces = { 'a' } })")
            assertEquals(result.strErrors, [])
            assertEquals(Array(result.config.persistentWorkspaces), ["a"])
            assertEquals(result.config.modes, Config().modes)
            assertEquals(result.config.onWindowDetected.count, 0)
            assertEquals(parse("inlay.config({ built_in_config = 'no' })").strErrors, ["[ERROR] built_in_config: Expected type is 'Bool'. But actual type is 'String'"])
        }

        /// The errors point at the keys of the user
        @Test func testErrorsOfTheUser() {
            assertEquals(parse("inlay.config({ borders = { width = 99 } })").strErrors, ["[ERROR] borders.width: width must be in [1, 20] range"])
        }

        /// The file of types for the editors has every key of the parser
        @Test func testTypes() throws {
            let reference = ConfigReference(try String(contentsOf: projectRoot.appending(path: "docs/config-reference.lua"), encoding: .utf8))
            let types = EditorTypes.generate(reference)
            assertTrue(types.hasPrefix("---@meta"))
            for key in configParser.keys where !["notifications", "settings"].contains(key) {
                assertEquals(types.contains("InlayConfig.\(key) = nil") || types.contains("InlayConfig['\(key)'] = nil"), true, additionalMsg: key)
            }
            for key in bordersParserTable.keys where key != "hide_when_single" {
                assertEquals(types.contains("InlayConfig_borders.\(key) = nil"), true, additionalMsg: key)
            }
            assertTrue(types.contains("---@type boolean?\nInlayConfig_menu_bar.per_monitor = nil"))
            assertTrue(types.contains("---@type 'pills'|'chips'|'hypr'|'minimal'|'dots'|'underline'|'liquid'|'dms'?\nInlayConfig_menu_bar.theme = nil"))
            assertTrue(types.contains("---@type integer?\nInlayConfig_borders.width = nil"))
            assertTrue(types.contains("---@class InlayConfig.workspaces"))
            assertTrue(types.contains("function inlay.bind(keys, command, options) end"))
            assertTrue(types.contains("function inlay.window_rule(rule) end"))
            assertTrue(types.contains("---@field move_node_to_workspace fun(...: any): string 'move-node-to-workspace …'"))
            assertTrue(types.contains("---@field exec fun(...: any): string 'exec-and-forget …'"))
            assertEquals(types.contains("inlay.merge"), false)
            // The text of the reference is the documentation of the key
            assertTrue(types.contains("--- Group the workspaces by monitor"))
            // Nothing of the examples of the tables with names of the user
            assertEquals(types.contains("alt-slash"), false)
        }
    }
}

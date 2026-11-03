@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// docs/config-reference.toml documents every key of the config, and 'inlay config --explain' prints its parts
    @Suite @MainActor struct ConfigReferenceTest {
        init() { setUpWorkspacesForTests() }

        private var reference: ConfigReference {
            get throws { ConfigReference(try String(contentsOf: projectRoot.appending(path: "docs/config-reference.toml"), encoding: .utf8)) }
        }

        /// The tables of the parser, by the path of the table in the config. "" is the root table
        private var parserTables: [(path: String, keys: [String])] {
            [
                ("", Array(configParser.keys)),
                ("gaps", Array(gapsParser.keys)),
                ("gaps.inner", Array(gapsInnerParser.keys)),
                ("gaps.outer", Array(gapsOuterParser.keys)),
                ("exec", Array(rawExecConfigParser.keys)),
                ("focusFollowsMouse", Array(focusFollowsMouseParserTable.keys)),
                ("keyMapping", Array(keyMappingParser.keys)),
                ("tiling", Array(tilingParserTable.keys)),
                ("menuBar", Array(menuBarParserTable.keys)),
                ("menuBar.colors", Array(menuBarColorsParserTable.keys)),
                ("borders", Array(bordersParserTable.keys)),
                ("borders.singleWindow", Array(singleWindowBorderParserTable.keys)),
                ("animations", Array(animationsParserTable.keys)),
                ("onWindowDetected", Array(windowDetectedParser.keys)),
                ("onWindowDetected.match", Array(windowDetectedMatcherParser.keys)),
                ("mode.*", ["binding"]), // See: parseMode
            ]
        }

        /// The tables whose keys are names that the user chooses: binding modes, key bindings, variables, workspaces
        private let freeFormTables = [
            "mode", "mode.*.binding", "borders.modeColors", "exec.envVars",
            "keyMapping.keyNotationToKeyCode", "workspaceToMonitorForceAssignment",
            "animations.curves",
        ]

        /// 'mode.main.binding.alt-h' -> 'mode.*.binding.*'. nil: the name itself, in a free-form table (not a key of the parser)
        private func generalized(_ path: String) -> String {
            var result: [String] = []
            for component in path.split(separator: ".").map(String.init) {
                result.append(freeFormTables.contains(result.joined(separator: ".")) ? "*" : component)
            }
            return result.joined(separator: ".")
        }

        private var acceptedKeys: Set<String> {
            parserTables.flatMap { table in table.keys.map { table.path.isEmpty ? $0 : table.path + "." + $0 } }.toSet()
        }

        @Test func testTheReferenceIsAValidConfig() throws {
            let result = parseConfig(try reference.text)
            assertEquals(result.strErrors, [])
            assertEquals(result.strWarnings, [])
            // The values that it spells out are the defaults of the code
            assertEquals(result.config.tiling, TilingConfig())
            assertEquals(result.config.menuBar, MenuBarConfig())
            assertEquals(result.config.borders.copy(\.modeColors, [:]), BordersConfig())
            assertEquals(result.config.animations, AnimationsConfig())
            assertEquals(result.config.gaps, Config().gaps)
            assertEquals(result.config.execConfig, Config().execConfig)
            assertEquals(result.config.startAtLogin, Config().startAtLogin)
            assertEquals(result.config.autoReloadConfig, Config().autoReloadConfig)
            assertEquals(result.config.defaultRootContainerOrientation, Config().defaultRootContainerOrientation)
            assertEquals(result.config.focusFollowsMouse.enabled, Config().focusFollowsMouse.enabled)
        }

        /// A key that the parser accepts and the reference doesn't document
        @Test func testEveryKeyOfTheParserIsDocumented() throws {
            let documented = try reference.documentedKeys.map(generalized).toSet()
            func isDocumented(_ key: String) -> Bool { documented.contains { $0 == key || $0.hasPrefix(key + ".") } }
            assertEquals(acceptedKeys.filter { !isDocumented($0) }.sorted(), [])
        }

        /// A key that the reference documents and the parser doesn't accept: a typo, or a key that was removed
        @Test func testEveryDocumentedKeyIsAKeyOfTheParser() throws {
            let accepted = acceptedKeys
            func isAccepted(_ key: String) -> Bool {
                key.hasSuffix(".*") || freeFormTables.contains(key) || accepted.contains { $0 == key || $0.hasPrefix(key + ".") }
            }
            assertEquals(try reference.documentedKeys.map(generalized).filter { !isAccepted($0) }.sorted(), [])
        }

        /// The test above is only as good as the list of tables of this file
        @Test func testAnUndocumentedKeyIsFound() throws {
            let text = try reference.text
            let withoutWidth = ConfigReference(text.replacing("\n    width = 4\n", with: "\n"))
            assertEquals(withoutWidth.documentedKeys.contains("borders.width"), false)
            assertEquals(try reference.documentedKeys.contains("borders.width"), true)
            let withTypo = ConfigReference(text.replacing("\n    width = 4\n", with: "\n    widht = 4\n"))
            assertEquals(withTypo.documentedKeys.contains("borders.widht"), true)
            assertEquals(acceptedKeys.contains("borders.widht"), false)
        }

        @Test func testDocumentedKeys() throws {
            let keys = try reference.documentedKeys
            for key in [
                "configVersion", "focusFollowsMouse.enabled", "keyMapping.keyNotationToKeyCode", "accordionPadding",
                "afterLoginCommand", "gaps", "gaps.inner.horizontal", "exec.envVars", "tiling.splitTarget", "menuBar.colors",
                "menuBar.colors.accent", "borders.modeColors", "mode.main.binding", "mode.main.binding.alt-h",
                "onWindowDetected", "onWindowDetected.match.appId", "onWindowDetected.run",
                "workspaceToMonitorForceAssignment",
            ] {
                assertEquals(keys.contains(key), true, additionalMsg: key)
            }
            assertEquals(keys.count, keys.toSet().count)
        }

        @Test func testExplainEverything() throws {
            assertEquals(try reference.explain(nil).get() + "\n", try reference.text)
        }

        @Test func testExplainKey() throws {
            assertEquals(
                try reference.explain("borders.width").get(),
                """
                [borders]

                    # The thickness of the border, in points. The border is drawn outside of the frame of the window:
                    # it never covers the content of the window, it takes a part of the gap. See [gaps]
                    # Possible values: 1 ... 20
                    # Fallback value (if you omit the key): width = 4
                    width = 4
                """,
            )
            // A key of the root table has no header
            assertEquals(
                try reference.explain("startAtLogin").get(),
                """
                # Start Inlay at login. Inlay adds itself to the login items of macOS, or removes itself from them,
                # every time the config is loaded
                # Possible values: true|false
                # Fallback value (if you omit the key): startAtLogin = false
                startAtLogin = false
                """,
            )
            // A key that is only documented, commented out
            let accordion = try reference.explain("accordionPadding").get()
            assertEquals(accordion.hasPrefix("# Not a key of Inlay: it has no accordion layout."), true)
            assertEquals(accordion.hasSuffix("# accordionPadding = 30"), true)
        }

        @Test func testExplainTable() throws {
            let tiling = try reference.explain("tiling").get()
            assertEquals(tiling.hasPrefix("# Where the tiling windows are placed\n[tiling]\n"), true)
            assertEquals(tiling.hasSuffix("    minWindowSize = 100"), true)
            assertEquals(tiling.contains("[menuBar]"), false)

            // A table with its subtables
            let menuBar = try reference.explain("menuBar").get()
            assertEquals(menuBar.contains("[menuBar]\n"), true)
            assertEquals(menuBar.contains("[menuBar.colors]\n"), true)
            assertEquals(menuBar.hasSuffix("        empty = 'auto'"), true)

            // Dotted keys inside a table, and a prefix of them
            let gaps = try reference.explain("gaps").get()
            assertEquals(gaps.contains("inner.horizontal = 0") && gaps.contains("outer.right = 0"), true)
            let inner = try reference.explain("gaps.inner").get()
            assertEquals(inner.hasPrefix("[gaps]\n"), true)
            assertEquals(inner.contains("inner.horizontal = 0") && inner.contains("inner.vertical = 0"), true)
            assertEquals(inner.contains("outer"), false)

            // Every table of a group, and every rule
            let modes = try reference.explain("mode").get()
            assertEquals(modes.contains("[mode.main.binding]") && modes.contains("[mode.service.binding]"), true)
            let rules = try reference.explain("onWindowDetected").get()
            assertEquals(rules.split(separator: "\n").filter { $0 == "[[onWindowDetected]]" }.count, 3)
            assertEquals(try reference.explain("onWindowDetected.match.appId").get().hasPrefix("[[onWindowDetected]]\n"), true)
            assertEquals(try reference.explain(".borders.").get(), try reference.explain("borders").get())
        }

        @Test func testExplainUnknownKey() throws {
            assertEquals(
                try reference.explain("glow").errorOrNil,
                "The config reference has no key or table 'glow'. Did you mean: borders.glow, borders.glowRadius",
            )
            assertEquals(
                try reference.explain("nope").errorOrNil,
                "The config reference has no key or table 'nope'. 'config --explain' without a key prints the whole reference",
            )
        }

        @Test func testParseArgs() {
            assertEquals((parseCmdArgs(["config", "--explain"]).cmdOrNil as? ConfigCmdArgs)?.explain, .everything)
            assertEquals((parseCmdArgs(["config", "--explain", "borders.width"]).cmdOrNil as? ConfigCmdArgs)?.explain, .key("borders.width"))
            assertEquals(parseCommand("config --explain --all-keys").errorOrNil?.hasPrefix("Conflicting flags are specified:"), true)
            assertEquals(parseCommand("config --explain tiling --json").errorOrNil, "--json flag requires --get flag")
        }

        /// The server answers it too (a binding may run it), from the same file
        @Test func testCommand() async throws {
            let result = await parseCommand("config --explain tiling.splitRatio").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0)
            assertEquals(result.stdout.joined(separator: "\n"), try reference.explain("tiling.splitRatio").get())
            let unknown = await parseCommand("config --explain nope").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(unknown.exitCode.rawValue != 0, true)
            assertEquals(unknown.stderr.joined(separator: "\n").contains("no key or table 'nope'"), true)
        }
    }
}

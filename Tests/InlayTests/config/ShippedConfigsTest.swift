@testable import AppBundle
import Common
import CryptoKit
import Foundation
import Testing

extension InlayTests {
    /// The configs that ship with Inlay, and the commented example of the design documentation
    /// (Tests/InlayTests/fixtures/inlay-example.toml), must load with the real parser without errors or warnings
    @Suite @MainActor struct ShippedConfigsTest {
        init() { setUpWorkspacesForTests() }

        private func parse(_ relativePath: String) throws -> (config: Config, errors: [String], warnings: [String]) {
            let text = try String(contentsOf: projectRoot.appending(path: relativePath), encoding: .utf8)
            let result = parseConfig(text)
            return (result.config, result.strErrors, result.strWarnings)
        }

        /// inlay.toml, at the root of the repo: the config that install.sh copies and that the app bundle carries
        @Test func testBuiltInConfig() throws {
            let result = try parse("inlay.toml")
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            // The tables of Inlay are spelled out with the defaults of the code
            assertEquals(result.config.tiling, TilingConfig())
            assertEquals(result.config.menuBar, MenuBarConfig())
            assertEquals(result.config.borders, BordersConfig())
            // A single window takes the whole screen, without a border
            assertEquals(result.config.gaps.smart, true)
            // Saving the file by hand reloads it, which is what keeps the settings window in sync with it
            assertEquals(result.config.autoReloadConfig, true)
            // It is the config that the app falls back to
            assertEquals(defaultConfigUrl.lastPathComponent, "inlay.toml")
            assertEquals(try String(contentsOf: defaultConfigUrl, encoding: .utf8), try String(contentsOf: projectRoot.appending(path: "inlay.toml"), encoding: .utf8))
        }

        /// install.sh replaces a config that is identical to a default config that Inlay has shipped, and only such
        /// a config. The list of their hashes must have the inlay.toml of right now: otherwise the config that
        /// this version installs would be taken for the user's own by the next one, and never updated.
        /// It fails after a change in inlay.toml until scripts/update-default-config-hashes.sh is run
        @Test func testBuiltInConfig_isInTheListOfDefaultConfigs() throws {
            let list = try String(contentsOf: projectRoot.appending(path: "scripts/default-config-hashes.txt"), encoding: .utf8)
            let entries = list.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { $0.components(separatedBy: "  ") }
            // "<sha256>  <the file it was>", the format that install.sh looks for
            for entry in entries {
                assertEquals(entry.count, 2, additionalMsg: "\(entry)")
                assertEquals(entry[0].count, 64, additionalMsg: "\(entry)")
                assertEquals(entry[0].allSatisfy { $0.isHexDigit && !$0.isUppercase }, true, additionalMsg: "\(entry)")
            }
            let hashes = entries.map { $0[0] }
            assertEquals(hashes.count, Set(hashes).count)
            let current = SHA256.hash(data: try Data(contentsOf: projectRoot.appending(path: "inlay.toml"))).map { String(format: "%02x", $0) }.joined()
            assertEquals(hashes.contains(current), true, additionalMsg: "inlay.toml has changed: run scripts/update-default-config-hashes.sh and commit the result")
            assertEquals(entries.last, [current, "inlay.toml"])
            // The default configs of the versions before inlay.toml: the config of AeroSpace, without any rule.
            // It is the one that the first installations got
            assertEquals(entries.filter { $0[1] == "docs/config-examples/default-config.toml" }.count, 11)
            assertTrue(hashes.contains("40f8d6dea755c66aeacf63e7a8d74a033b1804373b4935cd3c2fe53b014cdd76"))
        }

        /// What the built-in config gives to somebody who installs Inlay without a config of their own
        @Test func testBuiltInConfig_workspacesAndBindings() throws {
            let config = try parse("inlay.toml").config
            assertEquals(Array(config.persistentWorkspaces), ["1", "2", "3", "4", "5", "6", "7"])
            assertEquals(config.modes.keys.sorted(), ["main", "resize", "service"])
            func runs(_ binding: String, _ command: String, mode: String = mainModeId) -> Bool {
                let bound = config.modes[mode]?.bindings.values.first { $0.descriptionWithKeyNotation == binding }
                return bound?.commands.strictEquals(parseCommand(command).cmdOrDie) == true
            }
            for (key, workspace) in zip(["j", "k", "l", "i", "o", "p", "7"], 1 ... 7) {
                assertEquals(runs("cmd-alt-ctrl-\(key)", "workspace \(workspace); mode main"), true, additionalMsg: key)
                // The window also stops floating: the windows of the apps without a workspace open floating
                assertEquals(runs("cmd-alt-shift-\(key)", "layout tiling; move-node-to-workspace \(workspace)"), true, additionalMsg: key)
            }
            for direction in ["left", "down", "up", "right"] {
                assertEquals(runs("cmd-alt-\(direction)", "focus \(direction)"), true, additionalMsg: direction)
                // swap keeps the shape of the layout, move changes it
                assertEquals(runs("cmd-alt-ctrl-\(direction)", "swap \(direction)"), true, additionalMsg: direction)
                assertEquals(runs("cmd-alt-shift-\(direction)", "move \(direction)"), true, additionalMsg: direction)
                assertEquals(runs("cmd-alt-ctrl-\(direction)", "join-with \(direction); mode main", mode: "service"), true, additionalMsg: direction)
            }
            assertTrue(runs("cmd-alt-comma", "balance-sizes"))
            assertTrue(runs("w", "run-callback on-window-detected --for-every-window; mode main", mode: "service"))
        }

        /// Nothing of the accordion layout, which Inlay doesn't have, and nothing that talks to AeroSpace
        @Test func testBuiltInConfig_noAccordionAndNoAeroSpaceCli() throws {
            let text = try String(contentsOf: projectRoot.appending(path: "inlay.toml"), encoding: .utf8)
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
            assertEquals(text.lowercased().contains("accordion"), false)
            assertEquals(code.lowercased().contains("aerospace"), false)
            assertEquals(code.contains("exec-and-forget"), false)
            assertEquals(code.contains("$HOME") || code.contains("/Users/"), false)
        }

        /// The rules that send the windows of an app to its workspace
        @Test func testBuiltInConfig_windowRules() throws {
            let config = try parse("inlay.toml").config
            func workspace(of appId: String) -> String? {
                config.onWindowDetected.lazy.compactMap { rule -> String? in
                    guard case .legacy(let matcher) = rule.matcher, matcher.appId == appId else { return nil }
                    return rule.run.flatten().filterIsInstance(of: MoveNodeToWorkspaceCommand.self).first?.args.target.val.workspaceNameOrNil()?.raw
                }.first
            }
            assertEquals(workspace(of: "com.mitchellh.ghostty"), "1")
            assertEquals(workspace(of: "dev.zed.Zed"), "2")
            assertEquals(workspace(of: "com.google.Chrome"), "3")
            assertEquals(workspace(of: "com.tinyspeck.slackmacgap"), "4")
            assertEquals(workspace(of: "com.anthropic.claudefordesktop"), "5")
            assertEquals(workspace(of: "com.apple.finder"), nil) // It only floats
            // The last rule is the catch-all one: the tiling windows of every other app float.
            // What it does to each kind of window is in StartupRulesTest
            let last = try #require(config.onWindowDetected.last)
            assertEquals(last.matcher, .command(parseCommand("test %{window-layout} ~= _tiles").cmdOrDie))
            assertTrue(last.run.strictEquals(parseCommand("layout floating").cmdOrDie))
            // The first rule that matches is the only one that runs: the order of the file is the order of the rules
            assertEquals(config.onWindowDetected.filter(\.checkFurtherCallbacks).count, 0)
            assertEquals(config.workspaceToMonitorForceAssignment.keys.sorted(), ["1", "2", "3", "4", "5", "6", "7"])
            // 7 is the empty workspace: no rule sends an app to it, and it stays on the main display with 1 to 5
            let targets = config.onWindowDetected.flatMap { $0.run.flatten().filterIsInstance(of: MoveNodeToWorkspaceCommand.self) }
            assertEquals(targets.compactMap { $0.args.target.val.workspaceNameOrNil()?.raw }.contains("7"), false)
            assertEquals(config.workspaceToMonitorForceAssignment["7"], config.workspaceToMonitorForceAssignment["1"])
        }

        @Test func testI3LikeExample() throws {
            let result = try parse("docs/config-examples/i3-like-config-example.toml")
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
        }

        @Test func testDesignExample() throws {
            let result = try parse("Tests/InlayTests/fixtures/inlay-example.toml")
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            // The example spells out the defaults of every new table. Only the colors per mode are its own
            assertEquals(result.config.tiling, TilingConfig())
            assertEquals(result.config.menuBar, MenuBarConfig())
            assertEquals(result.config.borders.copy(\.modeColors, [:]), BordersConfig())
            assertEquals(result.config.borders.modeColors.keys.sorted(), ["resize", "service"])
            // The persistent workspaces are the ones of the built-in config
            assertEquals(result.config.persistentWorkspaces, try parse("inlay.toml").config.persistentWorkspaces)
        }
    }
}

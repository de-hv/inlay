@testable import AppBundle
import Common
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

        @Test func testDefaultConfig() throws {
            let result = try parse("docs/config-examples/default-config.toml")
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            // The values that the config spells out are the defaults of the code
            assertEquals(result.config.tiling, TilingConfig())
            assertEquals(result.config.menuBar, MenuBarConfig())
            assertEquals(result.config.borders, BordersConfig())
            // The same as a config that says nothing about them
            let bare = parseConfig("config-version = 2\n").config
            assertEquals(bare.tiling, result.config.tiling)
            assertEquals(bare.menuBar, result.config.menuBar)
            assertEquals(bare.borders, result.config.borders)
        }

        /// What the built-in config gives to somebody who installs Inlay without a config of their own
        @Test func testDefaultConfig_workspacesAndBindings() throws {
            let config = try parse("docs/config-examples/default-config.toml").config
            assertEquals(Array(config.persistentWorkspaces), ["1", "2", "3", "4", "5", "6"])
            func runs(_ binding: String, _ command: String) -> Bool {
                let bound = config.modes[mainModeId]?.bindings.values.first { $0.descriptionWithKeyNotation == binding }
                return bound?.commands.strictEquals(parseCommand(command).cmdOrDie) == true
            }
            // The workspaces that aren't persistent keep their bindings: they exist while they are in use
            for name in ["1", "6", "7", "9", "A", "Z"] {
                assertEquals(runs("alt-\(name.lowercased())", "workspace \(name)"), true, additionalMsg: name)
                assertEquals(runs("alt-shift-\(name.lowercased())", "move-node-to-workspace \(name)"), true, additionalMsg: name)
            }
            assertTrue(runs("cmd-alt-comma", "balance-sizes"))
            assertTrue(runs("alt-slash", "layout tiles horizontal vertical"))
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
            // The gaps are the ones of the built-in config: room for the borders of two neighbors
            assertEquals(result.config.gaps, try parse("docs/config-examples/default-config.toml").config.gaps)
            // And the persistent workspaces
            assertEquals(result.config.persistentWorkspaces, try parse("docs/config-examples/default-config.toml").config.persistentWorkspaces)
        }

        /// One-off: INLAY_TEST_CONFIG=<path> scripts/test.sh --filter ShippedConfigsTest prints what Inlay says about a config
        @Test func testConfigFromEnvironment() throws {
            guard let path = ProcessInfo.processInfo.environment["INLAY_TEST_CONFIG"] else { return }
            let result = parseConfig(try String(contentsOf: URL(filePath: path), encoding: .utf8))
            print("INLAY_TEST_CONFIG \(path)")
            print("  errors (\(result.errors.count)):")
            result.strErrors.forEach { print("    \($0)") }
            print("  warnings (\(result.warnings.count)):")
            result.strWarnings.forEach { print("    \($0)") }
            print("  allowReloadConfig: \(result.allowReloadConfig)")
            print("  workspaces: \(result.config.persistentWorkspaces.sorted()) modes: \(result.config.modes.keys.sorted()) bindings(main): \(result.config.modes[mainModeId]?.bindings.count ?? 0)")
        }
    }
}

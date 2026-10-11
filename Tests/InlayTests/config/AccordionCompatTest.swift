@testable import AppBundle
import Common
import Foundation
import Testing

/// Inlay has no accordion layout. The accordion spellings of AeroSpace are accepted with a warning and treated as tiles,
/// so that the config of AeroSpace can be used as is
extension InlayTests {
    @Suite @MainActor struct AccordionCompatTest {
        let name = "AccordionCompatTest"

        init() { setUpWorkspacesForTests() }

        @Test func testConfig_defaultRootContainerLayout() {
            let result = parseConfig(
                """
                config-version = 2
                default-root-container-layout = 'accordion'
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.defaultRootContainerLayout, .tiles)
            assertEquals(
                result.strWarnings,
                ["[WARNING] default-root-container-layout: Inlay has no accordion layout: 'accordion' is treated as 'tiles'"],
            )

            assertEquals(
                parseConfig("default-root-container-layout = 'accordeon'").strErrors,
                ["[ERROR] default-root-container-layout: Can't parse layout 'accordeon'"],
            )
        }

        @Test func testConfig_accordionPadding() {
            let result = parseConfig(
                """
                config-version = 2
                accordion-padding = 30
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(
                result.strWarnings,
                ["[WARNING] accordion-padding: Inlay has no accordion layout: 'accordion-padding' is ignored. Please drop it from the config"],
            )

            assertEquals(
                parseConfig("accordion-padding = 'wide'").strErrors,
                ["[ERROR] accordion-padding: Expected type is 'Int'. But actual type is 'String'"],
            )
        }

        @Test func testConfig_layoutCommands() {
            let result = parseConfig(
                """
                config-version = 2
                after-startup-command = ['layout tiles', 'layout accordion']

                [mode.main.binding]
                    alt-a = 'layout accordion horizontal vertical'
                    alt-b = ['layout h_accordion', 'mode main']
                    alt-c = 'layout tiles horizontal vertical'

                [[on-window-detected]]
                    if.app-id = 'com.apple.finder'
                    run = 'layout v_accordion'
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.allowReloadConfig, true)
            assertEquals(
                result.strWarnings.sorted(),
                [
                    "[WARNING] after-startup-command[1]: Inlay has no accordion layout: 'accordion' is treated as 'tiles'",
                    "[WARNING] mode.main.binding.alt-a: Inlay has no accordion layout: 'accordion' is treated as 'tiles'",
                    "[WARNING] mode.main.binding.alt-b[0]: Inlay has no accordion layout: 'h_accordion' is treated as 'h_tiles'",
                    "[WARNING] on-window-detected[0].run: Inlay has no accordion layout: 'v_accordion' is treated as 'v_tiles'",
                ],
            )
            assertEquals(result.config.onWindowDetected.count, 1)
            assertEquals(result.config.modes[mainModeId]?.bindings.count, 3)
        }

        /// The default config of AeroSpace (which uses 'accordion-padding' and 'layout accordion horizontal vertical')
        /// must load without errors
        @Test func testConfig_aerospaceDefaultConfigLoads() throws {
            let url = projectRoot.appending(path: "docs/upstream-aerospace/config-examples/default-config.toml")
            let result = parseConfig(try String(contentsOf: url, encoding: .utf8))
            assertEquals(result.errors, [])
            assertEquals(
                result.strWarnings.sorted(),
                [
                    "[WARNING] accordion-padding: Inlay has no accordion layout: 'accordion-padding' is ignored. Please drop it from the config",
                    "[WARNING] mode.main.binding.alt-comma: Inlay has no accordion layout: 'accordion' is treated as 'tiles'",
                ],
            )
        }

        @Test func testParseCommand() {
            testParseSingleCommandSucc(
                "layout accordion",
                LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiles]).copy(\.accordionArgs, ["accordion"]),
            )
            testParseSingleCommandSucc(
                "layout h_accordion v_accordion",
                LayoutCmdArgs(rawArgs: [], toggleBetween: [.h_tiles, .v_tiles]).copy(\.accordionArgs, ["h_accordion", "v_accordion"]),
            )
            // It used to toggle between two layouts. Now, it's the same layout twice
            testParseSingleCommandSucc(
                "layout tiles accordion",
                LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiles]).copy(\.accordionArgs, ["accordion"]),
            )
            testParseSingleCommandSucc(
                "layout accordion tiles",
                LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiles]).copy(\.accordionArgs, ["accordion"]),
            )
            testParseSingleCommandSucc(
                "layout accordion horizontal vertical",
                LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiles, .horizontal, .vertical]).copy(\.accordionArgs, ["accordion"]),
            )
            testParseSingleCommandSucc(
                "layout --root v_accordion",
                LayoutCmdArgs(rawArgs: [], toggleBetween: [.v_tiles]).copy(\.accordionArgs, ["v_accordion"]).copy(\.root, true),
            )
            // No warning without accordion
            assertEquals((parseCommand("layout tiles horizontal").cmdOrDie.flatten().first as? LayoutCommand)?.args.accordionWarning, nil)
            // accordion isn't a valid argument of anything else
            testParseCommandFail(
                "layout --for-next-detected-window accordion",
                msg: layoutCommandForNextDetectedWindowFlagIncompatibilityMsg,
                exitCode: 2,
            )
        }

        @Test func testRun_accordionKeepsOrientation() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))

            let io = CmdIoImpl(stdin: .emptyStdin)
            let result = await parseCommand("layout v_accordion").cmdOrDie.run(.defaultEnv, io)
            assertEquals(result.rawValue, 0)
            assertEquals(io.stderr, ["Inlay has no accordion layout: 'v_accordion' is treated as 'v_tiles'"])
            assertEquals(root.layoutDescription, .v_tiles([.window(1), .window(2)]))

            await parseCommand("layout h_accordion").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
        }

        @Test func testRun_accordionIsTiles() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            for command in ["layout accordion", "layout tiles accordion", "layout accordion tiles"] {
                let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
                assertEquals(result.exitCode.rawValue, 0)
                assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
            }
        }

        /// The binding of the default config of AeroSpace. Without accordion, it only toggles the orientation
        @Test func testRun_accordionHorizontalVertical() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            await parseCommand("layout accordion horizontal vertical").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(root.layoutDescription, .v_tiles([.window(1), .window(2)]))
            await parseCommand("layout accordion horizontal vertical").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
        }
    }
}

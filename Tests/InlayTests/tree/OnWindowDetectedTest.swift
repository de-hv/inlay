@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct OnWindowDetectedTest {
        let name = "OnWindowDetectedTest"

        init() { setUpWorkspacesForTests() }

        @Test func testMatcherCommandReceivesDetectedWindowId() async {
            let workspace = Workspace.get(byName: name)
            let focused = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let detected = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            assertEquals(focused.focusWindow(), true)
            assertEquals(focus.windowOrNil?.windowId, 1)

            let callback = WindowDetectedCallback(
                matcher: .command(parseCommand("test %{window-id} = 2").cmdOrDie),
                rawRun: .empty,
            )

            assertEquals(await callback.matches(detected), true)
            assertEquals(await callback.matches(focused), false)
        }

        @Test func testRunCommandReceivesDetectedWindowIdInEnv() async {
            let workspaceA = Workspace.get(byName: "a")
            let focused = TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
            let detected = TestWindow.new(id: 2, parent: workspaceA.rootTilingContainer)
            assertEquals(focused.focusWindow(), true)
            assertEquals(focus.windowOrNil?.windowId, 1)

            config.onWindowDetected = [
                WindowDetectedCallback(
                    matcher: .command(.empty), // true
                    rawRun: parseCommand("move-node-to-workspace b").cmdOrDie,
                ),
            ]

            await runOnWindowDetected(ifConventional: detected) // todo: tryOnWindowDetected must not be called manually in tests

            assertEquals((Workspace.get(byName: "b").rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 2)
            assertEquals((workspaceA.rootTilingContainer.children.singleOrNil() as? Window)?.windowId, 1)
        }

        @Test func testLayoutTilingRuleKeepsDialogsFloating() async {
            let workspace = Workspace.get(byName: name)
            let browser = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let dialog = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
            dialog.detectedType = .dialog
            let restored = TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer)
            assertEquals(browser.focusWindow(), true)

            config.onWindowDetected = [
                WindowDetectedCallback(
                    matcher: .command(.empty), // true
                    rawRun: parseCommand("layout tiling").cmdOrDie,
                ),
            ]

            await runOnWindowDetected(ifConventional: dialog)
            await runOnWindowDetected(ifConventional: restored)

            assertEquals(dialog.parent === workspace.floatingWindowsContainer, true)
            assertEquals(restored.parent is TilingContainer, true)
        }

        @Test func testLayoutTilingCommandStillTilesDialogs() async {
            let workspace = Workspace.get(byName: name)
            let dialog = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
            dialog.detectedType = .dialog

            await LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiling]))
                .run(.defaultEnv.withWindowId(dialog.windowId), .emptyStdin)

            assertEquals(dialog.parent is TilingContainer, true)
        }
    }
}

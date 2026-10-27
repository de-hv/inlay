@testable import AppBundle
import Common
import Foundation
import Testing

/// The test monitor is 1920x1080. The layout takes 1920x1079 (see Workspace.layoutWorkspace)
extension InlayTests {
    @Suite @MainActor struct ArrangeWorkspaceCommandTest {
        let workspace: Workspace

        init() {
            setUpWorkspacesForTests()
            // The real defaults. setUpWorkspacesForTests disables the normalizations
            config.enableNormalizationFlattenContainers = true
            config.enableNormalizationOppositeOrientationForNestedContainers = true
            config.tiling = TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5)
            workspace = focus.workspace
        }

        @Test func testDwindle_aRowBecomesTheSequenceOfNewWindows() async throws {
            row(1 ... 5)
            try await run("arrange-workspace dwindle")
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .v_tiles([.window(4), .window(5)])])])]),
            )
            assertRects([
                1: (0, 0, 960, 1079),
                2: (960, 0, 960, 539.5),
                3: (960, 539.5, 480, 539.5),
                4: (1440, 539.5, 480, 269.75),
                5: (1440, 809.25, 480, 269.75),
            ])
        }

        @Test func testDwindle_twoStackedWindowsGoSideBySide() async throws {
            workspace.rootTilingContainer.changeOrientation(.v)
            row(1 ... 2)
            try await run("arrange-workspace dwindle")
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 1079)])
        }

        @Test func testDwindle_splitRatio() async throws {
            config.tiling.splitRatio = 0.6
            row(1 ... 2)
            try await run("arrange-workspace dwindle")
            assertRects([1: (0, 0, 1152, 1079), 2: (1152, 0, 768, 1079)])
        }

        @Test func testDwindle_singleWindow() async throws {
            row(1 ... 1)
            try await run("arrange-workspace dwindle")
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
        }

        @Test func testGridAndRow() async throws {
            row(1 ... 3)
            try await run("arrange-workspace dwindle")
            try await run("arrange-workspace grid")
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.h_tiles([.window(1), .window(2)]), .window(3)]))
            try await run("arrange-workspace row")
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
        }

        /// The floating windows stay where they are, and the focused window is still the most recent one
        @Test func testFloatingWindowsAndFocus() async throws {
            row(1 ... 3)
            TestWindow.new(id: 10, parent: workspace.floatingWindowsContainer)
            assertEquals(window(2).focusWindow(), true)
            try await run("arrange-workspace dwindle")
            assertEquals(workspace.floatingWindows.map(\.windowId), [10])
            assertEquals(workspace.rootTilingContainer.mostRecentWindowRecursive?.windowId, 2)
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testAnotherWorkspace() async throws {
            let other = Workspace.get(byName: "other")
            other.rootTilingContainer.apply {
                TestWindow.new(id: 11, parent: $0)
                TestWindow.new(id: 12, parent: $0)
                TestWindow.new(id: 13, parent: $0)
            }
            try await run("arrange-workspace --workspace other dwindle")
            other.normalizeContainers()
            assertEquals(other.rootTilingContainer.layoutDescription, .h_tiles([.window(11), .v_tiles([.window(12), .window(13)])]))
        }

        @Test func testParse() {
            assertNil(parseCommand("arrange-workspace").cmdOrNil)
            assertNil(parseCommand("arrange-workspace spiral").cmdOrNil)
            assertNotNil(parseCommand("arrange-workspace grid").cmdOrNil)
        }

        private func row(_ ids: ClosedRange<UInt32>) {
            for id in ids { TestWindow.new(id: id, parent: workspace.rootTilingContainer) }
        }

        /// Runs the command, normalizes the tree like the real app, and lays the workspace out
        private func run(_ command: String) async throws {
            let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0, additionalMsg: command)
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
        }

        private func window(_ id: UInt32) -> TestWindow {
            workspace.allLeafWindowsRecursive.first { $0.windowId == id } as! TestWindow
        }

        /// The frames of all the tiling windows of the workspace: id -> (x, y, width, height)
        private func assertRects(_ expected: [UInt32: (CGFloat, CGFloat, CGFloat, CGFloat)], sourceLocation: SourceLocation = #_sourceLocation) {
            let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
            assertEquals(windows.map(\.windowId).sorted(), expected.keys.sorted(), sourceLocation: sourceLocation)
            for window in windows {
                guard let expected = expected[window.windowId], let actual = (window as! TestWindow).rect else {
                    Issue.record("Window \(window.windowId) isn't laid out", sourceLocation: sourceLocation)
                    continue
                }
                let actualArr = [actual.topLeftX, actual.topLeftY, actual.width, actual.height]
                let expectedArr = [expected.0, expected.1, expected.2, expected.3]
                if zip(actualArr, expectedArr).contains(where: { abs($0 - $1) > 0.001 }) {
                    failExpectedActual("window \(window.windowId): \(expectedArr)", actualArr, sourceLocation: sourceLocation)
                }
            }
        }
    }
}

@testable import AppBundle
import Common
import Foundation
import Testing

/// Placement of new tiling windows with `tiling.new-window-placement = 'dwindle'`.
/// The test monitor is 1920x1080. The layout takes 1920x1079 (see Workspace.layoutWorkspace)
extension InlayTests {
    @Suite @MainActor struct DwindleTest {
        let workspace: Workspace

        init() {
            setUpWorkspacesForTests()
            // The real defaults. setUpWorkspacesForTests disables the normalizations
            config.enableNormalizationFlattenContainers = true
            config.enableNormalizationOppositeOrientationForNestedContainers = true
            config.tiling = TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5)
            workspace = focus.workspace
        }

        // MARK: - The sequence

        @Test func testSequenceFrom1To5Windows() async throws {
            let root = workspace.rootTilingContainer
            try await openWindow(1)
            assertEquals(root.layoutDescription, .h_tiles([.window(1)]))
            assertRects([1: (0, 0, 1920, 1079)])

            try await openWindow(2) // 1 is wider than tall -> side by side
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 1079)])

            try await openWindow(3) // 2 is taller than wide -> stacked
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 3: (960, 539.5, 960, 539.5)])

            try await openWindow(4) // 3 is wider than tall -> side by side
            assertEquals(
                root.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])])]),
            )
            assertRects([
                1: (0, 0, 960, 1079),
                2: (960, 0, 960, 539.5),
                3: (960, 539.5, 480, 539.5),
                4: (1440, 539.5, 480, 539.5),
            ])

            try await openWindow(5) // 4 is taller than wide -> stacked
            assertEquals(
                root.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .v_tiles([.window(4), .window(5)])])])]),
            )
            assertRects([
                1: (0, 0, 960, 1079),
                2: (960, 0, 960, 539.5),
                3: (960, 539.5, 480, 539.5),
                4: (1440, 539.5, 480, 269.75),
                5: (1440, 809.25, 480, 269.75),
            ])
            assertEquals(focus.windowOrNil?.windowId, 5) // The new window gets the focus
        }

        /// The windows that appear in one refresh session (for example, at startup) aren't laid out in between.
        /// The result must be the same
        @Test func testSequenceWithoutLayoutInBetween() async throws {
            for id in 1 ... 5 as ClosedRange<UInt32> {
                TestWindow.newTiling(id: id, workspace: workspace)
            }
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .v_tiles([.window(4), .window(5)])])])]),
            )
            try await workspace.layoutWorkspace()
            assertRects([
                1: (0, 0, 960, 1079),
                2: (960, 0, 960, 539.5),
                3: (960, 539.5, 480, 539.5),
                4: (1440, 539.5, 480, 269.75),
                5: (1440, 809.25, 480, 269.75),
            ])
        }

        @Test func testTargetIsTheFocusedWindow_notTheMostRecentOne() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> {
                TestWindow.new(id: id, parent: workspace.rootTilingContainer)
            }
            assertEquals(window(1).focusWindow(), true)
            window(3).markAsMostRecentChild() // For example, flatten-workspace-tree rebinds all the windows
            assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3)

            try await openWindow(4)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.v_tiles([.window(1), .window(4)]), .window(2), .window(3)]),
            )
        }

        /// The focused window is floating
        @Test func testTargetIsTheMostRecentTilingWindow() async throws {
            try await openWindow(1)
            try await openWindow(2)
            // Not the last one, and the focused window is floating
            assertEquals(window(1).focusWindow(), true)
            assertEquals(TestWindow.new(id: 10, parent: workspace.floatingWindowsContainer).focusWindow(), true)

            try await openWindow(3)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.v_tiles([.window(1), .window(3)]), .window(2)]),
            )
            assertRects([1: (0, 0, 960, 539.5), 3: (0, 539.5, 960, 539.5), 2: (960, 0, 960, 1079)])
        }

        @Test func testSquareTargetIsSplitVertically() async throws {
            // 1079x1079
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer, adaptiveWeight: 1079)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer, adaptiveWeight: 841)
            assertEquals(window(1).focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertRects([1: (0, 0, 1079, 1079), 2: (1079, 0, 841, 1079)])

            try await openWindow(3)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.v_tiles([.window(1), .window(3)]), .window(2)]),
            )
        }

        // MARK: - The three placement cases

        /// Case a. The container of the target already has the required orientation
        @Test func testCaseA_sameOrientation_newWindowIsNextSibling() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1400)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 320)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 200)
            }
            assertEquals(window(1).focusWindow(), true)

            try await openWindow(4)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .window(4), .window(2), .window(3)]),
            )
            // 1 and 4 share the space of 1. The other siblings keep their sizes
            assertRects([
                1: (0, 0, 700, 1079),
                4: (700, 0, 700, 1079),
                2: (1400, 0, 320, 1079),
                3: (1720, 0, 200, 1079),
            ])
        }

        /// Case a. The weights aren't in screen points until the first layout. The split must not depend on it
        @Test func testCaseA_weightsAreNotNormalizedYet() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 500)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 100)
            }
            assertEquals(window(1).focusWindow(), true)

            TestWindow.newTiling(id: 3, workspace: workspace)
            try await workspace.layoutWorkspace()
            // Layout of the weights 500 and 100 in 1920: 1160 and 760
            assertRects([1: (0, 0, 580, 1079), 3: (580, 0, 580, 1079), 2: (1160, 0, 760, 1079)])
        }

        /// Case b. The target is the only child of the root container
        @Test func testCaseB_singleWindow_rootChangesOrientation() async throws {
            config.defaultRootContainerOrientation = .vertical
            try await openWindow(1)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.window(1)]))
            assertRects([1: (0, 0, 1920, 1079)])

            try await openWindow(2)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 1079)])
        }

        /// Case c. The container of the target has the opposite orientation
        @Test func testCaseC_oppositeOrientation_newContainerTakesThePlaceOfTheTarget() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(2).focusWindow(), true)

            try await openWindow(4)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .window(4)]), .window(3)]),
            )
            // The container has the position and the weight of the target. The other siblings keep their sizes
            assertRects([
                1: (0, 0, 800, 1079),
                2: (800, 0, 600, 539.5),
                4: (800, 539.5, 600, 539.5),
                3: (1400, 0, 520, 1079),
            ])
        }

        @Test func testEmptyWorkspace_newWindowGoesToRoot() async throws {
            TestWindow.new(id: 10, parent: workspace.floatingWindowsContainer)
            try await openWindow(1)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
            assertRects([1: (0, 0, 1920, 1079)])
        }

        // MARK: - split-ratio

        @Test func testSplitRatio() async throws {
            config.tiling.splitRatio = 0.7
            try await openWindow(1)
            try await openWindow(2) // case a
            assertRects([1: (0, 0, 1344, 1079), 2: (1344, 0, 576, 1079)])

            try await openWindow(3) // case c
            assertRects([
                1: (0, 0, 1344, 1079),
                2: (1344, 0, 576, 755.3),
                3: (1344, 755.3, 576, 323.7),
            ])
        }

        @Test func testSplitRatio_caseB() async throws {
            config.defaultRootContainerOrientation = .vertical
            config.tiling.splitRatio = 0.25
            try await openWindow(1)
            try await openWindow(2)
            assertRects([1: (0, 0, 480, 1079), 2: (480, 0, 1440, 1079)])
        }

        @Test func testInnerGaps() async throws {
            config.gaps = Gaps(
                inner: .init(vertical: .constant(10), horizontal: .constant(20)),
                outer: .init(left: .constant(8), bottom: .constant(8), top: .constant(8), right: .constant(8)),
            )
            for id in 1 ... 3 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]),
            )
            // 1904x1063 without the outer gaps
            assertRects([
                1: (8, 8, 942, 1063),
                2: (970, 8, 942, 526.5),
                3: (970, 544.5, 942, 526.5),
            ])
        }

        // MARK: - Closing

        @Test func testClose_twoSiblings_siblingTakesTheSpace() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))

            try await close(3)
            // The existing flatten normalization
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 1079)])
        }

        @Test func testClose_unwindsTheSequence() async throws {
            for id in 1 ... 5 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            try await close(5)
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 3: (960, 539.5, 480, 539.5), 4: (1440, 539.5, 480, 539.5)])
            try await close(4)
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 3: (960, 539.5, 960, 539.5)])
            try await close(3)
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 1079)])
            try await close(2)
            assertRects([1: (0, 0, 1920, 1079)])
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
        }

        @Test func testClose_threeSiblings_previousSiblingTakesTheSpace() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(3).focusWindow(), true)

            try await close(2)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(3)]))
            assertRects([1: (0, 0, 1400, 1079), 3: (1400, 0, 520, 1079)])
        }

        @Test func testClose_threeSiblings_firstWindow_nextSiblingTakesTheSpace() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(3).focusWindow(), true)

            try await close(1)
            assertRects([2: (0, 0, 1400, 1079), 3: (1400, 0, 520, 1079)])
        }

        @Test func testClose_threeSiblings_lastWindow_weightsAreNotNormalizedYet() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 1)
            }
            assertEquals(window(1).focusWindow(), true)

            try await close(3) // No layout before closing
            assertRects([1: (0, 0, 640, 1079), 2: (640, 0, 1280, 1079)])
        }

        /// Open and close is the identity
        @Test func testOpenAndClose_restoresTheLayout() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1400)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(1).focusWindow(), true)
            try await openWindow(3)
            assertRects([1: (0, 0, 700, 1079), 3: (700, 0, 700, 1079), 2: (1400, 0, 520, 1079)])

            try await close(3)
            assertRects([1: (0, 0, 1400, 1079), 2: (1400, 0, 520, 1079)])
        }

        // MARK: - The other ways in and out of the tiling tree

        @Test func testFloatingToTiling_splitsTheMostRecentTilingWindow() async throws {
            try await openWindow(1)
            try await openWindow(2)
            assertEquals(TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer).focusWindow(), true)

            try await run("layout tiling")
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]),
            )
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 3: (960, 539.5, 960, 539.5)])
        }

        @Test func testTilingToFloating_previousSiblingTakesTheSpace() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(2).focusWindow(), true)

            try await run("layout floating")
            assertEquals(workspace.floatingWindows.map(\.windowId), [2])
            assertRects([1: (0, 0, 1400, 1079), 3: (1400, 0, 520, 1079)])
        }

        @Test func testMoveNodeToWorkspace() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            let other = Workspace.get(byName: "other")
            TestWindow.new(id: 4, parent: other.rootTilingContainer)
            TestWindow.new(id: 5, parent: other.rootTilingContainer)
            assertEquals(window(3).focusWindow(), true)

            try await run("move-node-to-workspace other")
            // Source workspace: the previous sibling takes the space
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            assertRects([1: (0, 0, 800, 1079), 2: (800, 0, 1120, 1079)])
            // Target workspace: the window splits the most recent tiling window
            assertEquals(other.rootTilingContainer.layoutDescription, .h_tiles([.window(4), .v_tiles([.window(5), .window(3)])]))
            try await other.layoutWorkspace()
            assertRects([4: (0, 0, 960, 1079), 5: (960, 0, 960, 539.5), 3: (960, 539.5, 960, 539.5)], in: other)
        }

        @Test func testMoveNodeToEmptyWorkspace() async throws {
            try await openWindow(1)
            try await openWindow(2)
            let other = Workspace.get(byName: "other")

            try await run("move-node-to-workspace other")
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
            assertEquals(other.rootTilingContainer.layoutDescription, .h_tiles([.window(2)]))
        }

        // MARK: - Normalizations

        /// The placement never creates a container with the orientation of its parent, a container with a single child,
        /// or an empty container. So the normalizations have nothing to change
        @Test func testNormalizationsDontChangeTheTree() async throws {
            for id in 1 ... 8 as ClosedRange<UInt32> {
                TestWindow.newTiling(id: id, workspace: workspace)
                if id == 4 { assertEquals(window(1).focusWindow(), true) } // Split a window in the middle of the tree too
                let before = workspace.rootTilingContainer.layoutDescription
                assertNormalized(workspace.rootTilingContainer)
                workspace.normalizeContainers()
                assertEquals(workspace.rootTilingContainer.layoutDescription, before)
                try await workspace.layoutWorkspace()
            }
            assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 8)
        }

        /// A window is closed and another one is opened in the same refresh session:
        /// the container of the closed window is not flattened yet
        @Test func testPlacementSeesTheNormalizedTree() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            window(3).closeAxWindow() // h[1, v[2]]. No normalization and no layout
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2)])]))

            try await openWindow(4)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(4)])]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 4: (960, 539.5, 960, 539.5)])
        }

        /// The flattened container gets the orientation of its new parent, so the existing normalization rotates it
        @Test func testClose_flattenAndOppositeOrientationNormalizations() async throws {
            for id in 1 ... 4 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])])]),
            )

            try await close(2)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(3), .window(4)])]),
            )
            assertRects([1: (0, 0, 960, 1079), 3: (960, 0, 960, 539.5), 4: (960, 539.5, 960, 539.5)])
        }

        @Test func testWithoutNormalizations() async throws {
            config.enableNormalizationFlattenContainers = false
            config.enableNormalizationOppositeOrientationForNestedContainers = false
            for id in 1 ... 4 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])])]),
            )
        }

        // MARK: - The commands still work on the tree built by dwindle

        @Test func testCommandsOnDwindleTree() async throws {
            for id in 1 ... 4 as ClosedRange<UInt32> {
                try await openWindow(id)
            }
            let root = workspace.rootTilingContainer

            try await run("swap left") // 4 <-> 3
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(4), .window(3)])])]))

            try await run("resize width +100") // 4 is focused
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 4: (960, 539.5, 580, 539.5), 3: (1540, 539.5, 380, 539.5)])

            try await run("balance-sizes")
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 4: (960, 539.5, 480, 539.5), 3: (1440, 539.5, 480, 539.5)])

            try await run("move up") // 4 leaves h[4, 3] and goes above it
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(4), .window(3)])]))

            try await run("join-with left") // 4 joins 1
            assertEquals(root.layoutDescription, .h_tiles([.v_tiles([.window(1), .window(4)]), .v_tiles([.window(2), .window(3)])]))

            try await run("flatten-workspace-tree")
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(4), .window(2), .window(3)]))
            assertRects([1: (0, 0, 480, 1079), 4: (480, 0, 480, 1079), 2: (960, 0, 480, 1079), 3: (1440, 0, 480, 1079)])

            // After the flatten, dwindle only decides where the next window goes
            try await openWindow(5)
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(4), .window(5)]), .window(2), .window(3)]))
        }

        // MARK: - after-focused

        @Test func testAfterFocused_keepsAeroSpaceBehavior() async throws {
            config.tiling.newWindowPlacement = .afterFocused
            try await openWindow(1)
            try await openWindow(2)
            try await openWindow(3)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
            assertRects([1: (0, 0, 640, 1079), 2: (640, 0, 640, 1079), 3: (1280, 0, 640, 1079)])

            // Next sibling of the most recent window. All the siblings share the space
            assertEquals(window(1).focusWindow(), true)
            try await openWindow(4)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(4), .window(2), .window(3)]))
            assertRects([1: (0, 0, 480, 1079), 4: (480, 0, 480, 1079), 2: (960, 0, 480, 1079), 3: (1440, 0, 480, 1079)])

            // The most recent window is floating -> the end of the root container
            assertEquals(TestWindow.new(id: 10, parent: workspace.floatingWindowsContainer).focusWindow(), true)
            try await openWindow(5)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .window(4), .window(2), .window(3), .window(5)]),
            )
        }

        @Test func testAfterFocused_nestedContainer() async throws {
            config.tiling.newWindowPlacement = .afterFocused
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    assertEquals(TestWindow.new(id: 3, parent: $0).focusWindow(), true)
                }
            }
            try await openWindow(4)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .window(3), .window(4)])]),
            )
        }

        @Test func testAfterFocused_close_siblingsShareTheSpace() async throws {
            config.tiling.newWindowPlacement = .afterFocused
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(3).focusWindow(), true)

            try await close(2)
            assertRects([1: (0, 0, 1100, 1079), 3: (1100, 0, 820, 1079)])
        }

        @Test func testAfterFocused_moveNodeToWorkspace_endOfRoot() async throws {
            config.tiling.newWindowPlacement = .afterFocused
            try await openWindow(1)
            let other = Workspace.get(byName: "other")
            TestWindow.new(id: 4, parent: other.rootTilingContainer)
            TestWindow.new(id: 5, parent: other.rootTilingContainer)

            try await run("move-node-to-workspace other")
            assertEquals(other.rootTilingContainer.layoutDescription, .h_tiles([.window(4), .window(5), .window(1)]))
        }

        // MARK: - Helpers

        /// A new tiling window appears, gets the focus, and the workspace is laid out
        private func openWindow(_ id: UInt32) async throws {
            assertEquals(TestWindow.newTiling(id: id, workspace: workspace).focusWindow(), true)
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
        }

        private func close(_ id: UInt32) async throws {
            try await run("close --window-id \(id)")
        }

        /// Runs the command (it also runs the normalizations, like the real app) and lays the workspace out
        private func run(_ command: String) async throws {
            let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0, additionalMsg: command)
            try await workspace.layoutWorkspace()
        }

        private func window(_ id: UInt32) -> TestWindow {
            Workspace.all.flatMap(\.allLeafWindowsRecursive).first { $0.windowId == id } as! TestWindow
        }

        /// The frames of all the tiling windows of the workspace: id -> (x, y, width, height)
        private func assertRects(
            _ expected: [UInt32: (CGFloat, CGFloat, CGFloat, CGFloat)],
            in workspace: Workspace? = nil,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            let windows = (workspace ?? self.workspace).rootTilingContainer.allLeafWindowsRecursive
            assertEquals(windows.map(\.windowId).sorted(), expected.keys.sorted(), sourceLocation: sourceLocation)
            for window in windows {
                guard let expected = expected[window.windowId] else { continue }
                guard let actual = (window as! TestWindow).rect else {
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

        private func assertNormalized(_ container: TilingContainer, sourceLocation: SourceLocation = #_sourceLocation) {
            if !container.isRootContainer {
                assertTrue(container.children.count >= 2, sourceLocation: sourceLocation)
                assertNotEquals((container.parent as? TilingContainer)?.orientation, container.orientation, sourceLocation: sourceLocation)
            }
            for child in container.children.filterIsInstance(of: TilingContainer.self) {
                assertNormalized(child, sourceLocation: sourceLocation)
            }
        }
    }
}

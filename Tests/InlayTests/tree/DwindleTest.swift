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

        /// The refresh session notices that macOS made a window fullscreen or minimized it. See: normalizeLayoutReason
        @Test func testMacosFullscreenAndMinimize_previousSiblingTakesTheSpace_andTheWindowGetsItsPlaceBack() async throws {
            for minimize in [false, true] {
                for window in workspace.allLeafWindowsRecursive + macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self) {
                    window.unbindFromParent()
                }
                workspace.rootTilingContainer.apply {
                    TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                    TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                    TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
                }
                assertEquals(window(3).focusWindow(), true)
                let leaving = window(2)

                if minimize { leaving.isMacosMinimizedForTest = true } else { leaving.isMacosFullscreenForTest = true }
                try await refresh()
                assertTrue(minimize ? leaving.parent is MacosMinimizedWindowsContainer : leaving.parent is MacosFullscreenWindowsContainer)
                assertRects([1: (0, 0, 1400, 1079), 3: (1400, 0, 520, 1079)])

                // It doesn't split the focused window, like a new window would: it goes back to where it was
                assertEquals(window(1).focusWindow(), true)
                leaving.isMacosMinimizedForTest = false
                leaving.isMacosFullscreenForTest = false
                try await refresh()
                assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
                assertRects([1: (0, 0, 800, 1079), 2: (800, 0, 600, 1079), 3: (1400, 0, 520, 1079)])
                assertNil(leaving.tilingSlot)
            }
        }

        @Test func testMacosNativeMinimize_twoSiblingsInANestedContainer_containerIsFlattened() async throws {
            try await openWindow(1)
            try await openWindow(2)
            try await openWindow(3)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))

            window(3).isMacosMinimizedForTest = true
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 1079)])
        }

        // MARK: - Coming back from minimize, the macOS native fullscreen and a hidden app. See: TilingSlot

        /// The container of the window was flattened when the window left. The neighbor is split again, the same way
        @Test func testComeBack_theContainerIsGone_theNeighborIsSplitAgain() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> { try await openWindow(id) }
            try await run("resize height +100") // 3 is focused: 439.5 for 2, 639.5 for 3
            let rects: [UInt32: (CGFloat, CGFloat, CGFloat, CGFloat)] = [1: (0, 0, 960, 1079), 2: (960, 0, 960, 439.5), 3: (960, 439.5, 960, 639.5)]
            assertRects(rects)

            // The last child, and then the first one
            for id in [3, 2] as [UInt32] {
                window(id).isMacosMinimizedForTest = true
                try await refresh()
                assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(id == 3 ? 2 : 3)]))
                // A new window would split window 1, the focused one
                assertEquals(window(1).focusWindow(), true)
                window(id).isMacosMinimizedForTest = false
                try await refresh()
                assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))
                assertRects(rects)
            }
        }

        @Test func testComeBack_rootContainer() async throws {
            try await openWindow(1)
            try await openWindow(2)
            try await run("resize width -160") // 2 is focused
            assertRects([1: (0, 0, 1120, 1079), 2: (1120, 0, 800, 1079)])

            // One of two: the root container is never flattened, so the window goes back to its index
            for id in [1, 2] as [UInt32] {
                window(id).isMacosFullscreenForTest = true
                try await refresh()
                assertRects([(id == 1 ? 2 : 1): (0, 0, 1920, 1079)])
                window(id).isMacosFullscreenForTest = false
                try await refresh()
                assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
                assertRects([1: (0, 0, 1120, 1079), 2: (1120, 0, 800, 1079)])
            }

            // The only window
            try await close(2)
            window(1).isMacosMinimizedForTest = true
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([]))
            window(1).isMacosMinimizedForTest = false
            try await refresh()
            assertRects([1: (0, 0, 1920, 1079)])
        }

        /// The sibling of the window is a container. When the window leaves, the container takes the place of
        /// the flattened one, and the normalization turns it around. The window joins it instead of wrapping it
        @Test func testComeBack_theNeighborIsAContainerThatWasTurnedAround() async throws {
            for id in 1 ... 4 as ClosedRange<UInt32> { try await openWindow(id) }
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])])]),
            )
            window(2).isMacosMinimizedForTest = true
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(3), .window(4)])]))

            window(2).isMacosMinimizedForTest = false
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(2), .window(3), .window(4)])]))
            // It was the upper half
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 3: (960, 539.5, 960, 269.75), 4: (960, 809.25, 960, 269.75)])
            assertNormalized(workspace.rootTilingContainer)
        }

        @Test func testComeBack_theTreeChangedInTheMeantime() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(3).focusWindow(), true)

            // The neighbor that took the space is smaller than that space now: the window takes the same fraction of it
            window(2).isMacosMinimizedForTest = true
            try await refresh()
            assertEquals(window(1).focusWindow(), true)
            try await run("resize width -1000") // 1: 1400 -> 400
            window(2).isMacosMinimizedForTest = false
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2), .window(3)]))
            let share: CGFloat = 600 / 1400
            assertRects([1: (0, 0, 400 * (1 - share), 1079), 2: (400 * (1 - share), 0, 400 * share, 1079), 3: (400, 0, 1520, 1079)])

            // The neighbor is gone, and the container is still there: back to its index, with an average size
            try await run("balance-sizes")
            window(2).isMacosMinimizedForTest = true
            try await refresh()
            try await close(1)
            window(2).isMacosMinimizedForTest = false
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(2), .window(3)]))

            // The container was turned around: the window still goes next to its neighbor
            window(3).isMacosMinimizedForTest = true
            try await refresh()
            try await openWindow(4) // 2 is the only window: it is split side by side
            assertEquals(window(2).focusWindow(), true)
            try await run("layout vertical")
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.window(2), .window(4)]))
            window(3).isMacosMinimizedForTest = false
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.window(2), .window(3), .window(4)]))
            assertSound("turned around")
        }

        /// Neither the container nor the neighbor are there anymore: the window is a new window
        @Test func testComeBack_thePlaceIsGone_theWindowIsPlacedLikeANewOne() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> { try await openWindow(id) }
            window(3).isMacosMinimizedForTest = true
            try await refresh()
            try await close(2)
            try await openWindow(4)
            try await openWindow(5)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .v_tiles([.window(4), .window(5)])]))

            assertEquals(window(1).focusWindow(), true)
            window(3).isMacosMinimizedForTest = false
            try await refresh()
            // It splits the focused window: 1 is taller than wide
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.v_tiles([.window(1), .window(3)]), .v_tiles([.window(4), .window(5)])]),
            )
        }

        /// A minimized window belongs to no workspace. It comes back to the focused one
        @Test func testComeBack_inAnotherWorkspace_theWindowIsPlacedLikeANewOne() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> { try await openWindow(id) }
            window(2).isMacosMinimizedForTest = true
            try await refresh()

            let other = Workspace.get(byName: "other")
            TestWindow.new(id: 10, parent: other.rootTilingContainer)
            assertEquals(other.focusWorkspace(), true)
            window(2).isMacosMinimizedForTest = false
            try await normalizeLayoutReason()
            assertEquals(other.rootTilingContainer.layoutDescription, .h_tiles([.window(10), .window(2)]))
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(3)]))
        }

        /// The windows of an app are hidden and shown together
        @Test func testComeBack_severalWindowsAtOnce_everyWindowGetsItsPlace() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 500)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 400)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 300)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 720).apply {
                    TestWindow.new(id: 4, parent: $0, adaptiveWeight: 400)
                    TestWindow.new(id: 5, parent: $0, adaptiveWeight: 679)
                }
            }
            assertEquals(window(1).focusWindow(), true)
            try await workspace.layoutWorkspace()
            let tree = workspace.rootTilingContainer.layoutDescription
            let rects = workspace.rootTilingContainer.allLeafWindowsRecursive.map { ($0 as! TestWindow).rect }

            for ids in [[2, 3], [1, 2], [2, 3, 5], [1, 2, 3, 4], [4, 5]] as [[UInt32]] {
                for id in ids { window(id).isMacosFullscreenForTest = true }
                try await refresh()
                assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.count, 5 - ids.count)
                for id in ids { window(id).isMacosFullscreenForTest = false }
                try await refresh()
                assertEquals(workspace.rootTilingContainer.layoutDescription, tree, additionalMsg: "\(ids)")
                let actual = workspace.rootTilingContainer.allLeafWindowsRecursive.map { ($0 as! TestWindow).rect }
                for (actual, expected) in zip(actual, rects) {
                    guard let actual, let expected else { continue }
                    let difference = max(
                        abs(actual.topLeftX - expected.topLeftX), abs(actual.topLeftY - expected.topLeftY),
                        abs(actual.width - expected.width), abs(actual.height - expected.height),
                    )
                    assertTrue(difference < 0.001)
                }
            }
        }

        @Test func testComeBack_afterFocused_theSiblingsGiveTheSpaceBack() async throws {
            config.tiling.newWindowPlacement = .afterFocused
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 800)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 600)
                TestWindow.new(id: 3, parent: $0, adaptiveWeight: 520)
            }
            assertEquals(window(1).focusWindow(), true)
            window(2).isMacosMinimizedForTest = true
            try await refresh()
            assertRects([1: (0, 0, 1100, 1079), 3: (1100, 0, 820, 1079)])
            window(2).isMacosMinimizedForTest = false
            try await refresh()
            assertRects([1: (0, 0, 800, 1079), 2: (800, 0, 600, 1079), 3: (1400, 0, 520, 1079)])
        }

        /// macos-native-fullscreen and macos-native-minimize move the window on their own, before the refresh session
        /// notices the new state of the window
        @Test func testComeBack_theCommandMovedTheWindowBeforeTheRefresh() async throws {
            for id in 1 ... 3 as ClosedRange<UInt32> { try await openWindow(id) }
            let tree = workspace.rootTilingContainer.layoutDescription
            let leaving = window(2)
            // The same as MacosNativeFullscreenCommand
            leaving.rememberTilingSlot()
            leaving.releaseTilingSpaceToNeighbor()
            leaving.bind(to: workspace.macOsNativeFullscreenWindowsContainer, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            try await refresh() // macOS doesn't report the fullscreen yet
            assertEquals(leaving.layoutReason, .standard)
            leaving.isMacosFullscreenForTest = true
            try await refresh()
            assertEquals(leaving.layoutReason, .macos(prevParentKind: .macosFullscreenWindowsContainer))
            assertNotNil(leaving.tilingSlot)

            assertEquals(window(1).focusWindow(), true)
            leaving.isMacosFullscreenForTest = false
            try await refresh()
            assertEquals(workspace.rootTilingContainer.layoutDescription, tree)
            assertRects([1: (0, 0, 960, 1079), 2: (960, 0, 960, 539.5), 3: (960, 539.5, 960, 539.5)])
        }

        /// A floating window comes back as a floating window, and it forgets a place it had as a tiling one
        @Test func testComeBack_floatingWindow() async throws {
            try await openWindow(1)
            try await openWindow(2)
            window(2).isMacosMinimizedForTest = true
            try await refresh()
            window(2).isMacosMinimizedForTest = false
            try await refresh()
            assertEquals(window(2).focusWindow(), true)
            try await run("layout floating")

            window(2).isMacosMinimizedForTest = true
            try await refresh()
            assertNil(window(2).tilingSlot)
            window(2).isMacosMinimizedForTest = false
            try await refresh()
            assertEquals(workspace.floatingWindows.map(\.windowId), [2])
            assertRects([1: (0, 0, 1920, 1079)])
        }

        // MARK: - The tree stays sound

        /// Extreme ratios and deep trees: every window keeps a positive size, and the windows tile the whole workspace
        @Test func testExtremeSplitRatios_noWindowGetsANonPositiveSize() async throws {
            for ratio in [0.1, 0.9] as [CGFloat] {
                for window in workspace.allLeafWindowsRecursive { window.unbindFromParent() }
                config.tiling = TilingConfig(newWindowPlacement: .dwindle, splitRatio: ratio)
                for id in 1 ... 8 as ClosedRange<UInt32> {
                    try await openWindow(id)
                    assertSound("ratio \(ratio), \(id) windows")
                }
                // Close in an order that isn't the reverse of the opening
                for id in [3, 1, 8, 5, 2, 7, 6] as [UInt32] {
                    try await close(id)
                    assertSound("ratio \(ratio), closed \(id)")
                }
                assertRects([4: (0, 0, 1920, 1079)])
            }
        }

        /// A long pseudo-random session of the things a user and macOS do. After every step the tree must be normalized
        /// (no empty container, no container with the orientation of its parent), every weight and every frame
        /// must be positive, and the frames must tile the workspace without holes or overlaps
        @Test func testRandomSession_theTreeStaysSound() async throws {
            var seed: UInt64 = 0x1D1A7
            func random(_ bound: Int) -> Int {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407 // Deterministic: a failure can be reproduced
                return Int((seed >> 33) % UInt64(bound))
            }
            let commands = [
                "layout floating tiling", "swap left", "swap down", "move right", "move up", "join-with left", "join-with down",
                "resize smart +200", "resize smart -200", "balance-sizes", "layout horizontal vertical", "flatten-workspace-tree",
                "focus left", "focus right", "focus up", "focus down", "split opposite",
            ]
            unsafe Self.issues = 0
            var nextId: UInt32 = 1
            var log: [String] = []
            for step in 0 ..< 600 {
                let tiling = workspace.rootTilingContainer.allLeafWindowsRecursive
                let all = workspace.allLeafWindowsRecursive
                let minimized = macosMinimizedWindowsContainer.children.filterIsInstance(of: TestWindow.self)
                switch random(12) {
                    case 10 where !all.isEmpty, 11 where !all.isEmpty:
                        // macOS minimizes a window or makes it fullscreen, or brings one back. The window may be floating
                        let away = minimized + workspace.macOsNativeFullscreenWindowsContainer.children.filterIsInstance(of: TestWindow.self)
                        if !away.isEmpty && random(2) == 0 {
                            let window = away[random(away.count)]
                            log.append("come back \(window.windowId)")
                            window.isMacosMinimizedForTest = false
                            window.isMacosFullscreenForTest = false
                        } else {
                            let window = all[random(all.count)] as! TestWindow
                            if random(2) == 0 {
                                log.append("minimize \(window.windowId)")
                                window.isMacosMinimizedForTest = true
                            } else {
                                log.append("native fullscreen \(window.windowId)")
                                window.isMacosFullscreenForTest = true
                            }
                        }
                        try await refresh()
                    case 0 ..< 4 where tiling.count < 9, _ where all.isEmpty && minimized.isEmpty:
                        log.append("open \(nextId)")
                        try await openWindow(nextId)
                        nextId += 1
                    case _ where all.isEmpty:
                        continue
                    case 4 ..< 6:
                        let id = all[random(all.count)].windowId
                        log.append("close \(id)")
                        try await close(id)
                    case 6:
                        let window = all[random(all.count)]
                        log.append("focus \(window.windowId)")
                        _ = window.focusWindow()
                    default:
                        let command = commands[random(commands.count)]
                        log.append(command)
                        // The command may not apply (nothing in that direction, floating window focused...). That's fine
                        _ = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
                        try await workspace.layoutWorkspace()
                }
                assertSound("step \(step): \(log.suffix(12).joined(separator: " | "))")
                if unsafe Self.issues > 0 { return }
            }
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

        /// What a refresh session does after macOS minimized a window, made it fullscreen, or brought it back
        private func refresh() async throws {
            // Otherwise normalizeLayoutReason asks the real app of the window whether it is hidden
            config.automaticallyUnhideMacosHiddenApps = true
            try await normalizeLayoutReason()
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
            // The minimized windows belong to no workspace
            let windows = Workspace.all.flatMap(\.allLeafWindowsRecursive) + macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self)
            return windows.first { $0.windowId == id } as! TestWindow
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

        /// Normalized, positive weights and frames, and the frames tile the workspace
        private func assertSound(_ context: String, sourceLocation: SourceLocation = #_sourceLocation) {
            let root = workspace.rootTilingContainer
            func fail(_ message: String) {
                unsafe Self.issues += 1
                Issue.record("\(message)\n\(context)\n\(root.layoutDescription)", sourceLocation: sourceLocation)
            }
            func visit(_ container: TilingContainer) {
                if !container.isRootContainer {
                    if container.children.count < 2 { fail("A nested container with \(container.children.count) children") }
                    if (container.parent as? TilingContainer)?.orientation == container.orientation { fail("A container with the orientation of its parent") }
                }
                for child in container.children {
                    let weight = child.getWeight(container.orientation)
                    if !(weight > 0) || !weight.isFinite { fail("Weight \(weight)") }
                    if let child = child as? TilingContainer { visit(child) }
                }
            }
            visit(root)
            let windows = root.allLeafWindowsRecursive
            if windows.isEmpty { return }
            let rects = windows.compactMap { ($0 as? TestWindow)?.rect }
            if rects.count != windows.count { return fail("A tiling window without a frame") }
            for rect in rects where !(rect.width > 0 && rect.height > 0) { fail("Frame \(rect)") }
            let area = rects.reduce(0) { $0 + $1.width * $1.height }
            if abs(area - 1920 * 1079) > 1 { fail("The frames cover \(area) of \(1920 * 1079)") }
            for (i, a) in rects.enumerated() {
                for b in rects[(i + 1)...] {
                    let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
                    let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
                    if overlapX > 0.001 && overlapY > 0.001 { fail("\(a) overlaps \(b)") }
                }
            }
        }

        nonisolated(unsafe) private static var issues = 0

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

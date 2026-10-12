@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct ResizeCommandTest {
        let name = "ResizeCommandTest"

        init() { setUpWorkspacesForTests() }

        @Test func testParseCommand() {
            testParseSingleCommandSucc("resize smart +10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .add(10)))
            testParseSingleCommandSucc("resize smart -10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .subtract(10)))
            testParseSingleCommandSucc("resize smart 10", ResizeCmdArgs(rawArgs: [], dimension: .smart, units: .set(10)))

            testParseSingleCommandSucc("resize smart-opposite +10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .add(10)))
            testParseSingleCommandSucc("resize smart-opposite -10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .subtract(10)))
            testParseSingleCommandSucc("resize smart-opposite 10", ResizeCmdArgs(rawArgs: [], dimension: .smartOpposite, units: .set(10)))

            testParseSingleCommandSucc("resize height 10", ResizeCmdArgs(rawArgs: [], dimension: .height, units: .set(10)))
            testParseSingleCommandSucc("resize width 10", ResizeCmdArgs(rawArgs: [], dimension: .width, units: .set(10)))

            testParseCommandFail("resize s 10", msg: """
                ERROR: Can't parse 's'.
                       Possible values: (width|height|smart|smart-opposite)
                """, exitCode: 2)
            testParseCommandFail("resize smart foo", msg: "ERROR: <number> argument must be a number", exitCode: 2)
        }

        @Test func testWidthAdd_growsTargetShrinksSiblings() async {
            var window1: Window!
            var window2: Window!
            var window3: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 4)
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 4)
                window3 = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 4)
            }
            _ = window1.focusWindow()

            await parseCommand("resize width +2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            // The weights are screen points: 1920 / 3 = 640 each. diff = +2, childDiff = 2 / (3 - 1) = 1
            assertEquals(window1.hWeight, 642)
            assertEquals(window2.hWeight, 639)
            assertEquals(window3.hWeight, 639)
        }

        @Test func testWidthSubtract_shrinksTargetGrowsSiblings() async {
            var window1: Window!
            var window2: Window!
            var window3: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 4)
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 4)
                window3 = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 4)
            }
            _ = window1.focusWindow()

            await parseCommand("resize width -2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            // diff = -2, childDiff = -1
            assertEquals(window1.hWeight, 638)
            assertEquals(window2.hWeight, 641)
            assertEquals(window3.hWeight, 641)
        }

        @Test func testWidthSet_diffIsAbsoluteMinusCurrent() async {
            var window1: Window!
            var window2: Window!
            var window3: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 4)
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 4)
                window3 = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 4)
            }
            _ = window1.focusWindow()

            await parseCommand("resize width 642").cmdOrDie.run(.defaultEnv, .emptyStdin)
            // diff = 642 - 640 = 2, childDiff = 1
            assertEquals(window1.hWeight, 642)
            assertEquals(window2.hWeight, 639)
            assertEquals(window3.hWeight, 639)
        }

        @Test func testHeight_climbsToVerticalAncestor() async {
            // Root is horizontal; height must locate the nested vertical tile container.
            var window1: Window!
            var window2: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 4)
                    window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 4)
                }
            }
            _ = window1.focusWindow()

            await parseCommand("resize height +2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            // 1079 / 2 = 539.5 each. diff = +2, childDiff = 2 / (2 - 1) = 2
            assertEquals(window1.vWeight, 541.5)
            assertEquals(window2.vWeight, 537.5)
        }

        @Test func testSmart_usesImmediateParentOrientation() async {
            // .smart resizes along the immediate tile container's axis, even when an ancestor
            // would also qualify.
            var window1: Window!
            var window2: Window!
            var sibling: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 4).apply {
                    window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 4)
                    window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 4)
                }
                sibling = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 4)
            }
            _ = window1.focusWindow()

            await parseCommand("resize smart +2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            // immediate parent is vertical; resize is along .v
            assertEquals(window1.vWeight, 541.5)
            assertEquals(window2.vWeight, 537.5)
            // The horizontal sibling at the root is untouched.
            assertEquals(sibling.hWeight, 960)
        }

        @Test func testSmartOpposite_resizesAncestorContainer() async {
            // .smart-opposite resolves to the opposite axis (.h here) and climbs to the
            // ancestor tile container with that orientation. That ancestor's child — the
            // intermediate vertical container — is the node that gets resized.
            var verticalContainer: TilingContainer!
            var sibling: Window!
            var inner: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                verticalContainer = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 4).apply {
                    inner = TestWindow.new(id: 1, parent: $0)
                    TestWindow.new(id: 2, parent: $0)
                }
                sibling = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 4)
            }
            _ = inner.focusWindow()

            await parseCommand("resize smart-opposite +2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            // diff = +2 along .h; root has 2 children, childDiff = 2
            assertEquals(verticalContainer.hWeight, 962)
            assertEquals(sibling.hWeight, 958)
        }

        @Test func testHeight_noVerticalAncestor_returnsFail() async {
            // Root is horizontal; with no vertical container present, height has nothing to resize.
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("resize height +2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2)
        }

        @Test func testSingleChildParent_failsCleanly() async {
            // The root has only one tiling child; dividing the diff across 0 siblings must fail.
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0, adaptiveWeight: 4).focusWindow(), true)
            }

            let result = await parseCommand("resize width +2").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2)
        }

        // MARK: - tiling.min-window-size

        /// Three windows of 640 points in a row. 2 is the focused one
        private func threeWindows() -> [TestWindow] {
            let root = Workspace.get(byName: name).rootTilingContainer
            let windows = (1 ... 3).map { TestWindow.new(id: $0, parent: root, adaptiveWeight: 640) }
            assertEquals(windows[1].focusWindow(), true)
            return windows
        }

        private func resize(_ command: String) async -> Int32 {
            await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue
        }

        @Test func testShrink_stopsAtTheMinimumSize() async {
            let windows = threeWindows()
            assertEquals(await resize("resize width -500"), 0)
            assertEquals(windows.map(\.hWeight), [890, 140, 890])
            // 40 points are left to take. It isn't an error, and it isn't one either when nothing is left
            assertEquals(await resize("resize width -500"), 0)
            assertEquals(windows.map(\.hWeight), [910, 100, 910])
            assertEquals(await resize("resize width -500"), 0)
            assertEquals(windows.map(\.hWeight), [910, 100, 910])
            assertEquals(await resize("resize width 20"), 0)
            assertEquals(windows.map(\.hWeight), [910, 100, 910])
        }

        @Test func testGrow_theSiblingsStopAtTheMinimumSize() async {
            let windows = threeWindows()
            assertEquals(await resize("resize width +1000"), 0)
            assertEquals(windows.map(\.hWeight), [140, 1640, 140])
            assertEquals(await resize("resize width +1000"), 0)
            assertEquals(windows.map(\.hWeight), [100, 1720, 100])
            assertEquals(await resize("resize width 1900"), 0)
            assertEquals(windows.map(\.hWeight), [100, 1720, 100])
        }

        /// A sibling that can't give its part gives what it has, and the other siblings give the rest
        @Test func testGrow_theSiblingsWithRoomGiveWhatTheOthersCant() async {
            let root = Workspace.get(byName: name).rootTilingContainer
            let windows = [150, 400, 1370].enumerated().map { TestWindow.new(id: UInt32($0 + 1), parent: root, adaptiveWeight: $1) }
            assertEquals(windows[1].focusWindow(), true)
            assertEquals(await resize("resize width +300"), 0)
            assertEquals(windows.map(\.hWeight), [100, 700, 1120])
        }

        @Test func testMinWindowSizeFromTheConfig() async {
            config.tiling.minWindowSize = 300
            let windows = threeWindows()
            assertEquals(await resize("resize width -1000"), 0)
            assertEquals(windows.map(\.hWeight), [810, 300, 810])
            assertEquals(await resize("resize width +5000"), 0)
            assertEquals(windows.map(\.hWeight), [300, 1320, 300])
        }

        /// The inner gap is a part of the weight. The limit is the size of the window, not its weight
        @Test func testMinimumSizeIsTheSizeOfTheWindow_withoutTheGap() async throws {
            config.gaps = Gaps(inner: .init(vertical: 0, horizontal: 20), outer: .zero)
            let windows = threeWindows()
            assertEquals(await resize("resize width -1000"), 0)
            assertEquals(windows.map(\.hWeight), [900, 120, 900])
            try await Workspace.get(byName: name).layoutWorkspace()
            assertEquals(windows.map { $0.rect?.width }, [890, 100, 890])

            _ = windows[0].focusWindow()
            assertEquals(await resize("resize width -1000"), 0)
            try await Workspace.get(byName: name).layoutWorkspace()
            assertEquals(windows.map { $0.rect?.width }, [100, 495, 1285])
        }

        /// A window that is already smaller than the minimum isn't made bigger by a resize that asks to shrink it,
        /// and it doesn't give anything to a sibling that grows
        @Test func testWindowsSmallerThanTheMinimumAreLeftAlone() async {
            let root = Workspace.get(byName: name).rootTilingContainer
            let windows = [60, 60, 1800].enumerated().map { TestWindow.new(id: UInt32($0 + 1), parent: root, adaptiveWeight: $1) }
            assertEquals(windows[0].focusWindow(), true)
            assertEquals(await resize("resize width -30"), 0)
            assertEquals(windows.map(\.hWeight), [60, 60, 1800])
            assertEquals(await resize("resize width +30"), 0)
            assertEquals(windows.map(\.hWeight), [90, 60, 1770])
        }

        /// More windows than the monitor has room for with the minimum size: nothing breaks, and nothing can be resized
        @Test func testTooManyWindowsForTheMinimumSize() async throws {
            config.tiling.minWindowSize = 500
            let workspace = Workspace.get(byName: name)
            let windows = (1 ... 8).map { TestWindow.new(id: $0, parent: workspace.rootTilingContainer) }
            assertEquals(windows[3].focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertEquals(windows.map { $0.rect?.width }, Array(repeating: 240, count: 8))
            for command in ["resize width -50", "resize width +50", "resize smart 900"] {
                assertEquals(await resize(command), 0)
                try await workspace.layoutWorkspace()
                assertEquals(windows.map { $0.rect?.width }, Array(repeating: 240, count: 8), additionalMsg: command)
            }
        }

        @Test func testShrinkWeights() {
            assertEquals(shrinkWeights([500, 500], by: 200, minimums: [100, 100]), [400, 400])
            assertEquals(shrinkWeights([150, 500], by: 200, minimums: [100, 100]), [100, 350])
            assertEquals(shrinkWeights([150, 500], by: 2000, minimums: [100, 100]), [100, 100])
            assertEquals(shrinkWeights([150, 500, 120], by: 100, minimums: [100, 100, 110]), [105, 455, 110])
            assertEquals(shrinkWeights([50, 500], by: 100, minimums: [100, 100]), [50, 400])
            assertEquals(shrinkWeights([50, 80], by: 100, minimums: [100, 100]), [50, 80])
            assertEquals(shrinkWeights([500, 500], by: 0, minimums: [100, 100]), [500, 500])
            assertEquals(shrinkWeights([500, 500], by: -50, minimums: [100, 100]), [500, 500])
            assertEquals(shrinkWeights([], by: 50, minimums: []), [])
        }

        // MARK: - Resize with the mouse

        /// h[1, v[2, 3], 4], laid out: 640 points wide each
        private func layOutForTheMouse() async throws -> (Workspace, [UInt32: TestWindow]) {
            let workspace = Workspace.get(byName: name)
            var windows: [UInt32: TestWindow] = [:]
            workspace.rootTilingContainer.apply {
                windows[1] = TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    windows[2] = TestWindow.new(id: 2, parent: $0)
                    windows[3] = TestWindow.new(id: 3, parent: $0)
                }
                windows[4] = TestWindow.new(id: 4, parent: $0)
            }
            try await workspace.layoutWorkspace()
            return (workspace, windows)
        }

        /// The edges of the window are dragged by the given distances. Positive: the window grows on that side
        private func drag(_ window: TestWindow, left: CGFloat = 0, right: CGFloat = 0, down: CGFloat = 0) throws {
            let layoutRect = try #require(window.lastAppliedLayoutPhysicalRect)
            let rect = Rect(
                topLeftX: layoutRect.topLeftX - left,
                topLeftY: layoutRect.topLeftY,
                width: layoutRect.width + left + right,
                height: layoutRect.height + down,
            )
            resizeTilingWindow(window, from: layoutRect, to: rect)
        }

        @Test func testMouse_withinTheLimits() async throws {
            let (workspace, windows) = try await layOutForTheMouse()
            let window2 = try #require(windows[2])
            try drag(window2, right: 100, down: -50)
            try await workspace.layoutWorkspace()
            assertEquals([1, 2, 3, 4].map { windows[$0]?.rect?.width }, [640, 740, 740, 540])
            assertEquals([2, 3].map { windows[$0]?.rect?.height }, [489.5, 589.5])
        }

        @Test func testMouse_theSiblingsStopAtTheMinimumSize() async throws {
            let (workspace, windows) = try await layOutForTheMouse()
            let window2 = try #require(windows[2])
            // The events of a drag come one after another, and all of them are measured from the frame of the last layout
            try drag(window2, right: 300)
            try drag(window2, right: 900)
            try await workspace.layoutWorkspace()
            assertEquals([1, 2, 3, 4].map { windows[$0]?.rect?.width }, [640, 1180, 1180, 100])
        }

        @Test func testMouse_theLeftEdge() async throws {
            let (workspace, windows) = try await layOutForTheMouse()
            try drag(try #require(windows[4]), left: 2000)
            try await workspace.layoutWorkspace()
            // Both siblings on the left give the same
            assertEquals([1, 2, 3, 4].map { windows[$0]?.rect?.width }, [100, 100, 100, 1720])
        }

        @Test func testMouse_theWindowStopsAtTheMinimumSize() async throws {
            let (workspace, windows) = try await layOutForTheMouse()
            let window2 = try #require(windows[2])
            try drag(window2, right: -600, down: -500)
            try await workspace.layoutWorkspace()
            // The column of 2 and 3 is what gets narrower: it stops at the minimum. And so does the height of 2
            assertEquals([1, 2, 3, 4].map { windows[$0]?.rect?.width }, [640, 100, 100, 1180])
            assertEquals([2, 3].map { windows[$0]?.rect?.height }, [100, 979])
        }
    }
}

@testable import AppBundle
import Common
import Foundation
import Testing

// todo write tests
//
// test 1
//     horizontal
//         window1
//         vertical
//             vertical
//                 window2 <-- focused
//             vertical
//                 window5
//                 horizontal
//                     window3
//                     window4
// pre-condition: focus_wrapping force_workspace
// action: focus up
// expected: mru(window3, window4) is focused

extension InlayTests {
    @Suite @MainActor struct FocusCommandTest {
        let name = "FocusCommandTest"

        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            assertTrue(parseCommand("focus --boundaries left").errorOrNil?.contains("Possible values") == true)
            var expected = FocusCmdArgs(rawArgs: [], cardinalOrDfsDirection: .direction(.left))
            expected.rawBoundaries = .workspace
            testParseSingleCommandSucc("focus --boundaries workspace left", expected)

            assertEquals(
                parseCommand("focus --boundaries workspace --boundaries workspace left").errorOrNil,
                "ERROR: Duplicated option '--boundaries'",
            )
            assertEquals(
                parseCommand("focus --window-id 42 --ignore-floating").errorOrNil,
                "--window-id is incompatible with other options",
            )
            assertEquals(
                parseCommand("focus --boundaries all-monitors-outer-frame dfs-next").errorOrNil,
                "(dfs-next|dfs-prev) only supports --boundaries workspace",
            )

            assertEquals(
                parseCommand("focus --window-id 42 --wrap-around").errorOrNil,
                "--window-id is incompatible with other options",
            )
            assertEquals(
                parseCommand("focus left --boundaries-action wrap-around-the-workspace --wrap-around").errorOrNil,
                "ERROR: Conflicting options: --boundaries-action, --wrap-around",
            )
            assertEquals(
                parseCommand("focus dfs-next --fail-if-fullscreen").errorOrNil,
                "--fail-if-fullscreen/--fail-if-macos-native-fullscreen require using (left|down|up|right) argument",
            )
            assertEquals(
                parseCommand("focus --fail-if-macos-native-fullscreen --window-id 42").errorOrNil,
                "--window-id is incompatible with other options",
            )
            assertNil(parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen left").errorOrNil)
        }

        @Test func testFailIfFullscreen() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                let window = TestWindow.new(id: 1, parent: $0)
                assertEquals(window.focusWindow(), true)
                window.isFullscreen = true
                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("focus --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFailIfMacosNativeFullscreen() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                let window = TestWindow.new(id: 1, parent: $0)
                assertEquals(window.focusWindow(), true)
                window.isMacosFullscreenForTest = true

                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("focus --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFailIfFullscreenAllowsRegularWindows() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("focus --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocus() {
            assertEquals(focus.windowOrNil, nil)
            Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusOverFloatingWindows() async {
            assertEquals(focus.windowOrNil, nil)
            Workspace.get(byName: name).floatingWindowsContainer.apply {
                TestWindow.new(id: 1, parent: $0, rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
                assertEquals(TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 10, topLeftY: 10, width: 100, height: 100)).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 20, topLeftY: 20, width: 100, height: 100))
            }

            assertEquals(focus.windowOrNil?.windowId, 2)
            await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 3)
        }

        @Test func testFocusAlongTheContainerOrientation() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)
            await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusAcrossTheContainerOrientation() async {
            Workspace.get(byName: name).apply {
                TestWindow.new(id: 1, parent: $0.rootTilingContainer)
                TestWindow.new(id: 2, parent: $0.rootTilingContainer)
                assertEquals($0.focusWorkspace(), true)
            }

            assertEquals(focus.windowOrNil?.windowId, 2)
            await parseCommand("focus up").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
            await parseCommand("focus down").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusNoWrapping() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)
            await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFocusWrapping() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)
            await parseCommand("focus --boundaries workspace --boundaries-action wrap-around-the-workspace left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testFocusFindMruLeaf() async {
            let workspace = Workspace.get(byName: name)
            var startWindow: Window!
            var window2: Window!
            var window3: Window!
            var unrelatedWindow: Window!
            workspace.rootTilingContainer.apply {
                startWindow = TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        window2 = TestWindow.new(id: 2, parent: $0)
                        unrelatedWindow = TestWindow.new(id: 5, parent: $0)
                    }
                    window3 = TestWindow.new(id: 3, parent: $0)
                }
            }

            assertEquals(workspace.mostRecentWindowRecursive?.windowId, 3) // The latest bound
            _ = startWindow.focusWindow()
            await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 3)

            window2.markAsMostRecentChild()
            _ = startWindow.focusWindow()
            await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)

            window3.markAsMostRecentChild()
            unrelatedWindow.markAsMostRecentChild()
            _ = startWindow.focusWindow()
            await parseCommand("focus right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        /// The layout of dwindle with six windows: two columns, the bottom of each one split in two
        ///
        ///     A (1) | B (2)
        ///     C D   | E F
        ///    (3)(4) |(5)(6)
        @MainActor private func dwindleGrid() -> [UInt32: Window] {
            var windows: [UInt32: Window] = [:]
            Workspace.get(byName: name).rootTilingContainer.apply {
                for (top, bottom) in [(1, [3, 4]), (2, [5, 6])] as [(UInt32, [UInt32])] {
                    TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                        windows[top] = TestWindow.new(id: top, parent: $0)
                        TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                            for id in bottom { windows[id] = TestWindow.new(id: id, parent: $0) }
                        }
                    }
                }
            }
            return windows
        }

        @MainActor private func focusAndCheck(_ direction: CardinalDirection, from start: Window, _ expected: UInt32) async {
            _ = start.focusWindow()
            await parseCommand("focus \(direction.rawValue)").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, expected)
        }

        @Test func testFocusGoesToTheWindowNextToItOnTheScreen() async {
            let windows = dwindleGrid()
            // D was the last one focused of the left column: the tree went from B to D
            windows[4]!.markAsMostRecentChild()
            await focusAndCheck(.left, from: windows[2]!, 1)
            // The tree went from D to the most recent window of the right column, B
            windows[2]!.markAsMostRecentChild()
            await focusAndCheck(.right, from: windows[4]!, 5)
            await focusAndCheck(.up, from: windows[4]!, 1)
            await focusAndCheck(.up, from: windows[6]!, 2)
            await focusAndCheck(.left, from: windows[5]!, 4)
        }

        @Test func testFocusPicksTheMostRecentOfTheWindowsThatTouchIt() async {
            let windows = dwindleGrid()
            windows[4]!.markAsMostRecentChild()
            await focusAndCheck(.down, from: windows[1]!, 4)
            windows[3]!.markAsMostRecentChild()
            await focusAndCheck(.down, from: windows[1]!, 3)
        }

        @Test func testFocusStopsAtTheEdgeOfTheWorkspace() async {
            let windows = dwindleGrid()
            await focusAndCheck(.up, from: windows[2]!, 2)
            await focusAndCheck(.right, from: windows[6]!, 6)
            await focusAndCheck(.left, from: windows[3]!, 3)
        }

        @Test func testFocusFollowsTheWeights() async {
            // The left column is a quarter of the screen: its bottom window faces the top half of the right one too
            var windows: [UInt32: Window] = [:]
            Workspace.get(byName: name).rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    windows[1] = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1)
                    windows[2] = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 3)
                }
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 3).apply {
                    windows[3] = TestWindow.new(id: 3, parent: $0)
                    windows[4] = TestWindow.new(id: 4, parent: $0)
                }
            }
            windows[4]!.markAsMostRecentChild()
            await focusAndCheck(.right, from: windows[1]!, 3) // Only 3 faces 1
            windows[4]!.markAsMostRecentChild()
            await focusAndCheck(.right, from: windows[2]!, 4)
            windows[3]!.markAsMostRecentChild()
            await focusAndCheck(.right, from: windows[2]!, 3)
        }

        @Test func testFocusOutsideOfTheContainer() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                }
            }

            await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFocusOutsideOfTheContainer2() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                }
            }

            await parseCommand("focus left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFocusDfsRelative() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        TestWindow.new(id: 2, parent: $0)
                        TestWindow.new(id: 3, parent: $0)
                    }
                }
                TestWindow.new(id: 4, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)

            await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
            await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 3)
            await parseCommand("focus dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 4)

            await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 3)
            await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 2)
            await parseCommand("focus dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }

        @Test func testFocusDfsRelativeWrapping() async {
            Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            assertEquals(focus.windowOrNil?.windowId, 1)

            assertEquals(await parseCommand("focus --boundaries-action stop dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId, 1)

            assertEquals(await parseCommand("focus --boundaries-action fail dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
            assertEquals(focus.windowOrNil?.windowId, 1)

            assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-prev").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId, 2)

            assertEquals(await parseCommand("focus --boundaries-action stop dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId, 2)

            assertEquals(await parseCommand("focus --boundaries-action fail dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
            assertEquals(focus.windowOrNil?.windowId, 2)

            assertEquals(await parseCommand("focus --boundaries-action wrap-around-the-workspace dfs-next").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId, 1)
        }
    }
}

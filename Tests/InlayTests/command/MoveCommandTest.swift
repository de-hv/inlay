@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct MoveCommandTest {
        let name = "MoveCommandTest"

        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            assertNil(parseCommand("move --fail-if-fullscreen left").errorOrNil)
            assertNil(parseCommand("move --fail-if-macos-native-fullscreen --window-id 1 right").errorOrNil)
        }

        @Test func testFailIfFullscreen() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                let window = TestWindow.new(id: 1, parent: $0)
                assertEquals(window.focusWindow(), true)
                window.isFullscreen = true
                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("move --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2)
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
        }

        @Test func testFailIfMacosNativeFullscreen() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                let window = TestWindow.new(id: 1, parent: $0)
                assertEquals(window.focusWindow(), true)
                window.isMacosFullscreenForTest = true
                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("move --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 2)
            assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
        }

        @Test func testFailIfFullscreenAllowsRegularWindows() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            let result = await parseCommand("move --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0)
            assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
        }

        @Test func testMove_swapWindows() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
            }

            await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
        }

        @Test func testMoveInto_findTopMostContainerWithRightOrientation() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        TestWindow.new(id: 2, parent: $0)
                    }
                }
            }

            await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(0),
                    .h_tiles([
                        .window(1),
                        .h_tiles([
                            .window(2),
                        ]),
                    ]),
                ]),
            )
        }

        @Test func testMove_mru() async {
            var window3: Window!
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0)
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                        TestWindow.new(id: 2, parent: $0)
                        window3 = TestWindow.new(id: 3, parent: $0)
                    }
                    TestWindow.new(id: 4, parent: $0)
                }
            }
            window3.markAsMostRecentChild()

            await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(0),
                    .v_tiles([
                        .h_tiles([
                            .window(1),
                            .window(2),
                            .window(3),
                        ]),
                        .window(4),
                    ]),
                ]),
            )
        }

        @Test func testSwap_preserveWeight() async {
            let root = Workspace.get(byName: name).rootTilingContainer
            let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 1)
            let window2 = TestWindow.new(id: 2, parent: root, adaptiveWeight: 2)
            _ = window2.focusWindow()

            await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(window2.hWeight, 2)
            assertEquals(window1.hWeight, 1)
        }

        @Test func testMoveIn_newWeight() async {
            var window1: Window!
            var window2: Window!
            Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 0, parent: $0, adaptiveWeight: 1)
                window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 2)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
                }
            }
            _ = window1.focusWindow()

            await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(window2.hWeight, 1)
            assertEquals(window2.vWeight, 1)
            assertEquals(window1.vWeight, 1)
            assertEquals(window1.hWeight, 1)
        }

        @Test func testCreateImplicitContainer() async {
            let workspace = Workspace.get(byName: name)
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }

            let result = await parseCommand("move up").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .v_tiles([
                        .window(2),
                        .h_tiles([.window(1), .window(3)]),
                    ]),
                ]),
            )
            assertEquals(result.exitCode.rawValue, 0)
        }

        @Test func testStop_onRootNode() async {
            let workspace = Workspace.get(byName: name)
            workspace.rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }

            let result = await parseCommand("move --boundaries-action stop left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .h_tiles([.window(1), .window(2), .window(3)]),
                ]),
            )
            assertEquals(result.exitCode.rawValue, 0)
        }

        @Test func testStop_onRootNode_withOppositeOrientation() async {
            let workspace = Workspace.get(byName: name)
            workspace.rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }

            let result = await parseCommand("move --boundaries-action stop up").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .h_tiles([.window(1), .window(2), .window(3)]),
                ]),
            )
            assertEquals(result.exitCode.rawValue, 0)
        }

        @Test func testStop_onRootNode_whenNoBoundary() async {
            let workspace = Workspace.get(byName: name)
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }

            let result = await parseCommand("move --boundaries-action stop left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .h_tiles([.window(2), .window(1), .window(3)]),
                ]),
            )
            assertEquals(result.exitCode.rawValue, 0)
        }

        @Test func testStop_onInnerNode() async {
            let workspace = Workspace.get(byName: name)
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                    TestWindow.new(id: 3, parent: $0)
                }
            }

            let result = await parseCommand("move --boundaries-action stop right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .h_tiles([.window(1), .v_tiles([.window(3)]), .window(2)]),
                ]),
            )
            assertEquals(result.exitCode.rawValue, 0)
        }

        @Test func testFail() async {
            let workspace = Workspace.get(byName: name)
            workspace.rootTilingContainer.apply {
                assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }

            let result = await parseCommand("move --boundaries-action fail left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.layoutDescription,
                .workspace([
                    .h_tiles([.window(1), .window(2), .window(3)]),
                ]),
            )
            assertEquals(result.exitCode.rawValue, 2)
        }

        @Test func testMoveOut() async {
            let root = Workspace.get(byName: name).rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0)
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                    TestWindow.new(id: 3, parent: $0)
                    TestWindow.new(id: 4, parent: $0)
                }
            }

            await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                root.layoutDescription,
                .h_tiles([
                    .window(1),
                    .window(2),
                    .v_tiles([
                        .window(3),
                        .window(4),
                    ]),
                ]),
            )
        }

        @Test func testMoveOutWithNormalization_right() async {
            config.enableNormalizationFlattenContainers = true

            let workspace = Workspace.get(byName: name).apply {
                TestWindow.new(id: 1, parent: $0.rootTilingContainer)
                assertEquals(TestWindow.new(id: 2, parent: $0.rootTilingContainer).focusWindow(), true)
            }

            await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([
                    .window(1),
                    .window(2),
                ]),
            )
            assertEquals(focus.windowOrNil?.windowId, 2)
        }

        @Test func testMoveOutWithNormalization_left() async {
            config.enableNormalizationFlattenContainers = true

            let workspace = Workspace.get(byName: name).apply {
                assertEquals(TestWindow.new(id: 1, parent: $0.rootTilingContainer).focusWindow(), true)
                TestWindow.new(id: 2, parent: $0.rootTilingContainer)
            }

            await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([
                    .window(1),
                    .window(2),
                ]),
            )
            assertEquals(focus.windowOrNil?.windowId, 1)
        }
    }
}

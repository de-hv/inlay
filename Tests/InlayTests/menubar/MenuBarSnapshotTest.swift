@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct MenuBarSnapshotTest {
        init() {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
            ServerState.shared.isEnabled = true
            activeMode = mainModeId
            MenuBarStore.shared.onChange = nil
        }

        @Test func testEmptyModel() {
            let snapshot = MenuBarSnapshot.fromModel()
            assertEquals(snapshot, MenuBarSnapshot(
                status: .running,
                workspaces: [.init(name: "setUpWorkspacesForTests", isOccupied: false, isVisible: true)],
                focusedWorkspace: "setUpWorkspacesForTests",
                isFocusedWorkspaceFullscreen: false,
                mode: "main",
                focusedWindow: nil,
            ))
            assertEquals(snapshot.nonMainMode, nil)
        }

        @Test func testWorkspaces() {
            config.persistentWorkspaces = ["1", "2", "3"]
            Workspace.garbageCollectUnusedWorkspaces()
            // All the existing workspaces, whatever monitor they are on. Only the focused one is marked
            TestWindow.new(id: 1, parent: Workspace.get(byName: "2").rootTilingContainer)
            TestWindow.new(id: 2, parent: Workspace.get(byName: "2").rootTilingContainer)
            TestWindow.new(id: 3, parent: Workspace.get(byName: "9").floatingWindowsContainer)
            assertEquals(Workspace.get(byName: "3").focusWorkspace(), true)
            Workspace.garbageCollectUnusedWorkspaces()

            let app = MenuBarSnapshot.App(name: "com.dehv.Inlay.test-app")
            let snapshot = MenuBarSnapshot.fromModel()
            assertEquals(snapshot.workspaces, [
                .init(name: "1", isOccupied: false),
                // An app with several windows is listed once
                .init(name: "2", isOccupied: true, apps: [app]),
                .init(name: "3", isOccupied: false, isVisible: true),
                .init(name: "9", isOccupied: true, apps: [app]),
            ])
            assertEquals(snapshot.focusedWorkspace, "3")
            assertEquals(snapshot.focusedWindow, nil)
        }

        @Test func testFocusedWindow() {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            assertEquals(window.focusWindow(), true)
            var snapshot = MenuBarSnapshot.fromModel()
            assertEquals(snapshot.focusedWindow, .init(isFloating: false, isFullscreen: false))
            assertEquals(snapshot.isFocusedWorkspaceFullscreen, false)

            window.isFullscreen = true
            snapshot = MenuBarSnapshot.fromModel()
            assertEquals(snapshot.focusedWindow, .init(isFloating: false, isFullscreen: true))
            assertEquals(snapshot.isFocusedWorkspaceFullscreen, true)

            window.isFullscreen = false
            let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer)
            assertEquals(floating.focusWindow(), true)
            assertEquals(MenuBarSnapshot.fromModel().focusedWindow, .init(isFloating: true, isFullscreen: false))
        }

        @Test func testFullscreenWindowThatIsNotFocused() {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer).isFullscreen = true
            assertEquals(window.focusWindow(), true)
            let snapshot = MenuBarSnapshot.fromModel()
            assertEquals(snapshot.focusedWindow?.isFullscreen, false)
            assertEquals(snapshot.isFocusedWorkspaceFullscreen, true)
        }

        @Test func testTheSnapshotDoesNotChangeTheTree() {
            // The getters of the workspace create their containers on demand. The snapshot must not
            let workspace = focus.workspace
            assertEquals(workspace.children.count, 0)
            _ = MenuBarSnapshot.fromModel()
            assertEquals(workspace.children.count, 0)
        }

        @Test func testStatusAndMode() async {
            assertEquals(MenuBarSnapshot.fromModel().status, .running)
            ServerState.shared.axPermissionStatus = .waiting
            assertEquals(MenuBarSnapshot.fromModel().status, .needsAccessibility)
            ServerState.shared.axPermissionStatus = .granted

            config.modes["resize"] = Mode(bindings: [:])
            _ = try? await parseCommand("mode resize").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(MenuBarSnapshot.fromModel().mode, "resize")
            assertEquals(MenuBarSnapshot.fromModel().nonMainMode, "resize")

            _ = try? await parseCommand("enable off").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(MenuBarSnapshot.fromModel().status, .paused)
            assertEquals(MenuBarSnapshot.fromModel().mode, nil)
            _ = try? await parseCommand("enable on").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(MenuBarSnapshot.fromModel().status, .running)
            assertEquals(MenuBarSnapshot.fromModel().mode, "main")
        }

        @Test func testPublishOnlyWhenChanged() async {
            var published: [MenuBarState] = []
            MenuBarStore.shared.refresh()
            MenuBarStore.shared.onChange = { published.append($0) }
            defer { MenuBarStore.shared.onChange = nil }

            publishUiState()
            publishUiState()
            assertEquals(published.count, 0)

            // The model
            TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
            publishUiState()
            publishUiState()
            assertEquals(published.count, 1)
            assertEquals(published.last?.snapshot.workspaces.first?.isOccupied, true)

            // The config
            config.menuBar.theme = .square
            publishUiState()
            assertEquals(published.count, 2)
            assertEquals(published.last?.config.theme, .square)

            // The mode publishes on its own, without waiting for the end of the session
            config.modes["resize"] = Mode(bindings: [:])
            _ = try? await parseCommand("mode resize").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(published.count, 3)
            assertEquals(published.last?.snapshot.mode, "resize")
            _ = try? await parseCommand("mode resize").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(published.count, 3)

            // So does the accessibility permission
            ServerState.shared.axPermissionStatus = .waiting
            assertEquals(published.count, 4)
            assertEquals(published.last?.snapshot.status, .needsAccessibility)
            ServerState.shared.axPermissionStatus = .granted
            assertEquals(published.count, 5)
            assertEquals(MenuBarStore.shared.state, published.last)
        }
    }
}

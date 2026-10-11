@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// The borders as they are derived from the tree
    @Suite @MainActor struct BordersSnapshotTest {
        private let accent = Rgba.systemAccent.hex
        private let inactive = "#8E8E9373"

        init() {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
            ServerState.shared.isEnabled = true
            activeMode = mainModeId
            windowIdWithBorderHiddenByMouse = nil
            currentlyManipulatedWithMouseWindowId = nil
        }

        private func summary() -> [String] {
            BordersSnapshot.fromModel().items.map { "\($0.windowId) \($0.color.hex)" }
        }

        @Test func testEmptyModel() {
            assertEquals(BordersSnapshot.fromModel(), .empty)
        }

        @Test func testTilingWindows() async throws {
            let workspace = focus.workspace
            let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            assertEquals(window1.focusWindow(), true)
            // The windows have no frame until they are laid out: there is nothing to draw a border around
            assertEquals(BordersSnapshot.fromModel(), .empty)

            try await workspace.layoutWorkspace()
            let snapshot = BordersSnapshot.fromModel()
            assertEquals(summary(), ["1 \(accent)", "2 \(inactive)"])
            // The frames are the ones the layout gave to the windows
            assertEquals(snapshot.items.map(\.frame), [
                CGRect(x: 0, y: 0, width: 960, height: 1079),
                CGRect(x: 960, y: 0, width: 960, height: 1079),
            ])
            assertEquals(snapshot.items.map(\.width), [4, 4])
            assertEquals(snapshot.items.map(\.cornerRadius), [16, 16])

            // The focus moves: the same borders, the colors swapped
            assertEquals(Window.get(byId: 2)?.focusWindow(), true)
            assertEquals(summary(), ["1 \(inactive)", "2 \(accent)"])
            assertEquals(
                BordersDiff.ops(from: snapshot.items, to: BordersSnapshot.fromModel().items),
                [.recolor(windowId: 1, Rgba(hex: inactive).orDie()), .recolor(windowId: 2, .systemAccent)],
            )
        }

        @Test func testGapsLeaveRoomForTheBorder() async throws {
            config.gaps = Gaps(
                inner: .init(vertical: .constant(14), horizontal: .constant(14)),
                outer: .init(left: .constant(14), bottom: .constant(14), top: .constant(14), right: .constant(14)),
            )
            let workspace = focus.workspace
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            try await workspace.layoutWorkspace()
            let panels = BordersSnapshot.fromModel().items.map { BorderGeometry($0, scale: 2).panelFrame }
            // 14 points of gap, 4 points of border on each side: 6 points of air between the two borders
            assertEquals(panels[1].minX - panels[0].maxX, 6)
            assertEquals(panels[0].minX, 10)
            assertFalse(panels[0].intersects(panels[1]))
        }

        @Test func testFloatingWindow() async throws {
            let workspace = focus.workspace
            let tiling = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(floating.focusWindow(), true)
            // The frame of a floating window is read by the layout pass
            assertEquals(summary(), [])
            try await workspace.layoutWorkspace()
            assertEquals(summary(), ["1 \(inactive)", "2 #BF5AF2"])
            assertEquals(BordersSnapshot.fromModel().items[1].frame, CGRect(x: 100, y: 200, width: 640, height: 480))

            // The floating window loses the focus: it's one more inactive window
            assertEquals(tiling.focusWindow(), true)
            assertEquals(summary(), ["1 \(accent)", "2 \(inactive)"])

            // It was moved: the next layout pass picks the new frame up
            floating.setAxFrame(CGPoint(x: 300, y: 250), nil)
            try await workspace.layoutWorkspace()
            assertEquals(BordersSnapshot.fromModel().items[1].frame, CGRect(x: 300, y: 250, width: 640, height: 480))
        }

        @Test func testModeColor() async throws {
            config.borders.modeColors = ["resize": .rgba(Rgba(hex: "#30D158").orDie())]
            let workspace = focus.workspace
            let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            let floating = TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(window1.focusWindow(), true)
            try await workspace.layoutWorkspace()

            activeMode = "resize"
            assertEquals(summary(), ["1 #30D158", "2 \(inactive)", "3 \(inactive)"])
            // The mode wins over the floating color
            assertEquals(floating.focusWindow(), true)
            assertEquals(summary(), ["1 \(inactive)", "2 \(inactive)", "3 #30D158"])
            // A mode without an entry keeps the normal colors
            activeMode = "service"
            assertEquals(summary(), ["1 \(inactive)", "2 \(inactive)", "3 #BF5AF2"])
        }

        @Test func testFullscreen() async throws {
            let workspace = focus.workspace
            let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 3, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(window1.focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertEquals(summary().count, 3)

            // The fullscreen window has no border, and neither have the tiling windows behind it.
            // The floating window is above it and keeps its border
            window1.isFullscreen = true
            try await workspace.layoutWorkspace()
            assertEquals(summary(), ["3 \(inactive)"])

            window1.isFullscreen = false
            try await workspace.layoutWorkspace()
            assertEquals(summary().count, 3)
        }

        @Test func testFloatingFullscreen() async throws {
            let workspace = focus.workspace
            let floating = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(floating.focusWindow(), true)
            floating.isFullscreen = true
            try await workspace.layoutWorkspace()
            assertEquals(summary(), [])
            // The layout forgets that a floating window is fullscreen, but the window still covers the monitor
            try await workspace.layoutWorkspace()
            assertEquals(summary(), [])
        }

        @Test func testUnconventionalWindows() async throws {
            let workspace = focus.workspace
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let nativeFullscreen = TestWindow.new(id: 2, parent: workspace.macOsNativeFullscreenWindowsContainer)
            let minimized = TestWindow.new(id: 3, parent: macosMinimizedWindowsContainer)
            let hiddenApp = TestWindow.new(id: 4, parent: workspace.macOsNativeHiddenAppsWindowsContainer)
            let popup = TestWindow.new(id: 5, parent: macosPopupWindowsContainer)
            for window in [nativeFullscreen, minimized, hiddenApp, popup] {
                window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 500, height: 500)
                window.lastKnownFloatingRect = Rect(topLeftX: 0, topLeftY: 0, width: 500, height: 500)
            }
            try await workspace.layoutWorkspace()
            assertEquals(summary(), ["1 \(accent)"])
        }

        @Test func testInvisibleWorkspace() async throws {
            let visible = focus.workspace
            let other = Workspace.get(byName: "other")
            TestWindow.new(id: 1, parent: visible.rootTilingContainer)
            TestWindow.new(id: 2, parent: other.rootTilingContainer)
            TestWindow.new(id: 3, parent: other.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            try await visible.layoutWorkspace()
            try await other.layoutWorkspace()
            assertEquals(summary(), ["1 \(accent)"])

            // The other workspace becomes the visible one
            assertEquals(other.focusWorkspace(), true)
            assertEquals(summary().map { $0.prefix(1) }, ["2", "3"])
        }

        @Test func testWindowManipulatedWithMouseHasNoBorder() async throws {
            let workspace = focus.workspace
            let tiling = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(tiling.focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertEquals(summary().count, 2)

            windowIdWithBorderHiddenByMouse = 2 // A floating window is dragged
            assertEquals(summary(), ["1 \(accent)"])
            windowIdWithBorderHiddenByMouse = nil // The mouse button is released
            assertEquals(summary().count, 2)

            currentlyManipulatedWithMouseWindowId = 1 // A tiling window is resized
            assertEquals(summary(), ["2 \(inactive)"])
            currentlyManipulatedWithMouseWindowId = nil
        }

        @Test func testNoBordersWhenInlayDoesNotManageWindows() async throws {
            let workspace = focus.workspace
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            try await workspace.layoutWorkspace()
            assertEquals(summary().count, 1)

            config.borders.enabled = false
            assertEquals(BordersSnapshot.fromModel(), .empty)
            config.borders.enabled = true

            ServerState.shared.isEnabled = false // 'enable off'
            assertEquals(BordersSnapshot.fromModel(), .empty)
            ServerState.shared.isEnabled = true

            ServerState.shared.axPermissionStatus = .waiting
            assertEquals(BordersSnapshot.fromModel(), .empty)
            ServerState.shared.axPermissionStatus = .granted
            assertEquals(summary().count, 1)
        }

        @Test func testOnlyTheActiveWindow() async throws {
            config.borders.inactiveColor = .rgba(Rgba(hex: "#00000000").orDie())
            config.borders.activeColor = .rgba(Rgba(hex: "#D19A66").orDie())
            let workspace = focus.workspace
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            let window2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            assertEquals(window2.focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertEquals(summary(), ["2 #D19A66"])
        }

        @Test func testDerivingTheSnapshotDoesNotChangeTheTree() async throws {
            let workspace = focus.workspace
            TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
            try await workspace.layoutWorkspace()
            let before = workspace.layoutDescription
            assertEquals(BordersSnapshot.fromModel(), BordersSnapshot.fromModel())
            assertEquals(workspace.layoutDescription, before)
        }
    }
}

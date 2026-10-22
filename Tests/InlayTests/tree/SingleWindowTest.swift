@testable import AppBundle
import AppKit
import Common
import Testing

/// A workspace with a single tiling window: 'gaps.smart' and 'borders.hide-when-single'.
/// The test monitor is 1920x1080. The layout takes 1920x1079 (see Workspace.layoutWorkspace)
extension InlayTests {
    @Suite @MainActor struct SingleWindowTest {
        let workspace: Workspace

        init() {
            setUpWorkspacesForTests()
            config.enableNormalizationFlattenContainers = true
            config.enableNormalizationOppositeOrientationForNestedContainers = true
            config.tiling = TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5)
            config.gaps = Gaps(
                inner: .init(vertical: .constant(8), horizontal: .constant(8)),
                outer: .init(left: .constant(8), bottom: .constant(8), top: .constant(8), right: .constant(8)),
            )
            ServerState.shared.axPermissionStatus = .granted
            ServerState.shared.isEnabled = true
            activeMode = mainModeId
            windowIdWithBorderHiddenByMouse = nil
            currentlyManipulatedWithMouseWindowId = nil
            workspace = focus.workspace
        }

        // MARK: - Smart gaps

        @Test func testSmartGaps_aSingleWindowTakesTheWholeScreen_theGapsComeBackWithASecondOne() async throws {
            config.gaps.smart = true
            try await openWindow(1)
            assertRects([1: (0, 0, 1920, 1079)])

            try await openWindow(2)
            assertRects([1: (8, 8, 948, 1063), 2: (964, 8, 948, 1063)])

            try await run("close --window-id 2")
            assertRects([1: (0, 0, 1920, 1079)])
        }

        @Test func testWithoutSmartGaps_aSingleWindowKeepsTheOuterGaps() async throws {
            try await openWindow(1)
            assertRects([1: (8, 8, 1904, 1063)])
        }

        @Test func testSmartGaps_floatingWindowsDontCount() async throws {
            config.gaps.smart = true
            try await openWindow(1)
            TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            try await workspace.layoutWorkspace()
            assertRects([1: (0, 0, 1920, 1079)])
        }

        @Test func testSmartGaps_fullscreenKeepsASingleWindowWithoutGaps() async throws {
            config.gaps.smart = true
            try await openWindow(1)
            try await run("fullscreen")
            assertFrame(1, workspace.workspaceMonitor.visibleRect)

            // With a second window the gaps are back, and fullscreen keeps the outer ones
            try await run("fullscreen off")
            try await openWindow(2)
            try await run("fullscreen")
            assertFrame(2, workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)
        }

        @Test func testSmartGaps_aSingleWindowHasNoBorder() async throws {
            config.gaps.smart = true
            try await openWindow(1)
            // It fills the screen: there are no gaps around it for a border
            assertEquals(BordersSnapshot.fromModel().items, [])

            // With the gaps back, the borders come back
            try await openWindow(2)
            assertEquals(BordersSnapshot.fromModel().items.map(\.frame), [
                CGRect(x: 8, y: 8, width: 948, height: 1063),
                CGRect(x: 964, y: 8, width: 948, height: 1063),
            ])

            try await run("close --window-id 2")
            assertEquals(BordersSnapshot.fromModel().items, [])
        }

        // MARK: - Hide the border of a single window

        @Test func testHideWhenSingle() async throws {
            config.borders.hideWhenSingle = true
            try await openWindow(1)
            assertEquals(BordersSnapshot.fromModel().items, [])

            // A floating window keeps its border, and doesn't make the tiling one less single
            let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(floating.focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertEquals(BordersSnapshot.fromModel().items.map(\.windowId), [2])
            assertEquals(Window.get(byId: 1)?.focusWindow(), true)

            // A second tiling window: both have a border
            try await openWindow(3)
            assertEquals(BordersSnapshot.fromModel().items.map(\.windowId).sorted(), [1, 2, 3])

            try await run("close --window-id 3")
            assertEquals(BordersSnapshot.fromModel().items.map(\.windowId), [2])
        }

        @Test func testHideWhenSingle_alsoInFullscreen() async throws {
            config.borders.hideWhenSingle = true
            try await openWindow(1)
            try await run("fullscreen")
            assertEquals(BordersSnapshot.fromModel().items, [])
        }

        @Test func testWithoutHideWhenSingle_aSingleWindowHasABorder() async throws {
            try await openWindow(1)
            assertEquals(BordersSnapshot.fromModel().items.map(\.frame), [CGRect(x: 8, y: 8, width: 1904, height: 1063)])
        }

        // MARK: - Utils

        private func openWindow(_ id: UInt32) async throws {
            assertEquals(TestWindow.newTiling(id: id, workspace: workspace).focusWindow(), true)
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
        }

        /// Runs the command (it also runs the normalizations, like the real app) and lays the workspace out
        private func run(_ command: String) async throws {
            let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0, additionalMsg: command)
            try await workspace.layoutWorkspace()
        }

        /// The frame of one window
        private func assertFrame(_ id: UInt32, _ expected: Rect, sourceLocation: SourceLocation = #_sourceLocation) {
            guard let actual = (Window.get(byId: id) as? TestWindow)?.rect else {
                Issue.record("Window \(id) isn't laid out", sourceLocation: sourceLocation)
                return
            }
            assertEquals(
                [actual.topLeftX, actual.topLeftY, actual.width, actual.height],
                [expected.topLeftX, expected.topLeftY, expected.width, expected.height],
                sourceLocation: sourceLocation,
            )
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
                assertEquals(
                    [actual.topLeftX, actual.topLeftY, actual.width, actual.height],
                    [expected.0, expected.1, expected.2, expected.3],
                    additionalMsg: "window \(window.windowId)",
                    sourceLocation: sourceLocation,
                )
            }
        }
    }
}

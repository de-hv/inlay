@testable import AppBundle
import AppKit
import Common
import Testing

/// A workspace with a single tiling window, and a fullscreen window: [borders.single-window].
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
            config.borders.singleWindow = SingleWindowBorder()
            windowIdWithBorderHiddenByMouse = nil
            currentlyManipulatedWithMouseWindowId = nil
            workspace = focus.workspace
        }

        // MARK: - A window alone in its workspace

        @Test func testASingleWindowHasTheGapAndTheBorder_theOuterGapsComeBackWithASecondOne() async throws {
            try await openWindow(1)
            assertRects([1: (2, 2, 1916, 1075)])
            assertBorders([1: (CGRect(x: 2, y: 2, width: 1916, height: 1075), 1)])

            try await openWindow(2)
            assertRects([1: (8, 8, 948, 1063), 2: (964, 8, 948, 1063)])
            assertBorders([1: (CGRect(x: 8, y: 8, width: 948, height: 1063), 4), 2: (CGRect(x: 964, y: 8, width: 948, height: 1063), 4)])

            try await run("close --window-id 2")
            assertRects([1: (2, 2, 1916, 1075)])
            assertBorders([1: (CGRect(x: 2, y: 2, width: 1916, height: 1075), 1)])
        }

        @Test func testWithoutIt_aSingleWindowFillsTheScreenWithoutABorder() async throws {
            config.borders.singleWindow.enabled = false
            try await openWindow(1)
            assertRects([1: (0, 0, 1920, 1079)])
            assertBorders([:])
        }

        /// The edge of the screen would cut a border wider than the gap
        @Test func testTheGapIsNeverNarrowerThanTheBorder() async throws {
            config.borders.singleWindow = SingleWindowBorder(enabled: true, width: 6, gap: 2)
            try await openWindow(1)
            assertRects([1: (6, 6, 1908, 1067)])
            assertBorders([1: (CGRect(x: 6, y: 6, width: 1908, height: 1067), 6)])
        }

        @Test func testFloatingWindowsDontCount() async throws {
            try await openWindow(1)
            let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(floating.focusWindow(), true)
            try await workspace.layoutWorkspace()
            assertRects([1: (2, 2, 1916, 1075)])
            // The floating window keeps the border of [borders]
            assertBorders([
                1: (CGRect(x: 2, y: 2, width: 1916, height: 1075), 1),
                2: (CGRect(x: 100, y: 200, width: 640, height: 480), 4),
            ])
        }

        /// The border of a single window takes the colors of the others: not focused, the inactive color
        @Test func testTheColorsOfTheOtherBorders() async throws {
            try await openWindow(1)
            let active = config.borders.activeColor.resolve(auto: .systemAccent, systemAccent: .systemAccent)
            assertEquals(BordersSnapshot.fromModel().items.first?.color, active)
            let floating = TestWindow.new(id: 2, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(floating.focusWindow(), true)
            let inactive = config.borders.inactiveColor.resolve(auto: .systemAccent, systemAccent: .systemAccent)
            assertEquals(BordersSnapshot.fromModel().items.first { $0.windowId == 1 }?.color, inactive)
        }

        // MARK: - Fullscreen

        /// A fullscreen window looks like a window alone in its workspace, whatever the other windows are
        @Test func testFullscreenLooksLikeASingleWindow() async throws {
            try await openWindow(1)
            try await run("fullscreen")
            assertRects([1: (2, 2, 1916, 1075)])
            assertBorders([1: (CGRect(x: 2, y: 2, width: 1916, height: 1075), 1)])

            try await run("fullscreen off")
            try await openWindow(2)
            try await run("fullscreen")
            assertFrame(2, Rect(topLeftX: 2, topLeftY: 2, width: 1916, height: 1075))
            // The windows behind it have no border
            assertBorders([2: (CGRect(x: 2, y: 2, width: 1916, height: 1075), 1)])
        }

        @Test func testFullscreenWithoutIt_fillsTheScreenWithoutABorder() async throws {
            config.borders.singleWindow.enabled = false
            try await openWindow(1)
            try await openWindow(2)
            try await run("fullscreen")
            // Like a window alone in its workspace: one point shorter than the screen (see: layoutFrame)
            assertFrame(2, Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1079))
            assertBorders([:])
        }

        @Test func testFullscreenWithNoOuterGaps_fillsTheScreenWithoutABorder() async throws {
            try await openWindow(1)
            try await openWindow(2)
            try await run("fullscreen --no-outer-gaps")
            assertFrame(2, workspace.workspaceMonitor.visibleRect)
            assertBorders([:])
        }

        /// Fullscreen from the menu runs the commands of the key binding: a floating window is tiled first, so that it
        /// looks like with cmd-alt-ctrl-enter
        @Test func testFullscreenFromTheMenu() async throws {
            assertEquals(MenuBarMenu.layoutCommands(from: .floating, to: .fullscreen), ["layout tiling", "fullscreen"])
            assertEquals(MenuBarMenu.layoutCommands(from: .tiling, to: .fullscreen), ["fullscreen"])
            assertEquals(MenuBarMenu.layoutCommands(from: .fullscreen, to: .tiling), ["fullscreen"])
            assertEquals(MenuBarMenu.layoutCommands(from: .fullscreen, to: .floating), ["fullscreen", "layout floating"])
            assertEquals(MenuBarMenu.layoutCommands(from: .tiling, to: .tiling), [])

            let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: Rect(topLeftX: 100, topLeftY: 200, width: 640, height: 480))
            assertEquals(window.focusWindow(), true)
            for command in MenuBarMenu.layoutCommands(from: .floating, to: .fullscreen) { try await run(command) }
            assertEquals(window.isFullscreen, true)
            assertRects([1: (2, 2, 1916, 1075)])
            assertBorders([1: (CGRect(x: 2, y: 2, width: 1916, height: 1075), 1)])
        }

        // MARK: - The old keys

        @Test func testTheKeysOfThePast() {
            let result = parseConfig("config-version = 2\n[gaps]\nsmart = true\n[borders]\nhide-when-single = true\n")
            assertEquals(result.errors, [])
            assertEquals(result.strWarnings.count, 2, additionalMsg: result.strWarnings.joined(separator: "\n"))
            assertEquals(result.config.borders.singleWindow, SingleWindowBorder())
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

        /// The borders: id -> (frame, width)
        private func assertBorders(_ expected: [UInt32: (CGRect, CGFloat)], sourceLocation: SourceLocation = #_sourceLocation) {
            let items = BordersSnapshot.fromModel().items
            assertEquals(items.map(\.windowId).sorted(), expected.keys.sorted(), sourceLocation: sourceLocation)
            for item in items {
                guard let (frame, width) = expected[item.windowId] else { continue }
                assertEquals(item.frame, frame, additionalMsg: "window \(item.windowId)", sourceLocation: sourceLocation)
                assertEquals(item.width, width, additionalMsg: "window \(item.windowId)", sourceLocation: sourceLocation)
            }
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

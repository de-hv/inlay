@testable import AppBundle
import Common
import Foundation
import Testing

/// The arrangement of the windows that already exist when Inlay starts. See: 'tiling.startup-layout' config option.
/// The test monitor is 1920x1080. The layout takes 1920x1079 (see Workspace.layoutWorkspace)
extension InlayTests {
    @Suite @MainActor struct StartupLayoutTest {
        let workspace: Workspace

        init() {
            setUpWorkspacesForTests()
            // The real defaults. setUpWorkspacesForTests disables the normalizations
            config.enableNormalizationFlattenContainers = true
            config.enableNormalizationOppositeOrientationForNestedContainers = true
            config.tiling = TilingConfig()
            workspace = focus.workspace
        }

        // MARK: - Grid

        @Test func testGrid_from1To9Windows() async throws {
            let w: CGFloat = 1920, h: CGFloat = 1079
            // The windows per row, top to bottom
            let expectedRows: [Int: [Int]] = [
                1: [1], 2: [2], 3: [2, 1], 4: [2, 2], 5: [3, 2], 6: [3, 3], 7: [3, 3, 1], 8: [3, 3, 2], 9: [3, 3, 3],
            ]
            for count in 1 ... 9 {
                try await startWith(count)
                let rows = expectedRows[count].orDie()
                // ceil(sqrt(n)) columns, ceil(n / columns) rows
                let columns = Int(Double(count).squareRoot().rounded(.up))
                assertEquals(rows.max(), columns, additionalMsg: "\(count) windows")
                assertEquals(rows.count, Int((Double(count) / Double(columns)).rounded(.up)), additionalMsg: "\(count) windows")
                assertEquals(rows.reduce(0, +), count)

                var expected: [UInt32: (CGFloat, CGFloat, CGFloat, CGFloat)] = [:]
                var id: UInt32 = 1
                for (rowIndex, windowsInRow) in rows.enumerated() {
                    for column in 0 ..< windowsInRow {
                        // The windows of a row share its width, also in the last row
                        let width = w / CGFloat(windowsInRow), height = h / CGFloat(rows.count)
                        expected[id] = (CGFloat(column) * width, CGFloat(rowIndex) * height, width, height)
                        id += 1
                    }
                }
                assertRects(expected, "\(count) windows")
                assertNormalized(workspace.rootTilingContainer)
            }
        }

        @Test func testGrid_someRectsSpelledOut() async throws {
            try await startWith(3)
            assertRects([1: (0, 0, 960, 539.5), 2: (960, 0, 960, 539.5), 3: (0, 539.5, 1920, 539.5)], "3")
            try await startWith(5)
            assertRects(
                [1: (0, 0, 640, 539.5), 2: (640, 0, 640, 539.5), 3: (1280, 0, 640, 539.5), 4: (0, 539.5, 960, 539.5), 5: (960, 539.5, 960, 539.5)],
                "5",
            )
        }

        @Test func testGrid_treeShape() async throws {
            try await startWith(1)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
            // A single row is a flat horizontal root container
            try await startWith(2)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            // A row of one window is the window itself
            try await startWith(3)
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.h_tiles([.window(1), .window(2)]), .window(3)]))
            try await startWith(7)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .v_tiles([.h_tiles([.window(1), .window(2), .window(3)]), .h_tiles([.window(4), .window(5), .window(6)]), .window(7)]),
            )
            // The normalizations have nothing to change
            let before = workspace.rootTilingContainer.layoutDescription
            workspace.normalizeContainers()
            assertEquals(workspace.rootTilingContainer.layoutDescription, before)
        }

        @Test func testGrid_innerGaps() async throws {
            config.gaps = Gaps(inner: .init(vertical: 10, horizontal: 10), outer: .zero)
            try await startWith(3)
            assertRects([1: (0, 0, 955, 534.5), 2: (965, 0, 955, 534.5), 3: (0, 544.5, 1920, 534.5)], "gaps")
        }

        // MARK: - Row and dwindle

        @Test func testRow() async throws {
            config.tiling.startupLayout = .row
            for count in [1, 2, 5] {
                try await startWith(count)
                assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles((1 ... UInt32(count)).map { .window($0) }))
                let width = 1920 / CGFloat(count)
                var expected: [UInt32: (CGFloat, CGFloat, CGFloat, CGFloat)] = [:]
                for id in 1 ... UInt32(count) { expected[id] = (CGFloat(id - 1) * width, 0, width, 1079) }
                assertRects(expected, "\(count) windows")
            }
        }

        @Test func testDwindle_theWindowsStayWhereTheyWerePlaced() async throws {
            config.tiling.startupLayout = .dwindle
            try await startWith(4)
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .h_tiles([.window(1), .v_tiles([.window(2), .h_tiles([.window(3), .window(4)])])]),
            )
        }

        // MARK: - What is arranged, and when

        @Test func testOnlyOnce_theWindowsOpenedLaterAreNewWindows() async throws {
            try await startWith(4)
            // The most recent window is still the last one that was found. The new window splits it, dwindle style:
            // window 4 is wider than tall, so the new one goes next to it, in its row
            assertEquals(TestWindow.newTiling(id: 5, workspace: workspace).focusWindow(), true)
            StartupArrangement.noteDetected(window(5)) // Nothing is pending: it doesn't count
            StartupArrangement.finish()
            workspace.normalizeContainers()
            assertEquals(
                workspace.rootTilingContainer.layoutDescription,
                .v_tiles([.h_tiles([.window(1), .window(2)]), .h_tiles([.window(3), .window(4), .window(5)])]),
            )
            try await workspace.layoutWorkspace()
            assertRects(
                [1: (0, 0, 960, 539.5), 2: (960, 0, 960, 539.5), 3: (0, 539.5, 960, 539.5), 4: (960, 539.5, 480, 539.5), 5: (1440, 539.5, 480, 539.5)],
                "new window",
            )
        }

        @Test func testEveryWorkspaceIsArrangedOnItsOwn() async throws {
            let other = Workspace.get(byName: "other")
            StartupArrangement.begin()
            for id in 1 ... 3 as ClosedRange<UInt32> { detect(id, in: workspace) }
            for id in 11 ... 14 as ClosedRange<UInt32> { detect(id, in: other) }
            StartupArrangement.finish()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.h_tiles([.window(1), .window(2)]), .window(3)]))
            assertEquals(
                other.rootTilingContainer.layoutDescription,
                .v_tiles([.h_tiles([.window(11), .window(12)]), .h_tiles([.window(13), .window(14)])]),
            )
        }

        /// 'enable on' after a pause: the tree was kept. Only the workspaces that got a window in the meantime are arranged
        @Test func testResume_onlyTheWorkspacesWithNewWindowsAreArranged() async throws {
            let other = Workspace.get(byName: "other")
            for id in 1 ... 3 as ClosedRange<UInt32> { assertEquals(TestWindow.newTiling(id: id, workspace: workspace).focusWindow(), true) }
            for id in 11 ... 13 as ClosedRange<UInt32> { TestWindow.newTiling(id: id, workspace: other) }
            let dwindle = workspace.rootTilingContainer.layoutDescription
            assertEquals(dwindle, .h_tiles([.window(1), .v_tiles([.window(2), .window(3)])]))

            StartupArrangement.begin()
            detect(14, in: other)
            StartupArrangement.finish()
            assertEquals(workspace.rootTilingContainer.layoutDescription, dwindle)
            assertEquals(
                other.rootTilingContainer.layoutDescription,
                .v_tiles([.h_tiles([.window(11), .window(12)]), .h_tiles([.window(13), .window(14)])]),
            )
        }

        @Test func testFloatingWindowsAreLeftAlone_andTheMostRecentWindowsAreKept() async throws {
            StartupArrangement.begin()
            for id in 1 ... 3 as ClosedRange<UInt32> { detect(id, in: workspace) }
            let floating = TestWindow.new(id: 9, parent: workspace.floatingWindowsContainer)
            StartupArrangement.noteDetected(floating)
            window(2).markAsMostRecentChild()
            floating.markAsMostRecentChild()
            StartupArrangement.finish()

            assertEquals(workspace.floatingWindows.map(\.windowId), [9])
            assertEquals(workspace.rootTilingContainer.allLeafWindowsRecursive.map(\.windowId), [1, 2, 3])
            assertEquals(workspace.rootTilingContainer.mostRecentWindowRecursive?.windowId, 2)
            assertEquals(workspace.mostRecentWindowRecursive?.windowId, 9)
        }

        @Test func testAWorkspaceWithOnlyFloatingWindowsIsLeftAlone() async throws {
            StartupArrangement.begin()
            StartupArrangement.noteDetected(TestWindow.new(id: 9, parent: workspace.floatingWindowsContainer))
            StartupArrangement.finish()
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([]))
            assertEquals(workspace.floatingWindows.map(\.windowId), [9])
        }

        // MARK: - The 'on-window-detected' rules

        /// The windows that are already open go to the workspaces of their rules first, and then every workspace
        /// is arranged: not one grid with all of them in the visible workspace
        @Test func testTheRulesRunForTheWindowsThatAreAlreadyOpen() async throws {
            config.onWindowDetected = rules([1: "term", 2: "code", 3: "term", 5: "code", 6: "code", 7: "code", 8: "code"])
            StartupArrangement.begin()
            for id in 1 ... 9 as ClosedRange<UInt32> { try await detectAndRunRules(id) }
            StartupArrangement.finish()

            assertEquals(Workspace.get(byName: "term").rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(3)]))
            assertEquals(
                Workspace.get(byName: "code").rootTilingContainer.layoutDescription,
                .v_tiles([.h_tiles([.window(2), .window(5), .window(6)]), .h_tiles([.window(7), .window(8)])]),
            )
            // The windows without a rule stay in the workspace where they were found
            assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(4), .window(9)]))
        }

        /// A rule can make a window float: it isn't a part of the grid
        @Test func testARuleThatMakesTheWindowFloat() async throws {
            config.onWindowDetected = [
                WindowDetectedCallback(matcher: .command(parseCommand("test %{window-id} = 2").cmdOrDie), rawRun: parseCommand("layout floating").cmdOrDie),
            ]
            StartupArrangement.begin()
            for id in 1 ... 4 as ClosedRange<UInt32> { try await detectAndRunRules(id) }
            StartupArrangement.finish()
            assertEquals(workspace.floatingWindows.map(\.windowId), [2])
            assertEquals(workspace.rootTilingContainer.layoutDescription, .v_tiles([.h_tiles([.window(1), .window(3)]), .window(4)]))
        }

        /// 'enable on': the rules only run for the windows that appeared while Inlay was paused. A window that was
        /// moved away from the workspace of its rule before the pause stays where it was put
        @Test func testResume_theRulesOnlyRunForTheNewWindows() async throws {
            config.onWindowDetected = rules([1: "code", 2: "code", 3: "code"])
            StartupArrangement.begin()
            for id in 1 ... 2 as ClosedRange<UInt32> { try await detectAndRunRules(id) }
            StartupArrangement.finish()
            let code = Workspace.get(byName: "code")
            assertEquals(code.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(2)]))
            // The user moves window 2 somewhere else
            _ = window(2).bindAsFloatingWindow(to: workspace)

            StartupArrangement.begin() // enable on
            try await detectAndRunRules(3)
            StartupArrangement.finish()
            assertEquals(workspace.floatingWindows.map(\.windowId), [2])
            assertEquals(code.rootTilingContainer.layoutDescription, .h_tiles([.window(1), .window(3)]))
        }

        // MARK: - Helpers

        /// A rule per window: the window goes to the workspace
        private func rules(_ workspaces: [UInt32: String]) -> [WindowDetectedCallback] {
            workspaces.sorted { $0.key < $1.key }.map { id, workspace in
                WindowDetectedCallback(
                    matcher: .command(parseCommand("test %{window-id} = \(id)").cmdOrDie),
                    rawRun: parseCommand("move-node-to-workspace \(workspace)").cmdOrDie,
                )
            }
        }

        /// The same as MacWindow.getOrRegister: the window is found in the focused workspace, and then it is registered,
        /// which runs its rules
        private func detectAndRunRules(_ id: UInt32) async throws {
            let window = TestWindow.newTiling(id: id, workspace: workspace)
            assertEquals(window.focusWindow(), true)
            try await window.afterRegistration()
        }

        /// Inlay starts with `count` windows open in the workspace: 1, 2, ... They are found in one refresh session
        private func startWith(_ count: Int) async throws {
            for window in workspace.allLeafWindowsRecursive { window.unbindFromParent() }
            StartupArrangement.begin()
            for id in 1 ... UInt32(count) { detect(id, in: workspace) }
            StartupArrangement.finish()
            workspace.normalizeContainers()
            try await workspace.layoutWorkspace()
        }

        /// The same as MacWindow.getOrRegister: the window is placed like a new one, and noted
        private func detect(_ id: UInt32, in workspace: Workspace) {
            let window = TestWindow.newTiling(id: id, workspace: workspace)
            if workspace == focus.workspace { assertEquals(window.focusWindow(), true) }
            StartupArrangement.noteDetected(window)
        }

        private func window(_ id: UInt32) -> TestWindow {
            Workspace.all.flatMap(\.allLeafWindowsRecursive).first { $0.windowId == id } as! TestWindow
        }

        /// The frames of all the tiling windows of the workspace: id -> (x, y, width, height)
        private func assertRects(
            _ expected: [UInt32: (CGFloat, CGFloat, CGFloat, CGFloat)],
            _ context: String,
            sourceLocation: SourceLocation = #_sourceLocation,
        ) {
            let windows = workspace.rootTilingContainer.allLeafWindowsRecursive
            assertEquals(windows.map(\.windowId).sorted(), expected.keys.sorted(), additionalMsg: context, sourceLocation: sourceLocation)
            for window in windows {
                guard let expected = expected[window.windowId], let actual = (window as! TestWindow).rect else {
                    Issue.record("Window \(window.windowId) isn't laid out (\(context))", sourceLocation: sourceLocation)
                    continue
                }
                let actualArr = [actual.topLeftX, actual.topLeftY, actual.width, actual.height]
                let expectedArr = [expected.0, expected.1, expected.2, expected.3]
                if zip(actualArr, expectedArr).contains(where: { abs($0 - $1) > 0.001 }) {
                    failExpectedActual("\(context), window \(window.windowId): \(expectedArr)", actualArr, sourceLocation: sourceLocation)
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

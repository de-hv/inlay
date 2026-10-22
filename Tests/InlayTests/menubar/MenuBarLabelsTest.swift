@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// The 'labels' theme, and the workspaces grouped by monitor
    @Suite @MainActor struct MenuBarLabelsTest {
        init() { setUpWorkspacesForTests() }

        /// Every character is 7 pt wide, a symbol 12 pt. 'nope' isn't a symbol
        private static func measure(_ string: String, _ font: MenuBarFont) -> CGSize {
            switch font {
                case .symbol: string == "nope" ? .zero : CGSize(width: 12, height: 11)
                default: CGSize(width: 7 * CGFloat(string.count), height: 15)
            }
        }

        private let snapshot = MenuBarSnapshot(
            workspaces: [
                .init(name: "1", isOccupied: true),
                .init(name: "2", isOccupied: true),
                .init(name: "3", isOccupied: false),
            ],
            focusedWorkspace: "2",
        )

        private func layout(_ config: MenuBarConfig, _ snapshot: MenuBarSnapshot? = nil) -> MenuBarLayout {
            MenuBarLayout.make(snapshot ?? self.snapshot, config, measure: Self.measure)
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                config-version = 2
                [menu-bar]
                    theme = 'labels'
                    per-monitor = true
                [menu-bar.labels]
                    1 = 'Terminals'
                    2 = ''
                [menu-bar.symbols]
                    1 = 'terminal'
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.menuBar.theme, .labels)
            assertEquals(result.config.menuBar.perMonitor, true)
            // An empty label is no label
            assertEquals(result.config.menuBar.labels, ["1": "Terminals"])
            assertEquals(result.config.menuBar.symbols, ["1": "terminal"])
            assertEquals(parseConfig("[menu-bar.labels]\n1 = 2\n").errors.count, 1)
        }

        @Test func testLabels() {
            typealias M = MenuBarMetrics
            let config = MenuBarConfig(theme: .labels, labels: ["2": "Code"], symbols: ["1": "terminal", "2": "globe", "3": "nope"])
            let layout = layout(config)
            assertEquals(layout.style, .labels)
            // A symbol, or the name when there is none or it doesn't exist
            assertEquals(layout.cells.map { $0.symbol?.string }, ["terminal", "globe", nil])
            assertEquals(layout.cells[0].frame.width, max(M.chipSide, 12 + 2 * M.chipPadding))
            // The focused one is a pill with its symbol and its label
            assertEquals(layout.cells[1].expanded.map(\.string), ["globe", "Code"])
            assertEquals(layout.cells[1].frame.width, 2 * M.labelPadding + 12 + M.labelSymbolGap + 4 * 7)
            assertEquals(layout.marker?.frame, layout.cells[1].frame)
            // Without a label, the name of the workspace
            let unlabeled = self.layout(config.copy(\.labels, [:]))
            assertEquals(unlabeled.cells[1].expanded.map(\.string), ["globe", "2"])
        }

        /// The labels and the symbols only apply to the labels theme
        @Test func testOtherThemesIgnoreTheLabels() {
            let plain = layout(MenuBarConfig(theme: .pills))
            let labeled = layout(MenuBarConfig(theme: .pills, labels: ["2": "Code"], symbols: ["2": "globe"]))
            assertEquals(labeled, plain)
        }

        @Test func testPerMonitor() {
            typealias M = MenuBarMetrics
            let twoMonitors = MenuBarSnapshot(
                workspaces: [
                    .init(name: "1", isOccupied: true, monitor: 1, isVisible: true),
                    .init(name: "2", isOccupied: true, monitor: 0, isVisible: true),
                    .init(name: "3", isOccupied: false, monitor: 0),
                ],
                focusedWorkspace: "2",
            )
            let grouped = layout(MenuBarConfig(theme: .chips, perMonitor: true), twoMonitors)
            // Monitor by monitor, from left to right
            assertEquals(grouped.cells.map(\.workspace), ["2", "3", "1"])
            assertEquals(grouped.separators.count, 1)
            assertEquals(grouped.cells[2].frame.minX - grouped.cells[1].frame.maxX, M.chipSpacing + M.monitorSeparatorSpace)
            // The other monitor shows 1: a hollow marker on it
            assertEquals(grouped.visibleElsewhere.map(\.frame), [grouped.cells[2].frame])
            // Without the key, nothing changes
            let flat = layout(MenuBarConfig(theme: .chips), twoMonitors)
            assertEquals(flat.cells.map(\.workspace), ["1", "2", "3"])
            assertEquals(flat.separators, [])
            assertEquals(flat.visibleElsewhere, [])
            // A single monitor: no separator, no other visible workspace
            assertEquals(layout(MenuBarConfig(theme: .chips, perMonitor: true)).separators, [])
        }
    }
}

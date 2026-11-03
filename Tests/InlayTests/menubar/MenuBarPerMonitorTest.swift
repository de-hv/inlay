@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// The workspaces grouped by monitor
    @Suite @MainActor struct MenuBarPerMonitorTest {
        init() { setUpWorkspacesForTests() }

        /// Every character is 7 pt wide
        private static func measure(_ string: String, _ font: MenuBarFont) -> CGSize {
            CGSize(width: 7 * CGFloat(string.count), height: 15)
        }

        private let snapshot = MenuBarSnapshot(
            workspaces: [
                .init(name: "1", isOccupied: true),
                .init(name: "2", isOccupied: true),
                .init(name: "3", isOccupied: false),
            ],
            focusedWorkspace: "2",
        )

        /// 2 and 3 on the left monitor, 1 on the right one, which shows it
        private let twoMonitors = MenuBarSnapshot(
            workspaces: [
                .init(name: "1", isOccupied: true, monitor: 1, isVisible: true),
                .init(name: "2", isOccupied: true, monitor: 0, isVisible: true),
                .init(name: "3", isOccupied: false, monitor: 0),
            ],
            focusedWorkspace: "2",
        )

        private func layout(_ config: MenuBarConfig, _ snapshot: MenuBarSnapshot? = nil) -> MenuBarLayout {
            MenuBarLayout.make(snapshot ?? self.snapshot, config, measure: Self.measure)
        }

        @Test func testParse() {
            let result = parseConfig(lua: "return { configVersion = 2, menuBar = { perMonitor = true } }")
            assertEquals(result.errors, [])
            assertEquals(result.config.menuBar.perMonitor, true)
            assertEquals(MenuBarConfig().perMonitor, false)
        }

        @Test func testPerMonitor() {
            typealias M = MenuBarMetrics
            let grouped = layout(MenuBarConfig(theme: .chips, perMonitor: true), twoMonitors)
            // Monitor by monitor, from left to right
            assertEquals(grouped.cells.map(\.workspace), ["2", "3", "1"])
            assertEquals(grouped.separators.count, 1)
            assertEquals(grouped.separators[0].size, CGSize(width: M.monitorSeparatorWidth, height: M.monitorSeparatorHeight))
            assertEquals(grouped.cells[2].frame.minX - grouped.cells[1].frame.maxX, M.chipSpacing + M.monitorSeparatorSpace)
            // The other monitor shows 1: a hollow marker on it
            assertEquals(grouped.cells.map(\.isVisibleElsewhere), [false, false, true])
            assertEquals(grouped.visibleElsewhere.map(\.frame), [grouped.cells[2].frame])
            // Without the key, nothing changes
            let flat = layout(MenuBarConfig(theme: .chips), twoMonitors)
            assertEquals(flat.cells.map(\.workspace), ["1", "2", "3"])
            assertEquals(flat.cells.map(\.isVisibleElsewhere), [false, false, false])
            assertEquals(flat.separators, [])
            assertEquals(flat.visibleElsewhere, [])
            // A single monitor: no separator, no other visible workspace
            assertEquals(layout(MenuBarConfig(theme: .chips, perMonitor: true)).separators, [])
        }

        /// The divider of hypr is bolder, and the workspace that the other monitor shows gets a frame around its name
        @Test func testPerMonitor_hypr() throws {
            typealias M = MenuBarMetrics
            let grouped = layout(MenuBarConfig(theme: .hypr, perMonitor: true), twoMonitors)
            assertEquals(grouped.cells.map(\.workspace), ["2", "3", "1"])
            assertEquals(grouped.cells[2].frame.minX - grouped.cells[1].frame.maxX, M.hyprSeparatorSpace)
            let separator = try #require(grouped.separators.first)
            assertEquals(separator.size, CGSize(width: M.hyprSeparatorWidth, height: M.hyprSeparatorHeight))
            // In the middle of the room between the monitors
            assertEquals(separator.midX, (grouped.cells[1].frame.maxX + grouped.cells[2].frame.minX) / 2)
            let frame = try #require(grouped.visibleElsewhere.first)
            assertEquals(frame.isOutlined, true)
            assertEquals(frame.cornerRadius, M.hyprFrameCornerRadius)
            assertEquals(frame.frame.size, CGSize(width: M.hyprFrame, height: M.hyprFrame))
            // Around the name, which stays in sight
            let name = grouped.cells[2].name.frame
            assertEquals(frame.frame.midX, name.midX)
            assertEquals(frame.frame.minX < name.minX && frame.frame.maxX > name.maxX, true)
        }

        /// dms has no divider: each monitor gets its own track, and the gap between them is the divider
        @Test func testPerMonitor_dms() throws {
            typealias M = MenuBarMetrics
            let grouped = layout(MenuBarConfig(theme: .dms, perMonitor: true), twoMonitors)
            assertEquals(grouped.cells.map(\.workspace), ["2", "3", "1"])
            assertEquals(grouped.separators, [])
            assertEquals(grouped.tracks.count, 2)
            assertEquals(grouped.tracks[1].minX - grouped.tracks[0].maxX, M.dmsTrackGap)
            assertEquals(grouped.tracks[0].maxX, grouped.cells[1].frame.maxX + M.dmsTrackPadding)
            assertEquals(grouped.tracks[1].maxX, grouped.size.width)
            // A ring around the pill that the other monitor shows, inside of its track
            let ring = try #require(grouped.visibleElsewhere.first)
            assertEquals(ring.isOutlined, true)
            assertEquals(ring.frame, grouped.cells[2].frame.insetBy(dx: -2, dy: -2))
            assertEquals(grouped.tracks[1].contains(ring.frame), true)
            // Without the key, one track
            assertEquals(layout(MenuBarConfig(theme: .dms), twoMonitors).tracks.count, 1)
        }
    }
}

@testable import AppBundle
import Common
import Testing

extension InlayTests {
    /// A floating window with its center outside every screen is brought back. See: layoutFloatingWindow
    @Suite @MainActor struct FloatingWindowOffscreenTest {
        init() {
            setUpWorkspacesForTests()
            currentlyManipulatedWithMouseWindowId = nil
        }

        private func layout(_ rect: Rect, hidden: Bool = false) async throws -> Rect? {
            let workspace = focus.workspace
            let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer, rect: rect)
            window.isHiddenInCornerForTest = hidden
            try await workspace.layoutWorkspace()
            return window.rect
        }

        @Test func testWindowFarOffToTheCornerComesBack() async throws {
            let visible = focus.workspace.workspaceMonitor.visibleRect
            let result = try #require(await layout(Rect(topLeftX: visible.maxX + 5000, topLeftY: visible.maxY + 5000, width: 400, height: 300)))
            assertEquals(result.maxX <= visible.maxX, true)
            assertEquals(result.maxY <= visible.maxY, true)
            assertEquals(result.width, 400)
            assertEquals(result.height, 300)
        }

        @Test func testWindowPartlyOffScreenIsLeftAlone() async throws {
            let visible = focus.workspace.workspaceMonitor.visibleRect
            // Its center is on the screen
            let rect = Rect(topLeftX: visible.maxX - 300, topLeftY: visible.minY + 10, width: 400, height: 300)
            let result = try #require(await layout(rect))
            assertEquals(result.topLeftX, rect.topLeftX)
            assertEquals(result.topLeftY, rect.topLeftY)
        }

        @Test func testWindowHiddenInCornerIsLeftAlone() async throws {
            let visible = focus.workspace.workspaceMonitor.visibleRect
            let rect = Rect(topLeftX: visible.maxX + 5000, topLeftY: visible.maxY + 5000, width: 400, height: 300)
            let result = try #require(await layout(rect, hidden: true))
            assertEquals(result.topLeftX, rect.topLeftX)
        }
    }
}

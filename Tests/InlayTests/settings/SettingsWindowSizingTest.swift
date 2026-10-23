@testable import AppBundle
import AppKit
import Common
import Foundation
import Testing

extension InlayTests {
    /// The settings window is never taller than the usable part of the screen, and never leaves it:
    /// on a small screen its tabs scroll. See: SettingsWindowSizing, SettingsPageController
    @Suite @MainActor struct SettingsWindowSizingTest {
        /// A 14" MacBook Pro without the Dock: 1512 x 982 points, minus the menu bar
        private let laptop = CGRect(x: 0, y: 0, width: 1512, height: 944)
        private let chrome: CGFloat = 80

        private func frame(_ current: CGRect, content: CGFloat, visible: CGRect?) -> CGRect {
            SettingsWindowSizing.frame(current: current, chromeHeight: chrome, content: CGSize(width: 600, height: content), visible: visible)
        }

        @Test func testATabThatFitsKeepsTheTopLeftCorner() {
            let current = CGRect(x: 400, y: 300, width: 600, height: 500) // Its top is at 800
            assertEquals(frame(current, content: 620, visible: laptop), CGRect(x: 400, y: 100, width: 600, height: 700))
            assertEquals(frame(current, content: 300, visible: laptop), CGRect(x: 400, y: 420, width: 600, height: 380))
        }

        @Test func testATabThatFitsIsMovedUpWhenItsBottomWouldLeaveTheScreen() {
            let current = CGRect(x: 400, y: 300, width: 600, height: 500)
            // 860 + 80 = 940 fits in 944, but not from a top at 800
            assertEquals(frame(current, content: 860, visible: laptop), CGRect(x: 400, y: 0, width: 600, height: 940))
        }

        /// The bug: the General tab asked for 862 points, 942 with the title bar and the toolbar. The window was
        /// that tall whatever the screen, and it can't be resized
        @Test func testATabTallerThanTheScreenGetsTheHeightOfTheScreen() {
            let withDock = CGRect(x: 0, y: 70, width: 1512, height: 874)
            let current = CGRect(x: 400, y: 300, width: 600, height: 500)
            let result = frame(current, content: 862, visible: withDock)
            assertEquals(result, CGRect(x: 400, y: 70, width: 600, height: 874))
            assertEquals(withDock.contains(result), true)
            // The rest of the tab is reached by scrolling
            assertEquals(result.height - chrome < 862, true)
        }

        @Test func testTheWindowNeverLeavesTheScreen() {
            let small = CGRect(x: 0, y: 60, width: 1280, height: 715)
            for content: CGFloat in [200, 620, 812, 854, 862, 2000] {
                for current in [
                    CGRect(x: 340, y: 100, width: 600, height: 500),
                    CGRect(x: -200, y: -300, width: 600, height: 942), // Left there by a bigger screen
                    CGRect(x: 1100, y: 600, width: 600, height: 892),
                ] {
                    let result = frame(current, content: content, visible: small)
                    assertEquals(small.contains(result), true, additionalMsg: "\(content) \(current) -> \(result)")
                    assertEquals(result.height, min(content + chrome, small.height))
                    assertEquals(result.width, 600)
                }
            }
        }

        @Test func testWithoutAScreenTheWindowIsAsTallAsTheTab() {
            let current = CGRect(x: 400, y: 300, width: 600, height: 500)
            assertEquals(frame(current, content: 862, visible: nil), CGRect(x: 400, y: -142, width: 600, height: 942))
        }

        // MARK: - The real window, never shown

        private func window(visibleHeight: CGFloat) throws -> NSWindow {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
            let text = try String(contentsOf: defaultConfigUrl, encoding: .utf8)
            let model = SettingsModel { .success(.init(url: URL(filePath: "/nonexistent/inlay.toml"), text: text, exists: true)) }
            model.refresh()
            return SettingsWindowController(model: model).makeWindow { _ in CGRect(x: 0, y: 0, width: 1512, height: visibleHeight) }
        }

        @Test func testEveryTabFitsOrScrollsInAWindowThatIsAsTallAsASmallScreen() throws {
            let window = try window(visibleHeight: 600)
            let tabs = try #require(window.contentViewController as? SettingsTabViewController)
            assertEquals(tabs.tabViewItems.map(\.label), ["General", "Appearance", "Windows", "Keyboard", "Changes"])
            var scrolling: [String] = []
            for index in tabs.tabViewItems.indices {
                tabs.selectedTabViewItemIndex = index
                tabs.fitWindow(animate: false)
                window.layoutIfNeeded()
                let label = tabs.tabViewItems[index].label
                let page = try #require(tabs.tabViewItems[index].viewController as? SettingsPageController)
                let scrollView = try #require(page.view as? NSScrollView)
                let form = try #require(scrollView.documentView)
                assertEquals(window.frame.minY >= 0 && window.frame.maxY <= 600, true, additionalMsg: label)
                // The whole form is there, and it starts at its top
                assertEquals(abs(form.frame.height - page.contentSize.height) < 1, true, additionalMsg: label)
                assertEquals(scrollView.contentView.isFlipped, true)
                assertEquals(scrollView.contentView.bounds.origin.y, 0)
                if page.contentSize.height > scrollView.contentView.bounds.height {
                    // Taller than the screen: the window is as tall as the screen, and the tab scrolls
                    assertEquals(window.frame.height, 600, additionalMsg: label)
                    scrolling.append(label)
                } else {
                    // A short page: the window keeps its height, the one of every page, as far as the screen allows
                    assertEquals(window.frame.height, 600, additionalMsg: label)
                }
            }
            // Some tabs are taller than such a screen. Changes is short while nothing has changed
            assertEquals(scrolling.isEmpty, false)
            assertEquals(scrolling.contains("Changes"), false)
        }

        /// The top of a page shows again when asked, wherever the page was scrolled, and a window that gets taller than
        /// the page never leaves its top out of sight
        @Test func testScrollToTop() throws {
            let window = try window(visibleHeight: 600)
            let tabs = try #require(window.contentViewController as? SettingsTabViewController)
            tabs.selectedTabViewItemIndex = 1
            RunLoop.current.run(until: .now.addingTimeInterval(0.1))
            window.layoutIfNeeded()
            let page = try #require(tabs.tabViewItems[1].viewController as? SettingsPageController)
            let scrollView = try #require(page.view as? NSScrollView)
            // Appearance is taller than such a screen: the page scrolls. Scrolled down, as the user would
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
            assertEquals(scrollView.contentView.bounds.origin.y, 120)
            page.scrollToTop()
            RunLoop.current.run(until: .now.addingTimeInterval(0.1))
            assertEquals(scrollView.contentView.bounds.origin.y, 0)

            // Scrolled, and then the window gets taller than the form: the top can't stay out of sight
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
            window.setContentSize(NSSize(width: window.contentLayoutRect.width, height: 3000))
            RunLoop.current.run(until: .now.addingTimeInterval(0.6))
            window.layoutIfNeeded()
            assertEquals(scrollView.contentView.bounds.origin.y, 0)
        }

        /// Going from a tab to another one, the scroll view of the tab fills the window below the toolbar every time
        /// (a gap under the toolbar, or the top of the form under it, otherwise), and the window keeps its height
        @Test func testTheScrollViewFillsTheWindowOnEveryTab() throws {
            let window = try window(visibleHeight: 2000)
            let tabs = try #require(window.contentViewController as? SettingsTabViewController)
            // On the screen, and nothing but the run loop lays it out: like the real window
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            RunLoop.current.run(until: .now.addingTimeInterval(0.2))
            var heights: Set<CGFloat> = []
            for index in [1, 2, 0, 4, 3, 1] {
                tabs.selectedTabViewItemIndex = index
                RunLoop.current.run(until: .now.addingTimeInterval(0.3))
                heights.insert(window.frame.height)
                let label = tabs.tabViewItems[index].label
                let page = try #require(tabs.tabViewItems[index].viewController as? SettingsPageController)
                let scrollView = try #require(page.view as? NSScrollView)
                assertEquals(scrollView.convert(scrollView.bounds, to: nil), window.contentLayoutRect, additionalMsg: label)
                assertEquals(scrollView.contentView.bounds.origin.y, 0, additionalMsg: label)
            }
            assertEquals(heights.count, 1) // The same height for every tab: the window doesn't jump
        }

        /// On a big screen the window has the same height on every page, however tall the page is
        @Test func testOnABigScreenTheWindowHasAFixedHeight() throws {
            let window = try window(visibleHeight: 2000)
            let tabs = try #require(window.contentViewController as? SettingsTabViewController)
            for index in tabs.tabViewItems.indices {
                tabs.selectedTabViewItemIndex = index
                tabs.fitWindow(animate: false)
                window.layoutIfNeeded()
                assertEquals(window.contentLayoutRect.height, settingsContentHeight, additionalMsg: tabs.tabViewItems[index].label)
            }
            let page = try #require(tabs.tabViewItems[0].viewController as? SettingsPageController)
            assertEquals(page.contentSize.width, 600)
        }
    }
}

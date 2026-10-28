@testable import AppBundle
import AppKit
import Common
import HotKey
import Testing

extension InlayTests {
    /// Pressing the menu bar item, and the menu that it opens
    @Suite @MainActor struct MenuBarMenuTest {
        init() {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
        }

        /// The menu as it opens: what it shows, and how the panel lays it out
        private func openMenu() throws -> (card: MenuBarCard, content: MenuBarPanelContent) {
            let card = try #require(MenuBarMenu().update())
            return (card, MenuBarPanelContent(card))
        }

        private func footer(_ content: MenuBarPanelContent) -> [String] {
            content.footer.map(\.title)
        }

        // MARK: - What it shows

        /// What Inlay is doing, the focused window and its workspace, the config, and Inlay itself.
        /// Switching workspaces, focusing or moving windows and the binding modes are for the key bindings
        @Test func testContent() throws {
            let workspace = focus.workspace
            assertEquals(TestWindow.new(id: 1, parent: workspace.rootTilingContainer).focusWindow(), true)
            ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now, url: newUserConfigUrl, errorCount: 0, warningCount: 0, isApplied: true)
            defer { ServerState.shared.lastConfigLoad = nil }

            let (card, content) = try openMenu()
            assertEquals(card.status, .running)
            assertEquals(card.configProblems, nil)
            assertEquals(card.workspace, workspace.name)
            assertEquals(card.windowLayout, .tiling)
            let app = TestApp.shared.name ?? "?"
            assertEquals(content.title, "Workspace \(workspace.name) · \(app)")
            assertEquals(content.details.count, 1)
            assertTrue(content.details[0].hasPrefix("Config reloaded "))
            assertNil(content.problems)
            assertNil(content.prompt)
            // The layout in use is selected, and the arrangements apply to the focused workspace
            assertEquals(content.showsLayouts, true)
            assertEquals(content.windowLayout, .tiling)
            assertEquals(content.canSetLayout, true)
            assertEquals(content.canArrange, true)
            assertEquals(footer(content), ["Reload Config", "Open inlay.toml…", "Settings…", "Pause Inlay-Debug", "Quit Inlay-Debug"])
            assertEquals(content.footer.allSatisfy(\.isEnabled), true)
            // The shortcuts of the menu itself, while it is open
            assertEquals(content.footer.compactMap { $0.action.shortcut }, ["r", ",", "e", "q"])
            assertEquals(MenuBarCardAction.forShortcut("R"), .reloadConfig)
            assertNil(MenuBarCardAction.forShortcut("o"))
        }

        @Test func testArrange() {
            assertEquals(MenuBarCardAction.arrange(.grid).title(MenuBarCard(status: .running, workspace: "1")), "Arrange the Workspace in a Grid")
            assertEquals(WorkspaceArrangement.allCases.map(Strings.Menu.arrangeShort), ["Dwindle", "Grid", "Row"])
        }

        /// A workspace without windows: the layouts of the window are disabled, the arrangements aren't
        @Test func testAnEmptyWorkspace() throws {
            let (card, content) = try openMenu()
            assertEquals(card.windowLayout, nil)
            assertEquals(card.isEnabled(.setLayout(.floating)), false)
            assertEquals(content.canSetLayout, false)
            assertNil(content.windowLayout)
            assertEquals(content.canArrange, true)
            assertEquals(content.title, "Workspace \(focus.workspace.name)")
        }

        /// The binding mode, and the problems of the config: the button shows them all
        @Test func testModeAndProblems() throws {
            config.modes["resize"] = Mode(bindings: [:])
            ServerState.shared.lastConfigLoad = ConfigLoadStatus(
                date: .now, url: newUserConfigUrl, errorCount: 0, warningCount: 1, isApplied: true,
                problems: ["[WARNING] animations.curve: Unknown curve 'bounce2'\nmore"],
            )
            defer { ServerState.shared.lastConfigLoad = nil }
            activeMode = "resize"
            defer { activeMode = mainModeId }
            let (card, content) = try openMenu()
            assertEquals(card.mode, "resize")
            assertEquals(content.details.contains { $0.hasPrefix("Binding mode: resize") }, true)
            assertEquals(content.problems, .init(title: "Config contains warnings…", lines: ["[WARNING] animations.curve: Unknown curve 'bounce2'"]))
            assertEquals(card.isEnabled(.showConfigProblems), true)
        }

        /// The key bindings of the config aren't shown, even when one runs the command of a button
        @Test func testNoKeyBindingsOfTheConfig() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            for (modifiers, key, command) in [(NSEvent.ModifierFlags.option, Key.two, "workspace 2"), ([.option, .shift], .f, "layout floating tiling")] {
                let binding = HotkeyBinding(modifiers, key, parseCommand(command).cmdOrDie)
                config.modes[mainModeId]?.bindings[binding.descriptionWithKeyCode] = binding
            }
            let (_, content) = try openMenu()
            assertEquals(content.footer.compactMap { $0.action.shortcut }, ["r", ",", "e", "q"])
            assertEquals(footer(content).contains { $0.contains("⌥") }, false)
        }

        @Test func testVersion() {
            assertEquals(Strings.Menu.version, "\(inlayAppName) \(inlayAppVersion)")
            assertEquals(Strings.Menu.version.contains(gitHash.prefix(7)), false)
            assertEquals(Strings.Menu.version.lowercased().contains("aerospace"), false)
        }

        @Test func testPausedAndWithoutThePermission() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            ServerState.shared.isEnabled = false
            var (card, content) = try openMenu()
            assertEquals(card.status, .paused)
            assertEquals(card.windowLayout, nil)
            assertEquals(content.title, "Inlay-Debug is paused")
            assertEquals(content.canSetLayout, false)
            assertEquals(content.canArrange, false)
            assertEquals(card.isEnabled(.reloadConfig), false)
            assertEquals(content.footer.filter(\.isEnabled).compactMap { $0.action.shortcut }, [",", "e", "q"])
            assertEquals(footer(content).contains("Resume Inlay-Debug"), true)

            ServerState.shared.isEnabled = true
            ServerState.shared.axPermissionStatus = .waiting
            defer { ServerState.shared.axPermissionStatus = .granted }
            (card, content) = try openMenu()
            assertEquals(card.status, .needsAccessibility)
            // Nothing to do but to grant it, or to quit
            assertEquals(content.title, "Inlay-Debug requires accessibility permission to move windows")
            assertEquals(content.prompt, .promptForAccessibility)
            assertEquals(content.showsLayouts, false)
            assertEquals(footer(content), ["Quit Inlay-Debug"])
        }

        /// A press of the item opens the menu, and closes it while it is open. A press right after a click closed it
        /// is the end of that same click (the item got it through another window of the menu bar): the menu stays closed
        @Test func testThePressToggles() {
            assertEquals(MenuBarMenu.pressOpens(isOpen: false, closedByClickAgo: nil), true)
            assertEquals(MenuBarMenu.pressOpens(isOpen: true, closedByClickAgo: nil), false)
            assertEquals(MenuBarMenu.pressOpens(isOpen: false, closedByClickAgo: 0.1), false)
            assertEquals(MenuBarMenu.pressOpens(isOpen: false, closedByClickAgo: MenuBarMenu.pressAfterClose + 0.1), true)
        }

        /// The first time, the panel has no size yet: the content must still take the size of the panel, not grow
        /// along with it (it was twice as big, and looked moved to the right)
        @Test func testTheContentHasTheSizeOfThePanel() throws {
            _ = NSApplication.shared
            let panel = MenuBarPanel()
            for size in [CGSize(width: 280, height: 320), CGSize(width: 280, height: 260)] {
                let content = NSView()
                panel.setContent(content, size: size)
                let effect = try #require(panel.contentView)
                assertEquals(effect.frame.size, size)
                assertEquals(content.frame, CGRect(origin: .zero, size: size))
                assertEquals(effect.subviews.count, 1)
            }
        }

        /// The button highlights itself while the mouse is down on it. The shield takes the mouse away from the button
        @Test func testClickShield_theButtonNeverSeesTheMouse() throws {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 24), styleMask: [.borderless], backing: .buffered, defer: true)
            let button = RecordingButton(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
            window.contentView?.addSubview(button)
            let shield = MenuBarClickShield(frame: button.bounds)
            shield.autoresizingMask = [.width, .height]
            var clicks = 0
            shield.onClick = { clicks += 1 }
            button.addSubview(shield)

            // The mouse over any point of the button is over the shield, also after the item changes its width
            assertTrue(button.hitTest(NSPoint(x: 5, y: 5)) === shield)
            button.setFrameSize(NSSize(width: 180, height: 24))
            assertEquals(shield.frame, button.bounds)
            assertTrue(button.hitTest(NSPoint(x: 175, y: 20)) === shield)

            func event(_ type: NSEvent.EventType, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
                try #require(NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: 5, y: 5), modifierFlags: modifiers, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
                ))
            }
            // A plain click: the button doesn't hear about it, so it has nothing to highlight
            shield.mouseDown(with: try event(.leftMouseDown))
            assertEquals(clicks, 0)
            shield.mouseUp(with: try event(.leftMouseUp))
            assertEquals(clicks, 1)
            shield.rightMouseDown(with: try event(.rightMouseDown))
            assertEquals(clicks, 1)
            shield.rightMouseUp(with: try event(.rightMouseUp))
            assertEquals(clicks, 2)
            shield.mouseDown(with: try event(.leftMouseDown, .control))
            shield.mouseUp(with: try event(.leftMouseUp, .control))
            assertEquals(clicks, 3)
            assertEquals(button.mouseDowns, 0)
            assertEquals(button.isHighlighted, false)

            // A cmd-drag moves the item along the menu bar: that one is for the button
            shield.mouseDown(with: try event(.leftMouseDown, .command))
            assertEquals(button.mouseDowns, 1)

            // The shield isn't something VoiceOver can land on: the button is still what it finds and presses
            assertEquals(shield.isAccessibilityElement(), false)
        }
    }
}

/// A button that counts the times the mouse went down on it, instead of tracking the mouse
private final class RecordingButton: NSButton {
    var mouseDowns = 0
    override func mouseDown(with event: NSEvent) { mouseDowns += 1 }
}

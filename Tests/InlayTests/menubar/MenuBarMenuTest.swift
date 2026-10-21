@testable import AppBundle
import AppKit
import Common
import HotKey
import SwiftUI
import Testing

extension InlayTests {
    /// Pressing the menu bar item, and the menu that it opens
    @Suite @MainActor struct MenuBarMenuTest {
        init() {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
        }

        /// The menu as it opens: its card, and all its items
        private func openMenu() throws -> (card: MenuBarCard, items: [NSMenuItem]) {
            let menu = MenuBarMenu()
            menu.menuNeedsUpdate(menu.menu)
            return (try #require(menu.card), menu.menu.items)
        }

        // MARK: - The card

        /// The menu is one card: the windows of the focused workspace, the one thing it changes of the focused window,
        /// the config and Inlay itself. Switching workspaces, focusing or moving windows, the layout, the binding
        /// modes and the themes are for the key bindings and the settings window
        @Test func testCard() throws {
            let workspace = focus.workspace
            assertEquals(TestWindow.new(id: 1, parent: workspace.rootTilingContainer).focusWindow(), true)
            _ = Workspace.get(byName: "2")
            config.modes["service"] = Mode(bindings: [:])

            let (card, items) = try openMenu()
            assertEquals(card.status, .running)
            assertEquals(card.configProblems, nil)
            assertEquals(card.workspace, workspace.name)
            assertEquals(card.windows, [MenuBarCard.Window(app: TestApp.shared.name ?? "?", isFocused: true)])
            assertEquals(card.isFloating, false)
            assertEquals(card.isEnabled(.toggleFloating), true)
            assertEquals(card.buttons, [.reloadConfig, .openConfig, .togglePause, .openSettings])
            assertEquals(card.buttons.map { $0.title(card) }, ["Reload Config", "Open inlay.toml…", "Pause Inlay-Debug", "Settings…"])

            // One item that is the card, and the hidden items of the shortcuts. No submenu
            let visible = items.filter { !$0.isHidden }
            assertEquals(visible.count, 1)
            assertTrue(visible.first?.view is NSHostingView<MenuBarCardView>)
            assertEquals(items.filter(\.hasSubmenu).count, 0)
            // The windows are only shown: nothing in the menu focuses one
            assertEquals(items.compactMap { $0.representedObject as? String }, [])
        }

        /// A workspace without windows says so, and there is no window to float
        @Test func testAnEmptyWorkspace() throws {
            let (card, _) = try openMenu()
            assertEquals(card.windows, [])
            assertEquals(card.isFloating, nil)
            assertEquals(card.isEnabled(.toggleFloating), false)
        }

        /// The key bindings of the config aren't shown, even when one runs the command of a button
        @Test func testNoKeyBindingsOfTheConfig() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            _ = Workspace.get(byName: "2")
            for (modifiers, key, command) in [(NSEvent.ModifierFlags.option, Key.two, "workspace 2"), ([.option, .shift], .f, "layout floating tiling")] {
                let binding = HotkeyBinding(modifiers, key, parseCommand(command).cmdOrDie)
                config.modes[mainModeId]?.bindings[binding.descriptionWithKeyCode] = binding
            }

            let (_, items) = try openMenu()
            assertEquals(items.filter { $0.badge != nil }.map(\.title), [])
            // The shortcuts of the menu itself are real: hidden items, that only exist while the menu is open
            let shortcuts = items.filter { !$0.keyEquivalent.isEmpty }
            assertEquals(shortcuts.map { "\($0.title) \($0.keyEquivalent)" }, ["Reload Config r", "Pause Inlay-Debug e", "Settings… ,", "Quit Inlay-Debug q"])
            assertEquals(shortcuts.allSatisfy { $0.isHidden && $0.allowsKeyEquivalentWhenHidden }, true)
        }

        /// Only the name and the version. The commit and the attribution are in the README and in NOTICE.md
        @Test func testVersion() {
            assertEquals(Strings.Menu.version, "\(inlayAppName) \(inlayAppVersion)")
            assertEquals(Strings.Menu.version.contains(gitHash.prefix(7)), false)
            assertEquals(Strings.Menu.version.lowercased().contains("aerospace"), false)
            // What a click on it copies still tells the commit, for a bug report
            assertEquals(Strings.Menu.versionToCopy, "\(inlayAppName) v\(inlayAppVersion) \(gitHash)")
        }

        @Test func testPausedAndWithoutThePermission() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            ServerState.shared.isEnabled = false
            var (card, items) = try openMenu()
            assertEquals(card.status, .paused)
            assertEquals(card.windows, [])
            assertEquals(card.isEnabled(.toggleFloating), false)
            assertEquals(card.buttons.map { $0.title(card) }, ["Reload Config", "Open inlay.toml…", "Resume Inlay-Debug", "Settings…"])
            assertEquals(card.isEnabled(.reloadConfig), false)
            assertEquals(items.filter { !$0.keyEquivalent.isEmpty && $0.isEnabled }.map(\.keyEquivalent), ["e", ",", "q"])

            ServerState.shared.isEnabled = true
            ServerState.shared.axPermissionStatus = .waiting
            defer { ServerState.shared.axPermissionStatus = .granted }
            (card, items) = try openMenu()
            assertEquals(card.status, .needsAccessibility)
            assertEquals(card.windows, [])
            assertEquals(card.buttons, [])
            assertEquals(MenuBarCardAction.promptForAccessibility.title(card), "Inlay-Debug requires accessibility permission to move windows")
            assertEquals(items.filter { !$0.keyEquivalent.isEmpty }.map(\.keyEquivalent), ["q"])
        }

        /// The card has the same width in every state: only its height changes
        @Test func testCardSize() throws {
            _ = NSApplication.shared
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            var heights: [CGFloat] = []
            for isEnabled in [true, false] {
                ServerState.shared.isEnabled = isEnabled
                defer { ServerState.shared.isEnabled = true }
                let (_, items) = try openMenu()
                let view = try #require(items.first?.view)
                assertEquals(view.frame.width, MenuBarCardView.width)
                heights.append(view.frame.height)
            }
            // Paused, the card has no windows and no switch
            assertTrue(heights[0] > heights[1])
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

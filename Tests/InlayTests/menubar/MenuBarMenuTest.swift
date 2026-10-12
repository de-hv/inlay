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

        /// All the items of the menu as it opens, the ones of the submenus included
        private func openMenu() -> [NSMenuItem] {
            let menu = MenuBarMenu()
            menu.menuNeedsUpdate(menu.menu)
            func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
            return items(menu.menu)
        }

        /// The titles as they are read, with the spaces of the workspace rows collapsed
        private func titles(_ items: [NSMenuItem]) -> [String] {
            items.map { $0.isSeparatorItem ? "---" : $0.title.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        }

        // MARK: - The items

        /// The menu is short: the workspaces, the one thing it changes of the focused window, the config and Inlay
        /// itself. Moving windows, the layout and the binding modes are for the key bindings
        @Test func testItems() throws {
            let workspace = focus.workspace
            assertEquals(TestWindow.new(id: 1, parent: workspace.rootTilingContainer).focusWindow(), true)
            _ = Workspace.get(byName: "2")
            config.modes["service"] = Mode(bindings: [:])

            let items = openMenu()
            assertEquals(titles(items), [
                "Workspaces", "2 Empty", "\(workspace.name) \(TestApp.shared.rawAppBundleId ?? "")",
                "---",
                "Float Focused Window",
                "---",
                "Reload Config", "Open inlay.toml…", "Pause Inlay-Debug", "Settings…",
                "---",
                "Inlay-Debug 0.0.0-dev", "Quit Inlay-Debug",
            ])
            // No submenu: the whole menu is what is seen when it opens
            assertEquals(items.filter(\.hasSubmenu).map(\.title), [])
            assertEquals(
                items.compactMap { $0.representedObject as? String },
                ["workspace 2", "workspace \(workspace.name)", "layout floating tiling"],
            )
            assertEquals(items.filter { $0.state == .on }.compactMap { $0.representedObject as? String }, ["workspace \(workspace.name)"])
        }

        /// The rows of the workspaces are text: the name of the workspace and the names of its apps, without icons
        @Test func testWorkspaceRowsHaveNoIcons() {
            let apps = [MenuBarSnapshot.App(name: "Telegram"), MenuBarSnapshot.App(name: "WhatsApp")]
            let occupied = MenuBarMenu.workspaceTitle(.init(name: "4", isOccupied: true, apps: apps))
            assertEquals(occupied.string, "4\u{2003}Telegram, WhatsApp")
            let empty = MenuBarMenu.workspaceTitle(.init(name: "6", isOccupied: false))
            assertEquals(empty.string, "6\u{2003}Empty")
            for title in [occupied, empty] {
                assertEquals(title.containsAttachments, false)
            }
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            assertEquals(openMenu().filter { $0.representedObject as? String == "workspace \(focus.workspace.name)" }.map { $0.image == nil }, [true])
        }

        /// The key bindings of the config aren't shown next to the items, even when one runs the command of the item
        @Test func testNoKeyBindingsOfTheConfig() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            _ = Workspace.get(byName: "2")
            for (modifiers, key, command) in [(NSEvent.ModifierFlags.option, Key.two, "workspace 2"), ([.option, .shift], .f, "layout floating tiling")] {
                let binding = HotkeyBinding(modifiers, key, parseCommand(command).cmdOrDie)
                config.modes[mainModeId]?.bindings[binding.descriptionWithKeyCode] = binding
            }

            let items = openMenu()
            assertEquals(items.filter { $0.badge != nil }.map(\.title), [])
            // No item that runs a command can be chosen with a key
            assertEquals(items.filter { $0.representedObject is String && !$0.keyEquivalent.isEmpty }.map(\.title), [])
            // The shortcuts of the menu itself are real: they only exist while the menu is open
            assertEquals(
                items.filter { !$0.keyEquivalent.isEmpty }.map { "\($0.title) \($0.keyEquivalent)" },
                ["Reload Config r", "Pause Inlay-Debug e", "Settings… ,", "Quit Inlay-Debug q"],
            )
        }

        /// Only the name and the version. The commit and the attribution are in the README and in NOTICE.md
        @Test func testVersion() {
            assertEquals(Strings.Menu.version, "\(inlayAppName) \(inlayAppVersion)")
            assertEquals(Strings.Menu.version.contains(gitHash.prefix(7)), false)
            assertEquals(Strings.Menu.version.lowercased().contains("aerospace"), false)
            // What a click on it copies still tells the commit, for a bug report
            assertEquals(Strings.Menu.versionToCopy, "\(inlayAppName) v\(inlayAppVersion) \(gitHash)")
        }

        @Test func testPausedAndWithoutThePermission() {
            ServerState.shared.isEnabled = false
            assertEquals(titles(openMenu()), [
                "Inlay-Debug is paused",
                "---",
                "Reload Config", "Open inlay.toml…", "Resume Inlay-Debug", "Settings…",
                "---",
                "Inlay-Debug 0.0.0-dev", "Quit Inlay-Debug",
            ])
            ServerState.shared.isEnabled = true
            ServerState.shared.axPermissionStatus = .waiting
            defer { ServerState.shared.axPermissionStatus = .granted }
            assertEquals(titles(openMenu()), [
                "Inlay-Debug requires accessibility permission to move windows",
                "---",
                "Inlay-Debug 0.0.0-dev", "Quit Inlay-Debug",
            ])
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

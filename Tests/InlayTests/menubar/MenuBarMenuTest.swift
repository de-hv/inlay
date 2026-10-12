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

        private func bind(_ modifiers: NSEvent.ModifierFlags, _ key: Key, _ command: String) {
            let binding = HotkeyBinding(modifiers, key, parseCommand(command).cmdOrDie)
            config.modes[mainModeId]?.bindings[binding.descriptionWithKeyCode] = binding
        }

        /// All the items of the menu as it opens, the ones of the submenus included
        private func openMenu() -> [NSMenuItem] {
            let menu = MenuBarMenu()
            menu.menuNeedsUpdate(menu.menu)
            func items(_ menu: NSMenu) -> [NSMenuItem] { menu.items.flatMap { [$0] + ($0.submenu.map(items) ?? []) } }
            return items(menu.menu)
        }

        // MARK: - The key bindings of the main mode in the menu

        @Test func testShortcutText() {
            func text(_ modifiers: NSEvent.ModifierFlags, _ key: Key) -> String {
                HotkeyBinding(modifiers, key, parseCommand("balance-sizes").cmdOrDie).menuText
            }
            assertEquals(text(.option, .one), "⌥1")
            assertEquals(text([.command, .option], .comma), "⌥⌘,")
            // The order of the menus of macOS, whatever the order of the config
            assertEquals(text([.command, .shift, .option, .control], .k), "⌃⌥⇧⌘K")
            assertEquals(text([.option, .shift], .tab), "⌥⇧⇥")
            assertEquals(text(.option, .space), "⌥Space")
            assertEquals(text([.control, .option], .leftArrow), "⌃⌥←")
            assertEquals(text([], .f5), "F5")
            assertEquals(text(.option, .slash), "⌥/")
        }

        @Test func testMainModeShortcut() {
            bind(.option, .two, "workspace 2")
            bind([.option, .shift], .f, "layout floating tiling")
            bind(.option, .b, "balance-sizes; mode main")
            assertEquals(mainModeShortcut(for: "workspace 2"), "⌥2")
            assertEquals(mainModeShortcut(for: "layout floating tiling"), "⌥⇧F")
            // Only a binding that runs exactly the command of the item
            assertEquals(mainModeShortcut(for: "workspace 3"), nil)
            assertEquals(mainModeShortcut(for: "balance-sizes"), nil)
            assertEquals(mainModeShortcut(for: "not a command"), nil)
            // The bindings of the other modes aren't shown: they don't work until the mode is entered
            config.modes["service"] = Mode(bindings: [:])
            let inService = HotkeyBinding([], .r, parseCommand("flatten-workspace-tree").cmdOrDie)
            config.modes["service"]?.bindings[inService.descriptionWithKeyCode] = inService
            assertEquals(mainModeShortcut(for: "flatten-workspace-tree"), nil)
        }

        /// The bindings are shown next to the items, but they aren't key equivalents: with the menu open,
        /// pressing one doesn't choose the item. A key equivalent is the only way a menu matches a key to an item
        @Test func testShortcutsAreOnlyText() throws {
            let workspace = focus.workspace
            assertEquals(TestWindow.new(id: 1, parent: workspace.rootTilingContainer).focusWindow(), true)
            _ = Workspace.get(byName: "2")
            bind(.option, .two, "workspace 2")
            bind([.option, .shift], .two, "move-node-to-workspace 2")
            bind([.command, .option], .comma, "balance-sizes")
            bind([.option, .shift], .f, "layout floating tiling")

            let items = openMenu()
            func item(_ command: String) throws -> NSMenuItem {
                try #require(items.first { $0.representedObject as? String == command }, "\(command)")
            }
            assertEquals(try item("workspace 2").badge?.stringValue, "⌥2")
            assertEquals(try item("move-node-to-workspace 2").badge?.stringValue, "⌥⇧2")
            assertEquals(try item("balance-sizes").badge?.stringValue, "⌥⌘,")
            assertEquals(try item("layout floating tiling").badge?.stringValue, "⌥⇧F")
            // No binding, no badge
            assertNil(try item("fullscreen").badge)
            assertNil(try item("workspace \(workspace.name)").badge)

            // No item that runs a command can be chosen with a key
            let commandItems = items.filter { $0.representedObject is String }
            assertEquals(commandItems.count > 8, true)
            assertEquals(commandItems.filter { !$0.keyEquivalent.isEmpty }.map(\.title), [])
            // The shortcuts of the menu itself are still real: they only exist while the menu is open
            assertEquals(
                items.filter { !$0.keyEquivalent.isEmpty }.map { "\($0.title) \($0.keyEquivalent)" },
                ["Reload Config r", "Pause Inlay-Debug e", "Settings… ,", "Quit Inlay-Debug q"],
            )
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

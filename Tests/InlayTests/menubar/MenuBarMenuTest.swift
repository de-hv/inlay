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

        /// The menu as it opens: what it shows, and its items
        private func openMenu() throws -> (card: MenuBarCard, items: [NSMenuItem]) {
            let menu = MenuBarMenu()
            menu.menuNeedsUpdate(menu.menu)
            return (try #require(menu.card), menu.menu.items)
        }

        private func titles(_ items: [NSMenuItem]) -> [String] {
            items.map { $0.isSeparatorItem ? "---" : $0.title }
        }

        // MARK: - The items

        /// Native items: what Inlay is doing, the focused window in a submenu, the config, and Inlay itself.
        /// Switching workspaces, focusing or moving windows and the binding modes are for the key bindings
        @Test func testItems() throws {
            let workspace = focus.workspace
            assertEquals(TestWindow.new(id: 1, parent: workspace.rootTilingContainer).focusWindow(), true)
            ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now, url: newUserConfigUrl, errorCount: 0, warningCount: 0, isApplied: true)
            defer { ServerState.shared.lastConfigLoad = nil }

            let (card, items) = try openMenu()
            assertEquals(card.status, .running)
            assertEquals(card.configProblems, nil)
            assertEquals(card.workspace, workspace.name)
            assertEquals(card.windowLayout, .tiling)
            let app = TestApp.shared.name ?? "?"
            assertEquals(titles(items), [
                "Workspace \(workspace.name) · \(app)",
                titles(items)[1], // "Config reloaded <when>"
                "---",
                "Window",
                "---",
                "Reload Config", "Open inlay.toml…", "Settings…",
                "---",
                "Pause Inlay-Debug", "Quit Inlay-Debug",
            ])
            assertTrue(items[1].title.hasPrefix("Config reloaded "))
            // The information isn't an action
            assertEquals(items[0].isEnabled, false)
            assertEquals(items[1].isEnabled, false)
            // The shortcuts of the menu itself
            assertEquals(items.filter { !$0.keyEquivalent.isEmpty }.map { "\($0.title) \($0.keyEquivalent)" }, [
                "Reload Config r", "Settings… ,", "Pause Inlay-Debug e", "Quit Inlay-Debug q",
            ])
        }

        /// Window ▸: the app of the focused window, and its layout checked
        @Test func testWindowSubmenu() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            let (_, items) = try openMenu()
            let window = try #require(items.first { $0.title == "Window" })
            assertEquals(window.isEnabled, true)
            let submenu = try #require(window.submenu)
            assertEquals(titles(submenu.items), [TestApp.shared.name ?? "?", "---", "Tiling", "Floating", "Fullscreen"])
            assertEquals(submenu.items.map(\.state), [.off, .off, .on, .off, .off])
            assertEquals(submenu.items[0].isEnabled, false)
            assertEquals(submenu.items[2 ... 4].allSatisfy(\.isEnabled), true)
        }

        /// A workspace without windows: the submenu is disabled
        @Test func testAnEmptyWorkspace() throws {
            let (card, items) = try openMenu()
            assertEquals(card.windowLayout, nil)
            assertEquals(card.isEnabled(.setLayout(.floating)), false)
            assertEquals(items.first { $0.title == "Window" }?.isEnabled, false)
            assertEquals(items.first?.title, "Workspace \(focus.workspace.name)")
        }

        /// The binding mode, and the problems of the config as items: the first one shows them all
        @Test func testModeAndProblems() throws {
            config.modes["resize"] = Mode(bindings: [:])
            ServerState.shared.lastConfigLoad = ConfigLoadStatus(
                date: .now, url: newUserConfigUrl, errorCount: 0, warningCount: 1, isApplied: true,
                problems: ["[WARNING] animations.curve: Unknown curve 'bounce2'\nmore"],
            )
            defer { ServerState.shared.lastConfigLoad = nil }
            activeMode = "resize"
            defer { activeMode = mainModeId }
            let (card, items) = try openMenu()
            assertEquals(card.mode, "resize")
            assertEquals(items.contains { $0.title.hasPrefix("Binding mode: resize") }, true)
            let problems = try #require(items.first { $0.title == "Config contains warnings…" })
            assertEquals(problems.isEnabled, true)
            let line = try #require(items.first { $0.title == "[WARNING] animations.curve: Unknown curve 'bounce2'" })
            assertEquals(line.indentationLevel, 1)
        }

        /// The key bindings of the config aren't shown, even when one runs the command of an item
        @Test func testNoKeyBindingsOfTheConfig() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            for (modifiers, key, command) in [(NSEvent.ModifierFlags.option, Key.two, "workspace 2"), ([.option, .shift], .f, "layout floating tiling")] {
                let binding = HotkeyBinding(modifiers, key, parseCommand(command).cmdOrDie)
                config.modes[mainModeId]?.bindings[binding.descriptionWithKeyCode] = binding
            }
            let (_, items) = try openMenu()
            let all = items + items.compactMap(\.submenu).flatMap(\.items)
            assertEquals(all.filter { $0.badge != nil }.map(\.title), [])
            assertEquals(all.filter { !$0.keyEquivalent.isEmpty }.map(\.keyEquivalent), ["r", ",", "e", "q"])
        }

        @Test func testVersion() {
            assertEquals(Strings.Menu.version, "\(inlayAppName) \(inlayAppVersion)")
            assertEquals(Strings.Menu.version.contains(gitHash.prefix(7)), false)
            assertEquals(Strings.Menu.version.lowercased().contains("aerospace"), false)
        }

        @Test func testPausedAndWithoutThePermission() throws {
            assertEquals(TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer).focusWindow(), true)
            ServerState.shared.isEnabled = false
            var (card, items) = try openMenu()
            assertEquals(card.status, .paused)
            assertEquals(card.windowLayout, nil)
            assertEquals(items.first?.title, "Inlay-Debug is paused")
            assertEquals(items.first { $0.title == "Window" }?.isEnabled, false)
            assertEquals(card.isEnabled(.reloadConfig), false)
            assertEquals(items.filter { !$0.keyEquivalent.isEmpty && $0.isEnabled }.map(\.keyEquivalent), [",", "e", "q"])
            assertEquals(items.contains { $0.title == "Resume Inlay-Debug" }, true)

            ServerState.shared.isEnabled = true
            ServerState.shared.axPermissionStatus = .waiting
            defer { ServerState.shared.axPermissionStatus = .granted }
            (card, items) = try openMenu()
            assertEquals(card.status, .needsAccessibility)
            // Nothing to do but to grant it, or to quit
            assertEquals(titles(items), ["Inlay-Debug requires accessibility permission to move windows", "---", "Quit Inlay-Debug"])
            assertEquals(items[0].isEnabled, true)
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

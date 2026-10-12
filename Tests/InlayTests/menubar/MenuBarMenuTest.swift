@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// Pressing the menu bar item, and the menu that it opens
    @Suite @MainActor struct MenuBarMenuTest {
        init() { setUpWorkspacesForTests() }

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

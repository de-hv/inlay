import AppKit

@MainActor var currentlyManipulatedWithMouseWindowId: UInt32? = nil
/// The window that is being moved or resized with the mouse, floating windows included. Its border is hidden
/// until the mouse button is released: the frames arrive late and in bursts, the border would trail behind
@MainActor var windowIdWithBorderHiddenByMouse: UInt32? = nil

/// Called when a move or a resize of the window with the mouse is detected
@MainActor
func hideBorderWhileManipulatedWithMouse(_ window: Window) {
    // The mouse button could have been released while the caller was talking to the accessibility API.
    // The handler of the mouse up event has already run then, and nothing would show the border again
    if isLeftMouseButtonDown { windowIdWithBorderHiddenByMouse = window.windowId }
}

var isLeftMouseButtonDown: Bool { NSEvent.pressedMouseButtons == 1 }

@MainActor
func isManipulatedWithMouse(_ window: Window) async throws -> Bool {
    try await (!window.isHiddenInCorner && // Don't allow to resize/move windows of hidden workspaces
        isLeftMouseButtonDown &&
        (currentlyManipulatedWithMouseWindowId == nil || window.windowId == currentlyManipulatedWithMouseWindowId))
        .andAsync { @Sendable @MainActor in try await getNativeFocusedWindow(.cancellable) == window }
}

/// Same motivation as in monitorFrameNormalized
var mouseLocation: CGPoint { NSEvent.mouseLocation.withYAxisFlipped }

/// Where the mouse cursor is, for the decisions about the tree that depend on it. See: 'tiling.split-target' config option.
/// It's a variable so that the tests can put the cursor wherever they need
@MainActor var cursorLocation: @MainActor () -> CGPoint = { mouseLocation }

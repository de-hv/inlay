import AppKit
import Common

/// The border of one window, with everything resolved: where it is, and how it looks
struct BorderItem: Equatable, Sendable {
    var windowId: UInt32
    /// The frame of the window. The origin is the top left corner of the main screen and Y grows downwards,
    /// the same coordinates as the layout uses. The border is drawn around this frame, outside of it
    var frame: CGRect
    var color: Rgba
    var width: CGFloat
    var cornerRadius: CGFloat
    /// The blur radius of the glow around the border. 0: no glow
    var glowRadius: CGFloat = 0
}

/// What the model knows about a window that may get a border. See: BordersSnapshot.resolve
struct BorderCandidate: Equatable, Sendable {
    var windowId: UInt32
    var frame: CGRect
    var isFocused: Bool = false
    var isFloating: Bool = false
}

/// All the borders to show. A value derived from the model on the main thread. See: publishUiState
struct BordersSnapshot: Equatable, Sendable {
    var items: [BorderItem] = []

    static let empty = BordersSnapshot()

    /// Decides the color of every candidate. Pure.
    ///
    /// The focused window takes the color of the binding mode if the mode has one, otherwise
    /// the floating color if it floats, otherwise the active color. The rest of the windows take the inactive color.
    /// A fully transparent color means that the border isn't drawn at all.
    /// Only the focused window glows, in the color of its border
    static func resolve(_ candidates: [BorderCandidate], _ config: BordersConfig, mode: String?, systemAccent: Rgba) -> BordersSnapshot {
        if !config.enabled { return .empty }
        var seen: Set<UInt32> = []
        var items: [BorderItem] = []
        for candidate in candidates {
            // Thinner than the border itself. It is not a window worth decorating, and it can't be a frame set by the layout
            if candidate.frame.width < 1 || candidate.frame.height < 1 { continue }
            let color: ConfigColor = switch true {
                case !candidate.isFocused: config.inactiveColor
                case mode.flatMap { config.modeColors[$0] } != nil: mode.flatMap { config.modeColors[$0] } ?? config.activeColor
                case candidate.isFloating: config.floatingColor
                default: config.activeColor
            }
            let rgba = color.resolve(auto: systemAccent, systemAccent: systemAccent)
            if rgba.alpha <= 0 { continue }
            if !seen.insert(candidate.windowId).inserted { continue }
            items.append(BorderItem(
                windowId: candidate.windowId,
                frame: candidate.frame,
                color: rgba,
                width: config.width,
                cornerRadius: config.cornerRadius,
                glowRadius: candidate.isFocused && config.glow ? config.glowRadius : 0,
            ))
        }
        return BordersSnapshot(items: items)
    }
}

extension BordersSnapshot {
    /// The windows of the visible workspaces that are on the screen where the layout has put them:
    /// tiling and floating ones. No heuristics: everything comes from the tree.
    ///
    /// Left out: the fullscreen window and the tiling windows that it covers, the windows in the macOS native fullscreen,
    /// the minimized ones, the ones of hidden apps, popups, the windows of the invisible workspaces,
    /// and the window that is being moved or resized with the mouse
    @MainActor
    static func candidatesFromModel() -> [BorderCandidate] {
        let focused = focus.windowOrNil
        var result: [BorderCandidate] = []
        func add(_ window: Window, _ rect: Rect, isFloating: Bool) {
            if window.windowId == windowIdWithBorderHiddenByMouse || window.windowId == currentlyManipulatedWithMouseWindowId { return }
            result.append(BorderCandidate(
                windowId: window.windowId,
                frame: CGRect(x: rect.topLeftX, y: rect.topLeftY, width: rect.width, height: rect.height),
                isFocused: window == focused,
                isFloating: isFloating,
            ))
        }
        for monitor in monitorInfos {
            let workspace = monitor.activeWorkspace
            // The fullscreen window has no lastAppliedLayoutPhysicalRect. The other tiling windows are behind it,
            // but their borders would stick out in the outer gaps
            if workspace.rootTilingContainer.mostRecentWindowRecursive?.isFullscreen != true {
                for window in workspace.rootTilingContainer.allLeafWindowsRecursive {
                    if let rect = window.lastAppliedLayoutPhysicalRect { add(window, rect, isFloating: false) }
                }
            }
            let area = monitor.visibleRectPaddedByOuterGaps
            for window in workspace.floatingWindowsContainer.children.filterIsInstance(of: Window.self) {
                guard let rect = window.lastKnownFloatingRect else { continue }
                // A floating window that was made fullscreen
                let coversMonitor = rect.minX <= area.minX && rect.minY <= area.minY && rect.maxX >= area.maxX && rect.maxY >= area.maxY
                if !coversMonitor { add(window, rect, isFloating: true) }
            }
        }
        return result
    }

    @MainActor
    static func fromModel() -> BordersSnapshot {
        let state = ServerState.shared
        let borders = config.borders
        // Paused ('enable off') or not started yet: Inlay doesn't manage the windows, so it doesn't decorate them
        guard borders.enabled, state.isEnabled, state.axPermissionStatus == .granted else { return .empty }
        return resolve(candidatesFromModel(), borders, mode: activeMode, systemAccent: .systemAccent)
    }
}

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
    /// The border fills the rounded corners of the window, so that the window looks square. See: BorderGeometry
    var squareCorners: Bool = false
    /// The blur radius of the glow around the border. 0: no glow
    var glowRadius: CGFloat = 0
}

/// What the model knows about a window that may get a border. See: BordersSnapshot.resolve
struct BorderCandidate: Equatable, Sendable {
    var windowId: UInt32
    var frame: CGRect
    var isFocused: Bool = false
    var isFloating: Bool = false
    /// The width of its border. nil: the one of [borders]. See: SingleWindowBorder
    var width: CGFloat? = nil
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
                width: candidate.width ?? config.width,
                cornerRadius: config.cornerRadius,
                squareCorners: config.squareCorners,
                glowRadius: candidate.isFocused && config.glow ? config.glowRadius : 0,
            ))
        }
        return BordersSnapshot(items: items)
    }
}

extension BordersSnapshot {
    /// The windows of the visible workspaces that are on the screen where the layout has put them:
    /// the tiling ones, and the normal windows that float. No heuristics of its own: everything comes from the tree,
    /// and from what the window was taken for when it was detected.
    ///
    /// The tiling window alone in its workspace and the fullscreen window have the border of [borders.single-window], in
    /// the gap that the layout leaves around them. Without it (and in fullscreen with --no-outer-gaps) they fill the
    /// screen without a border.
    ///
    /// Left out: the tiling windows that a fullscreen window covers, the windows in the macOS native fullscreen,
    /// the minimized ones, the ones of hidden apps, popups, the dialogs and sheets that float on their own,
    /// the windows of the invisible workspaces, and the window that is being moved or resized with the mouse
    @MainActor
    static func candidatesFromModel() -> [BorderCandidate] {
        let focused = focus.windowOrNil
        var result: [BorderCandidate] = []
        func add(_ window: Window, _ rect: Rect, isFloating: Bool, width: CGFloat? = nil) {
            if window.windowId == windowIdWithBorderHiddenByMouse || window.windowId == currentlyManipulatedWithMouseWindowId { return }
            result.append(BorderCandidate(
                windowId: window.windowId,
                frame: CGRect(x: rect.topLeftX, y: rect.topLeftY, width: rect.width, height: rect.height),
                isFocused: window == focused,
                isFloating: isFloating,
                width: width,
            ))
        }
        let single = config.borders.singleWindow
        /// While the window slides to its frame, the border goes with it. See: WindowAnimator
        func currentRect(_ window: Window) -> Rect? {
            WindowAnimator.shared.currentFrame(window.windowId)
                .map { Rect(topLeftX: $0.minX, topLeftY: $0.minY, width: $0.width, height: $0.height) }
        }
        for monitor in monitorInfos {
            let workspace = monitor.activeWorkspace
            let tiling = workspace.rootTilingContainer.allLeafWindowsRecursive
            // The fullscreen window has no lastAppliedLayoutPhysicalRect: the layout gives it the area of
            // [borders.single-window]. The other tiling windows are behind it, and their borders would stick out
            if let fullscreen = workspace.rootTilingContainer.mostRecentWindowRecursive, fullscreen.isFullscreen {
                if single.enabled && !fullscreen.noOuterGapsInFullscreen {
                    add(fullscreen, currentRect(fullscreen) ?? fullscreen.fullscreenFrame ?? monitor.singleWindowRect, isFloating: false, width: single.width)
                }
            } else if tiling.count == 1, let window = tiling.first {
                if single.enabled, let rect = currentRect(window) ?? window.lastAppliedLayoutPhysicalRect {
                    add(window, rect, isFloating: false, width: single.width)
                }
            } else {
                for window in tiling {
                    if let rect = currentRect(window) ?? window.lastAppliedLayoutPhysicalRect {
                        add(window, rect, isFloating: false)
                    }
                }
            }
            for window in workspace.floatingWindowsContainer.children.filterIsInstance(of: Window.self) {
                // A dialog comes and goes with the window it belongs to. Only the windows that the user sees as windows
                // are decorated. A dialog that the user made a tiling window is in the tiling tree, and it has a border there
                guard window.detectedType != .dialog, let rect = window.lastKnownFloatingRect else { continue }
                // A floating window that was made fullscreen looks like a fullscreen tiling window: [borders.single-window]
                // (the layout gives it the area of a window alone in its workspace, one point shorter: see layoutFullscreen)
                let full = monitor.singleWindowRect
                let coversMonitor = rect.minX <= full.minX && rect.minY <= full.minY && rect.maxX >= full.maxX && rect.maxY >= full.maxY - 1
                if !coversMonitor {
                    add(window, rect, isFloating: true)
                } else if single.enabled {
                    // The border is drawn outside of the frame: around a window that fills the screen it is pulled in
                    add(window, rect.intersection(monitor.visibleRect.insetBy(single.width)), isFloating: true, width: single.width)
                }
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

/// The appearance of the system: dark or light. Dark without an app (the tests)
@MainActor
var isSystemAppearanceDark: Bool {
    guard let app = NSApp else { return true }
    return app.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}

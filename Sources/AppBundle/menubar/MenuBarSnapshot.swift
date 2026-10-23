import Common

/// What the menu bar item and its menu show. A value derived from the model on the main thread
struct MenuBarSnapshot: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case running
        /// 'enable off'
        case paused
        /// The accessibility permission isn't granted yet. Inlay doesn't manage windows
        case needsAccessibility
    }

    struct App: Hashable, Sendable {
        var name: String
    }

    struct Workspace: Equatable, Sendable {
        var name: String
        /// false for a workspace without windows
        var isOccupied: Bool
        /// The apps that have windows in the workspace. An app with several windows is listed once
        var apps: [App] = []
        /// The monitor the workspace is on, or would be shown on: 0 for the leftmost one. See: MenuBarConfig.perMonitor
        var monitor: Int = 0
        /// A monitor shows it. The focused workspace is always visible
        var isVisible: Bool = false
    }

    struct FocusedWindow: Equatable, Sendable {
        var isFloating: Bool
        var isFullscreen: Bool
    }

    var status: Status = .running
    /// All the existing workspaces, in the order of the item. Their monitors are told apart only with 'per-monitor'
    var workspaces: [Workspace]
    var focusedWorkspace: String
    /// One of the windows of the focused workspace is fullscreen
    var isFocusedWorkspaceFullscreen: Bool = false
    /// The binding mode. nil if the key bindings are off (Inlay is paused)
    var mode: String? = mainModeId
    var focusedWindow: FocusedWindow? = nil

    /// The mode to show, if it is worth showing
    var nonMainMode: String? { mode.flatMap { $0 == mainModeId ? nil : $0 } }
}

extension MenuBarSnapshot {
    @MainActor
    static func fromModel() -> MenuBarSnapshot {
        let state = ServerState.shared
        let focus = focus
        let focusedWorkspace = focus.workspace
        let windows = focusedWorkspace.allLeafWindowsRecursive
        let monitors = sortedMonitorInfos.map(\.monitorAppKitNsScreenScreensId)
        let status: Status = switch true {
            case state.axPermissionStatus != .granted: .needsAccessibility
            case !state.isEnabled: .paused
            default: .running
        }
        return MenuBarSnapshot(
            status: status,
            workspaces: AppBundle.Workspace.all.map { workspace in
                MenuBarSnapshot.Workspace(
                    name: workspace.name,
                    isOccupied: !workspace.isEffectivelyEmpty,
                    apps: workspace.allLeafWindowsRecursive
                        .map { App(name: $0.app.name?.takeIf { !$0.isEmpty } ?? $0.app.rawAppBundleId ?? "?") }
                        .toOrderedSet()
                        .elements,
                    monitor: monitors.firstIndex(of: workspace.workspaceMonitor.monitorAppKitNsScreenScreensId) ?? 0,
                    isVisible: workspace.isVisible,
                )
            },
            focusedWorkspace: focusedWorkspace.name,
            isFocusedWorkspaceFullscreen: windows.contains { $0.isFullscreen || $0.parent is MacosFullscreenWindowsContainer },
            mode: activeMode,
            focusedWindow: focus.windowOrNil.map { FocusedWindow(isFloating: $0.isFloating, isFullscreen: $0.isFullscreen) },
        )
    }
}

/// Everything the menu bar item is drawn from
struct MenuBarState: Equatable, Sendable {
    var snapshot: MenuBarSnapshot
    var config: MenuBarConfig
}

/// Keeps the last published state of the menu bar. See: publishUiState
@MainActor
final class MenuBarStore {
    static let shared = MenuBarStore()

    private init() {}

    private(set) var state: MenuBarState? = nil
    /// Called only when the state has changed
    var onChange: (@MainActor (MenuBarState) -> Void)? = nil

    func refresh() {
        let new = MenuBarState(snapshot: .fromModel(), config: config.menuBar)
        if new == state {
            DebugStats.count("menu-bar.snapshot.same")
            return
        }
        DebugStats.count("menu-bar.snapshot.changed")
        state = new
        onChange?(new)
    }
}

@MainActor
func normalizeLayoutReason() async throws {
    for workspace in Workspace.all {
        let windows: [Window] = workspace.allLeafWindowsRecursive
        try await _normalizeLayoutReason(workspace: workspace, windows: windows)
    }
    // A minimized window belongs to no workspace. It goes back to the one it was minimized in, if that is known
    try await _normalizeLayoutReason(workspace: nil, windows: macosMinimizedWindowsContainer.children.filterIsInstance(of: Window.self))
    try await validateStillPopups()
}

@MainActor
private func validateStillPopups() async throws {
    for node in macosPopupWindowsContainer.children {
        let popup = (node as! MacWindow)
        let windowLevel = getWindowLevel(for: popup.windowId)
        if try await popup.isWindowHeuristic(windowLevel, .cancellable) {
            try await popup.relayoutWindow(on: focus.workspace, .cancellable)
            await runOnWindowDetected(ifConventional: popup)
        }
    }
}

/// - Parameter workspace: the workspace of the windows. nil for the minimized windows, which have none
@MainActor
private func _normalizeLayoutReason(workspace: Workspace?, windows: [Window]) async throws {
    // Last out, first in. The windows of an app are hidden and shown together: a window that left its place after
    // another one must take it back before the other one does, or their indexes don't match the tree
    for window in windows.reversed() {
        let isMacosFullscreen = try await window.isMacosFullscreen(.cancellable)
        let isMacosMinimized = try await (!isMacosFullscreen).andAsync { @MainActor @Sendable in try await window.isMacosMinimized(.cancellable) }
        let isMacosWindowOfHiddenApp = !isMacosFullscreen && !isMacosMinimized &&
            !config.automaticallyUnhideMacosHiddenApps && window.macAppUnsafe.nsApp.isHidden
        switch window.layoutReason {
            case .standard:
                guard let parent = window.parent else { continue }
                let workspace = workspace ?? focus.workspace
                let container: NonLeafTreeNodeObject
                switch true {
                    case isMacosFullscreen: container = workspace.macOsNativeFullscreenWindowsContainer
                    case isMacosMinimized: container = macosMinimizedWindowsContainer
                    case isMacosWindowOfHiddenApp: container = workspace.macOsNativeHiddenAppsWindowsContainer
                    default: continue
                }
                window.layoutReason = .macos(prevParentKind: parent.kind)
                window.rememberPlace()
                window.releaseTilingSpaceToNeighbor(temporarily: true)
                window.bind(to: container, adaptiveWeight: WEIGHT_DOESNT_MATTER, index: INDEX_BIND_LAST)
            case .macos(let prevParentKind):
                if !isMacosFullscreen && !isMacosMinimized && !isMacosWindowOfHiddenApp {
                    let home = workspace ?? window.takeWorkspaceBeforeMinimize() ?? focus.workspace
                    try await exitMacOsNativeUnconventionalState(window: window, prevParentKind: prevParentKind, workspace: home, .cancellable)
                    // A minimized window went back to a workspace that isn't the focused one. The focus follows it there:
                    // the user has just asked for the window, and it would be hidden with its workspace otherwise
                    if workspace == nil && home != focus.workspace && window.focusWindow() {
                        window.nativeFocus()
                    }
                }
        }
    }
}

@MainActor
func exitMacOsNativeUnconventionalState(
    window: Window,
    prevParentKind: NonLeafTreeNodeKind,
    workspace: Workspace,
    _ cm: CancellationMode,
) async throws {
    window.layoutReason = .standard
    let slot = window.takeTilingSlot()
    switch prevParentKind {
        case .floatingWindowsContainer:
            window.bindAsFloatingWindow(to: workspace)
        case .workspace:
            break // Not possible
        case .tilingContainer:
            window.rebindAsTilingWindow(on: workspace, restoring: slot)
        case .macosPopupWindowsContainer: // Since the window was minimized/fullscreened it was mistakenly detected as popup. Relayout the window
            try await window.relayoutWindow(on: workspace, cm)
        case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer, .macosHiddenAppsWindowsContainer:
            // macos-native-fullscreen and macos-native-minimize move the window before the refresh session notices its
            // new state. If the window was a tiling one, its place is remembered. Otherwise, just re-layout the window
            if let slot {
                window.rebindAsTilingWindow(on: workspace, restoring: slot)
            } else {
                try await window.relayoutWindow(on: workspace, cm)
            }
    }
}

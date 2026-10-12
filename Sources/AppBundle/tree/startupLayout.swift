import AppKit
import Common

/// Arranges the windows that are already open when Inlay starts to manage the windows: when it starts, and when
/// `enable on` resumes it. See: 'tiling.startup-layout' config option
///
/// The windows found by the first complete refresh session are first placed one after another, like new windows.
/// With a lot of windows in a workspace, dwindle leaves the last ones tiny. So, at the end of that session, the tiling
/// tree of every workspace that got one of those windows is rebuilt as a grid or as a row.
/// The windows that appear later are new windows: 'tiling.new-window-placement' decides about them
@MainActor
enum StartupArrangement {
    private static var isPending = false
    /// The windows registered since `begin`
    private static var detectedWindowIds: Set<UInt32> = []
    /// The windows whose 'on-window-detected' rules are running right now. See: whileDetecting
    private static var detectionsInFlight = 0

    /// Inlay is about to look for the windows that already exist
    static func begin() {
        isPending = true
        detectedWindowIds = []
    }

    /// See: MacWindow.getOrRegister
    static func noteDetected(_ window: Window) {
        if isPending { detectedWindowIds.insert(window.windowId) }
    }

    /// Notes the window, and runs what places it for good: its 'on-window-detected' rules. See: Window.afterRegistration
    ///
    /// The rules suspend (they ask the app for the title of the window), and the refresh sessions interleave: a second
    /// session, started by an app that got activated or by a window that got the focus while the first one is still
    /// going through the windows, takes the registered windows for done and gets to `finish` first. Until the rules of
    /// every window are over, the windows aren't in their workspaces yet, and there is nothing to arrange
    static func whileDetecting<T>(_ window: Window, _ body: @MainActor () async throws -> T) async rethrows -> T {
        noteDetected(window)
        detectionsInFlight += 1
        defer { detectionsInFlight -= 1 }
        return try await body()
    }

    /// A refresh session that went through all the windows is over, and every window is in the workspace and in the
    /// container (tiling, floating, minimized...) it belongs to. Does nothing unless `begin` was called since the last
    /// `finish`, and nothing yet while another session is still placing a window: that session, or the next one, arranges
    static func finish() {
        guard isPending, detectionsInFlight == 0 else { return }
        isPending = false
        let detected = detectedWindowIds
        detectedWindowIds = []
        let layout = config.tiling.startupLayout
        // While Inlay is paused the tree is kept. A workspace that got no window in the meantime keeps its layout
        for workspace in Workspace.all
            where workspace.rootTilingContainer.allLeafWindowsRecursive.contains(where: { detected.contains($0.windowId) })
        {
            workspace.arrangeTilingWindows(layout)
        }
    }
}

extension Workspace {
    /// Rebuilds the tiling tree of the workspace out of its tiling windows, in the order they have in the tree.
    /// All the windows of a row get the same width, and all the rows get the same height.
    ///
    /// The tree is a normalized one: the root container is horizontal for a single row, and vertical with a horizontal
    /// container per row otherwise. A row of one window is the window itself
    @MainActor
    func arrangeTilingWindows(_ layout: StartupLayout) {
        let windows = rootTilingContainer.allLeafWindowsRecursive
        let rows: [[Window]]
        switch layout {
            case .dwindle: return
            case .row: rows = [windows]
            case .grid: rows = gridRows(windows)
        }
        if windows.isEmpty { return }
        // Binding marks every window as the most recent one
        let mostRecentTiling = rootTilingContainer.mostRecentWindowRecursive
        let mostRecent = mostRecentWindowRecursive // It may be a floating window
        for window in windows {
            window.unbindFromParent()
        }
        rootTilingContainer.unbindFromParent() // With the containers that are left empty
        let root = TilingContainer(parent: self, adaptiveWeight: 1, rows.count == 1 ? .h : .v, .tiles, index: INDEX_BIND_LAST)
        for row in rows {
            let parent = rows.count == 1 || row.count == 1 ? root : TilingContainer.newHTiles(parent: root, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            for window in row {
                window.bind(to: parent, adaptiveWeight: 1, index: INDEX_BIND_LAST)
            }
        }
        mostRecentTiling?.markAsMostRecentChild()
        mostRecent?.markAsMostRecentChild()
    }
}

/// ceil(sqrt(n)) columns. The rows are filled from the top: only the last one may have fewer windows
private func gridRows(_ windows: [Window]) -> [[Window]] {
    var columns = 1
    while columns * columns < windows.count { columns += 1 }
    return stride(from: 0, to: windows.count, by: columns).map { Array(windows[$0 ..< min($0 + columns, windows.count)]) }
}

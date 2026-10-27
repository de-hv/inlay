import Common

struct MoveNodeToWorkspaceCommand: Command {
    let args: MoveNodeToWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        guard let window = target.windowOrNil else { return .fail(io.err(noWindowIsFocused)) }
        let subjectWs = window.nodeWorkspace
        let targetWorkspace: Workspace
        switch args.target.val {
            case .relative(let nextPrev):
                guard let subjectWs else { return .fail(io.err("Window \(window.windowId) doesn't belong to any workspace")) }
                let ws = getNextPrevWorkspace(
                    current: subjectWs,
                    isNext: nextPrev == .next,
                    wrapAround: args.wrapAround,
                    stdin: args.useStdin ? io.readStdin() : nil,
                    target: target,
                )
                guard let ws = ws.getOrNil(appendErrorTo: &io.stderr) else { return .fail }
                targetWorkspace = ws
            case .direct(let name):
                targetWorkspace = Workspace.get(byName: name.raw)
        }
        return moveWindowToWorkspace(window, targetWorkspace, io, focusFollowsWindow: args.focusFollowsWindow, failIfNoop: args.failIfNoop)
    }
}

/// - Parameter index: The index of the tiling window in the root container of the target workspace.
///   nil means that the window is placed as a new window of the target workspace. See: 'tiling.new-window-placement' config option
@MainActor
func moveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, _ io: CmdIo, focusFollowsWindow: Bool, failIfNoop: Bool, index: Int? = nil) -> BinaryExitCode {
    if window.nodeWorkspace == targetWorkspace {
        return switch failIfNoop {
            case true: .fail
            case false:
                .succ(io.err("Window '\(window.windowId)' already belongs to workspace '\(targetWorkspace.name)'. Tip: use --fail-if-noop to exit with non-zero code"))
        }
    }
    // A fullscreen window takes a place in the layout of the other workspace, like a new window
    if window.isFullscreen {
        WindowAnimator.shared.requestAnimatedLayout()
        window.isFullscreen = false
    }
    let binding: BindingData
    if window.isFloating {
        binding = BindingData(parent: targetWorkspace.floatingWindowsContainer, adaptiveWeight: WEIGHT_AUTO, index: index ?? INDEX_BIND_LAST)
    } else {
        window.releaseTilingSpaceToNeighbor()
        let dwindle = index == nil && config.tiling.newWindowPlacement == .dwindle
            ? prepareDwindleBindingDataForNewTilingWindow(targetWorkspace, focused: focus.windowOrNil)
            : nil
        binding = dwindle ?? BindingData(parent: targetWorkspace.rootTilingContainer, adaptiveWeight: WEIGHT_AUTO, index: index ?? INDEX_BIND_LAST)
    }
    window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    return .from(bool: focusFollowsWindow ? window.focusWindow() : true)
}

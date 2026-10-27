import AppKit
import Common

/// Rebuilds the tiling tree of the workspace, like 'tiling.startup-layout' does when Inlay starts.
/// Example: a workspace left with a row of windows gets the dwindle tree back
struct ArrangeWorkspaceCommand: Command {
    let args: ArrangeWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        let layout: StartupLayout = switch args.arrangement.val {
            case .dwindle: .dwindle
            case .grid: .grid
            case .row: .row
        }
        target.workspace.arrangeTilingWindows(layout)
        return .succ
    }
}

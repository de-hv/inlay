import Common

/// Read only. The server answers it without a refresh session, so that asking doesn't change what is counted.
/// See: newConnection
struct DebugStatsCommand: Command {
    let args: DebugStatsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        .succ(io.out(DebugStats.report()))
    }
}

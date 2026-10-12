public struct DebugStatsCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .debugStats,
        help: debug_stats_help_generated,
        flags: [
            "--watch": singleValueSubArgParser(\.watch, "<seconds>", parseWatchSeconds),
        ],
        posArgs: [],
    )

    /// Print the counters again every this many seconds, until interrupted. The CLI client does the waiting
    public var watch: UInt32? = nil
}

private func parseWatchSeconds(_ raw: String) -> ResOrStr<UInt32> {
    switch UInt32(raw) {
        case let seconds? where (1 ... 3600).contains(seconds): .success(seconds)
        default: .failure("Expected a whole number of seconds between 1 and 3600")
    }
}

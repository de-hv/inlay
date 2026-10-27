public struct ArrangeWorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .arrangeWorkspace,
        help: arrange_workspace_help_generated,
        flags: [
            "--workspace": workspaceSubArgParser(),
        ],
        posArgs: [newMandatoryPosArgParser(\.arrangement, parseWorkspaceArrangementArg, placeholder: WorkspaceArrangement.unionLiteral)],
    )

    public var arrangement: Lateinit<WorkspaceArrangement> = .uninitialized
}

/// How `arrange-workspace` rebuilds the tiling tree. The same values as the 'tiling.startup-layout' config option
public enum WorkspaceArrangement: String, CaseIterable, Equatable, Sendable {
    case dwindle, grid, row
}

private func parseWorkspaceArrangementArg(i: PosArgParserInput) -> ParsedCliArgs<WorkspaceArrangement> {
    .init(parseEnum(i.arg, WorkspaceArrangement.self), advanceBy: 1)
}

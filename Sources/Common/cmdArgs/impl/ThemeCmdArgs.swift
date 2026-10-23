public struct ThemeCmdArgs: CmdArgs, Equatable {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .theme,
        help: theme_help_generated,
        flags: [
            "--reset-colors": trueBoolFlag(\.resetColors),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.action, parseThemeAction, placeholder: "(set|list)"),
            ArgParser(\.name) { i in .succ(i.arg, advanceBy: 1) },
        ],
    )

    public var action: Lateinit<Action> = .uninitialized
    /// The palette, for 'set'
    public var name: String? = nil
    /// 'set' also removes the colors written by hand, so that the palette gives every color
    public var resetColors: Bool = false

    public enum Action: String, Equatable, Sendable {
        /// Make the palette the one of the config
        case set
        /// Print the palettes, the one in use marked
        case list
    }
}

private func parseThemeAction(i: PosArgParserInput) -> ParsedCliArgs<ThemeCmdArgs.Action> {
    switch ThemeCmdArgs.Action(rawValue: i.arg) {
        case let action?: .succ(action, advanceBy: 1)
        case nil: .fail("Can't parse '\(i.arg)'. Possible values: set|list", advanceBy: 1)
    }
}

func parseThemeCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ThemeCmdArgs> {
    parseSpecificCmdArgs(ThemeCmdArgs(rawArgs: args), args)
        .filter("'theme set' requires the name of a palette (see: inlay theme list)") { $0.action.val != .set || $0.name != nil }
        .filter("'theme list' takes no name") { $0.action.val != .list || $0.name == nil }
        .filter("--reset-colors requires 'set'") { !$0.resetColors || $0.action.val == .set }
}

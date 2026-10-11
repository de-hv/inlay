public struct LayoutCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .layout,
        help: layout_help_generated,
        flags: [
            "--window-id": windowIdSubArgParser(),
            "--workspace": workspaceSubArgParser(),
            "--root": trueBoolFlag(\.root),
            "--fail-if-noop": trueBoolFlag(\.failIfNoop),
            "--for-next-detected-window": trueBoolFlag(\.forNextDetectedWindow),
        ],
        posArgs: [newMandatoryPosArgParser(\.parsedToggleBetween, parseToggleBetween, placeholder: LayoutDescription.unionLiteral)],
        conflictingOptions: [
            ["--window-id", "--workspace"],

            // todo introduce a flagsAllowlist primitive
            ["--for-next-detected-window", "--window-id"],
            ["--for-next-detected-window", "--workspace"],
            ["--for-next-detected-window", "--root"],
            ["--for-next-detected-window", "--fail-if-noop"],
        ],
    )

    public var toggleBetween: Lateinit<[LayoutDescription]> = .uninitialized

    public init(rawArgs: [String], toggleBetween: [LayoutDescription]) {
        self.commonState = .init(rawArgs.slice)
        self.toggleBetween = .initialized(toggleBetween)
    }

    /// Inlay has no accordion layout. The accordion arguments of AeroSpace (accordion, h_accordion, v_accordion) are
    /// accepted and treated as the tiles layout of the same orientation. Here are those arguments as the user typed them
    public var accordionArgs: [String] = []

    public enum LayoutDescription: String, CaseIterable, Equatable, Sendable, AeroAny {
        case tiles
        case horizontal, vertical
        case h_tiles, v_tiles
        case tiling, floating
    }

    public var root: Bool = false
    public var failIfNoop: Bool = false
    public var forNextDetectedWindow: Bool = false
}

public let layoutCommandRootFlagIncompatibilityMsg = "layout command: --root and tiling|floating are incompatible"
public let layoutCommandForNextDetectedWindowFlagIncompatibilityMsg =
    "layout command: --for-next-detected-window allows only one tiling|floating <target-layout> argument"

extension LayoutCmdArgs {
    /// The warning to show to the user if the command uses the accordion arguments of AeroSpace
    public var accordionWarning: String? {
        if accordionArgs.isEmpty { return nil }
        let mapping = accordionArgs.map { "'\($0)' is treated as '\(accordionArgToTiles[$0].orDie().rawValue)'" }
        return "Inlay has no accordion layout: " + mapping.joined(separator: ", ")
    }

    fileprivate var parsedToggleBetween: Lateinit<ParsedToggleBetween> {
        get {
            switch toggleBetween {
                case .initialized(let layouts): .initialized(ParsedToggleBetween(layouts: layouts, accordionArgs: accordionArgs))
                case .uninitialized: .uninitialized
            }
        }
        set {
            switch newValue {
                case .initialized(let parsed):
                    toggleBetween = .initialized(parsed.layouts)
                    accordionArgs = parsed.accordionArgs
                case .uninitialized:
                    toggleBetween = .uninitialized
                    accordionArgs = []
            }
        }
    }
}

private struct ParsedToggleBetween: Sendable {
    var layouts: [LayoutCmdArgs.LayoutDescription] = []
    var accordionArgs: [String] = []
}

private let accordionArgToTiles: [String: LayoutCmdArgs.LayoutDescription] = [
    "accordion": .tiles,
    "h_accordion": .h_tiles,
    "v_accordion": .v_tiles,
]

private func parseToggleBetween(input: PosArgParserInput) -> ParsedCliArgs<ParsedToggleBetween> {
    let args = input.nonFlagArgs()

    var result = ParsedToggleBetween()
    var i = 0
    for arg in args {
        if let layout = arg.parseLayoutDescription() {
            result.layouts.append(layout)
        } else if let layout = accordionArgToTiles[arg] {
            result.accordionArgs.append(arg)
            result.layouts.append(layout)
        } else {
            return .fail(
                "Can't parse '\(arg)'\nPossible values: \(LayoutCmdArgs.LayoutDescription.unionLiteral)",
                advanceBy: i + 1,
            )
        }
        i += 1
    }

    if !result.accordionArgs.isEmpty {
        // 'layout tiles accordion' used to toggle between two layouts. Now, it's the same layout twice
        var unique: [LayoutCmdArgs.LayoutDescription] = []
        for layout in result.layouts where !unique.contains(layout) {
            unique.append(layout)
        }
        result.layouts = unique
    }
    return .succ(result, advanceBy: args.count)
}

func parseLayoutCmdArgs(_ args: StrArrSlice) -> ParsedCmd<LayoutCmdArgs> {
    parseSpecificCmdArgs(LayoutCmdArgs(rawArgs: args), args)
        .map {
            check(!$0.toggleBetween.val.isEmpty)
            return $0
        }
        .filter(layoutCommandRootFlagIncompatibilityMsg) { cmdArgs in
            !cmdArgs.root || cmdArgs.toggleBetween.val.allSatisfy {
                switch $0 {
                    case .floating, .tiling: false
                    case .h_tiles, .horizontal, .tiles, .v_tiles, .vertical: true
                }
            }
        }
        .filter(layoutCommandForNextDetectedWindowFlagIncompatibilityMsg) { cmdArgs in
            !cmdArgs.forNextDetectedWindow || true == cmdArgs.toggleBetween.val.singleOrNil()?.then {
                switch $0 {
                    case .floating, .tiling: true
                    case .h_tiles, .horizontal, .tiles, .v_tiles, .vertical: false
                }
            }
        }
        .filter("--workspace flag requires using an explicit --root flag") { ($0.workspaceName != nil).implies($0.root) }
        .filter("--fail-if-noop allows only one <target-layout> argument") { $0.failIfNoop.implies($0.toggleBetween.val.count == 1) }
}

extension String {
    fileprivate func parseLayoutDescription() -> LayoutCmdArgs.LayoutDescription? {
        if let parsed = LayoutCmdArgs.LayoutDescription(rawValue: self) {
            return parsed
        } else if self == "list" {
            return .tiles
        } else if self == "h_list" {
            return .h_tiles
        } else if self == "v_list" {
            return .v_tiles
        }
        return nil
    }
}

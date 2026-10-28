public struct ConfigCmdArgs: CmdArgs, Equatable {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(
        kind: .config,
        help: config_help_generated,
        flags: [
            "--json": trueBoolFlag(\.json),
            "--keys": trueBoolFlag(\.keys),
            "--major-keys": trueBoolFlag(\.majorKeys),
            "--all-keys": trueBoolFlag(\.allKeys),
            "--config-path": trueBoolFlag(\.configPath),
            "--use": singleValueSubArgParser(\.pathToUse, "<path>", Result.success),
            "--unlink": trueBoolFlag(\.unlink),
            "--export": trueBoolFlag(\.export),
            "--get": singleValueSubArgParser(\.keyNameToGet, "<name>", Result.success),
            "--explain": ArgParser(\.explain) { input in
                switch input.nonFlagArgOrNil() {
                    case let key?: .succ(.key(key), advanceBy: 1)
                    case nil: .succ(.everything, advanceBy: 0)
                }
            },
        ],
        posArgs: [],
    )

    public var json: Bool = false
    public var majorKeys: Bool = false
    public var keys: Bool = false
    public var allKeys: Bool = false
    public var configPath: Bool = false
    public var keyNameToGet: String? = nil
    /// A file whose text replaces the config, or a folder that ~/.config/inlay links to. The CLI makes it absolute
    public var pathToUse: String? = nil
    public var unlink: Bool = false
    public var export: Bool = false
    public var explain: Explain? = nil

    /// What `--explain` prints of the config reference
    public enum Explain: Equatable, Sendable {
        case everything
        case key(String)
    }
}

extension ConfigCmdArgs {
    public enum Mode {
        case getKey(key: String), majorKeys, allKeys, configPath
        /// Changes the config: see ConfigFiles
        case use(path: String), unlink
        /// The config with every key that it leaves out
        case export
        /// Answered from the config reference, without the server. nil key: the whole reference
        case explain(key: String?)
    }

    public var mode: Mode {
        if let keyNameToGet { return .getKey(key: keyNameToGet) }
        if majorKeys { return .majorKeys }
        if allKeys { return .allKeys }
        if configPath { return .configPath }
        if let pathToUse { return .use(path: pathToUse) }
        if unlink { return .unlink }
        if export { return .export }
        switch explain {
            case .everything: return .explain(key: nil)
            case .key(let key): return .explain(key: key)
            case nil: break
        }
        die("At least one mode must be specified")
    }
}

func parseConfigCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ConfigCmdArgs> {
    parseSpecificCmdArgs(ConfigCmdArgs(commonState: .init(args)), args)
        .flatMap { raw in
            var conflicting: Set<String> = []
            if raw.keyNameToGet != nil { conflicting.insert("--get") }
            if raw.majorKeys { conflicting.insert("--major-keys") }
            if raw.allKeys { conflicting.insert("--all-keys") }
            if raw.configPath { conflicting.insert("--config-path") }
            if raw.explain != nil { conflicting.insert("--explain") }
            if raw.pathToUse != nil { conflicting.insert("--use") }
            if raw.unlink { conflicting.insert("--unlink") }
            if raw.export { conflicting.insert("--export") }
            return switch conflicting.count {
                case 1: .cmd(raw)
                case 0: .failure("Mandatory flag is not specified (--get|--major-keys|--all-keys|--config-path|--explain|--use|--unlink|--export)")
                default: .failure("Conflicting flags are specified: \(conflicting.joined(separator: ", "))")
            }
        }
        .filter("--keys flag requires --get flag") { !$0.keys || $0.keyNameToGet != nil }
        .filter("--json flag requires --get flag") { !$0.json || $0.keyNameToGet != nil }
}

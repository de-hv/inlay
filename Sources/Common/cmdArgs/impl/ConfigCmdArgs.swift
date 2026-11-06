public struct ConfigCmdArgs: CmdArgs, Equatable {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public static let parser: CmdParser<Self> = .init(
        kind: .config,
        help: config_help_generated,
        flags: [
            "--show": ArgParser(\.show) { input in
                switch input.nonFlagArgOrNil() {
                    case let key?: .succ(.key(key), advanceBy: 1)
                    case nil: .succ(.everything, advanceBy: 0)
                }
            },
            "--mine": trueBoolFlag(\.mine),
            "--keys": trueBoolFlag(\.keys),
            "--json": trueBoolFlag(\.json),
            "--types": trueBoolFlag(\.types),
            "--config-path": trueBoolFlag(\.configPath),
            "--files": trueBoolFlag(\.files),
            "--file": singleValueSubArgParser(\.file, "<name>", Result.success),
            "--use": singleValueSubArgParser(\.pathToUse, "<path>", Result.success),
            "--unlink": trueBoolFlag(\.unlink),
            "--explain": ArgParser(\.explain) { input in
                switch input.nonFlagArgOrNil() {
                    case let key?: .succ(.key(key), advanceBy: 1)
                    case nil: .succ(.everything, advanceBy: 0)
                }
            },
            // The flags of a previous version: an error that names the new one. See: removedFlagMessage
            "--get": singleValueSubArgParser(\.removedGet, "<name>", Result.success),
            "--major-keys": trueBoolFlag(\.removedMajorKeys),
            "--all-keys": trueBoolFlag(\.removedAllKeys),
        ],
        posArgs: [],
    )

    /// What `--show` prints of the config in use
    public var show: Explain? = nil
    /// With --show: only the values of the user
    public var mine: Bool = false
    /// With --show: only the paths of the keys
    public var keys: Bool = false
    /// With --show: JSON, for scripts
    public var json: Bool = false
    /// The .luarc.json of the config folder, for the autocompletion of the editor
    public var types: Bool = false
    public var configPath: Bool = false
    /// The files that the config is made of: the ones of Inlay and the ones of the user
    public var files: Bool = false
    /// The text of one of them: 'builtin-config', 'themes/gruvbox', 'binds'
    public var file: String? = nil
    /// A file whose text replaces the config, or a folder that ~/.config/inlay links to. The CLI makes it absolute
    public var pathToUse: String? = nil
    public var unlink: Bool = false
    public var explain: Explain? = nil
    public var removedGet: String? = nil
    public var removedMajorKeys: Bool = false
    public var removedAllKeys: Bool = false

    /// What `--explain` prints of the config reference, and `--show` of the config in use
    public enum Explain: Equatable, Sendable {
        case everything
        case key(String)
    }
}

extension ConfigCmdArgs {
    public enum Mode {
        /// The config in use. nil key: all of it
        case show(key: String?)
        case configPath
        /// The files of the config in use
        case files
        /// The text of one file of the config: of Inlay, a theme, or of the user
        case file(name: String)
        /// Changes the config: see ConfigFiles
        case use(path: String), unlink
        /// Answered from the config reference, without the server. nil key: the whole reference
        case explain(key: String?)
        /// Answered by the CLI: the .luarc.json of the config folder
        case types
    }

    public var mode: Mode {
        switch show {
            case .everything: return .show(key: nil)
            case .key(let key): return .show(key: key)
            case nil: break
        }
        if configPath { return .configPath }
        if files { return .files }
        if let file { return .file(name: file) }
        if let pathToUse { return .use(path: pathToUse) }
        if unlink { return .unlink }
        if types { return .types }
        switch explain {
            case .everything: return .explain(key: nil)
            case .key(let key): return .explain(key: key)
            case nil: break
        }
        die("At least one mode must be specified")
    }
}

private let mandatoryFlags = "--show|--files|--file|--explain|--types|--config-path|--use|--unlink"

func parseConfigCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ConfigCmdArgs> {
    parseSpecificCmdArgs(ConfigCmdArgs(commonState: .init(args)), args)
        .flatMap { raw in
            if let message = removedFlagMessage(raw) { return .failure(message) }
            var conflicting: Set<String> = []
            if raw.show != nil { conflicting.insert("--show") }
            if raw.configPath { conflicting.insert("--config-path") }
            if raw.files { conflicting.insert("--files") }
            if raw.file != nil { conflicting.insert("--file") }
            if raw.explain != nil { conflicting.insert("--explain") }
            if raw.pathToUse != nil { conflicting.insert("--use") }
            if raw.unlink { conflicting.insert("--unlink") }
            if raw.types { conflicting.insert("--types") }
            return switch conflicting.count {
                case 1: .cmd(raw)
                case 0: .failure("Mandatory flag is not specified (\(mandatoryFlags))")
                default: .failure("Conflicting flags are specified: \(conflicting.sorted().joined(separator: ", "))")
            }
        }
        .filter("--mine flag requires --show flag") { !$0.mine || $0.show != nil }
        .filter("--keys flag requires --show flag") { !$0.keys || $0.show != nil }
        .filter("--json flag requires --show flag") { !$0.json || $0.show != nil }
        .filter("--keys and --json can't go together: --keys prints the paths of the keys, --json their values") { !($0.keys && $0.json) }
}

/// '--get', '--major-keys' and '--all-keys' only knew the key bindings: '--show' prints the whole config
private func removedFlagMessage(_ raw: ConfigCmdArgs) -> String? {
    if let key = raw.removedGet {
        return "'--get' is gone. The value of a key, and where it comes from: config --show \(key)"
    }
    if raw.removedMajorKeys || raw.removedAllKeys {
        let flag = raw.removedMajorKeys ? "--major-keys" : "--all-keys"
        return "'\(flag)' is gone. Every key of the config: config --show --keys"
    }
    return nil
}

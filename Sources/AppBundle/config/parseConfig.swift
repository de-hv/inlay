import AppKit
import Common
import HotKey
import OrderedCollections

struct ReadConfigResult {
    let configUrl: URL
    /// The contents of the file. nil if it wasn't read
    var text: String? = nil
    /// The main file and its modules, with the text that was run
    var files: [LuaConfigFile] = []
    let parseConfigResult: ParseConfigResult

    @MainActor static func fatal(configUrl: URL, message: String) -> Self {
        ReadConfigResult(
            configUrl: configUrl,
            parseConfigResult: ParseConfigResult(
                config: defaultConfig,
                errors: [.init(.emptyRoot, message, preventConfigReload: true)],
                warnings: [],
            ),
        )
    }
}

@MainActor
func readConfig(forceConfigUrl: URL?) -> ReadConfigResult {
    let configUrl: URL
    if let forceConfigUrl {
        configUrl = forceConfigUrl
    } else {
        switch findCustomConfigUrl() {
            case .file(let url): configUrl = url
            case .noCustomConfigExists: configUrl = builtInConfigUrl
            case .legacyConfig(let url): return .fatal(configUrl: url, message: legacyConfigMessage(url))
            case .ambiguousConfigError(let candidates):
                let msg = """
                    Ambiguous config error. Several configs found:
                    \(candidates.map(\.path).joined(separator: "\n"))
                    """
                return .fatal(configUrl: builtInConfigUrl, message: msg)
        }
    }
    let lua = LuaConfigLoader.load(file: configUrl)
    // The built-in config is the base of any other: see mergedConfig
    let result = parseConfig(lua, base: configUrl == builtInConfigUrl ? nil : builtInConfigTable)
    // A file that can't be read has no files
    return ReadConfigResult(configUrl: configUrl, text: lua.files.first?.text, files: lua.files + result.themeFiles, parseConfigResult: result)
}

struct ConfigParseDiagnostic: Error, Equatable {
    let backtrace: ConfigBacktrace
    let message: String
    let preventConfigReload: Bool // for severe config errors (like a Lua syntax error)

    public init(_ backtrace: ConfigBacktrace, _ message: String, preventConfigReload: Bool = false) {
        check(!message.isEmpty)
        self.backtrace = backtrace
        self.message = message
        self.preventConfigReload = preventConfigReload
    }

    func description(_ severity: Severity) -> String {
        let backtraceDesc = backtrace.description
        // todo Make 'split' + flatten normalization prettier
        return switch backtraceDesc.isEmpty {
            case true: "[\(severity.rawValue)] \(message)"
            case false: "[\(severity.rawValue)] \(backtraceDesc): \(message)"
        }
    }

    enum Severity: String {
        case warning = "WARNING"
        case error = "ERROR"
    }
}

typealias ResOrConfigParseDiagnostic<T> = Result<T, ConfigParseDiagnostic>

extension ParserProtocol {
    func transformRawConfig(_ raw: S,
                            _ value: OrderedJson,
                            _ backtrace: ConfigBacktrace,
                            _ c: inout ConfigParserContext) -> S
    {
        if let value = parse(value, backtrace, &c).getOrNil(appendErrorTo: &c.errors) {
            return raw.copy(keyPath, value)
        }
        return raw
    }
}

struct ConfigParserContext {
    var errors: [ConfigParseDiagnostic]
    var warnings: [ConfigParseDiagnostic]
}

protocol ParserProtocol<S>: Sendable {
    associatedtype T
    associatedtype S where S: ConvenienceMutable
    var keyPath: SendableWritableKeyPath<S, T> { get }
    var parse: @Sendable (OrderedJson, ConfigBacktrace, inout ConfigParserContext) -> ResOrConfigParseDiagnostic<T> { get }
}

struct Parser<S: ConvenienceMutable, T>: ParserProtocol {
    let keyPath: SendableWritableKeyPath<S, T>
    let parse: @Sendable (OrderedJson, ConfigBacktrace, inout ConfigParserContext) -> ResOrConfigParseDiagnostic<T>

    init(_ keyPath: SendableWritableKeyPath<S, T>, _ parse: @escaping @Sendable (OrderedJson, ConfigBacktrace, inout ConfigParserContext) -> T) {
        self.keyPath = keyPath
        self.parse = { raw, backtrace, errors -> ResOrConfigParseDiagnostic<T> in .success(parse(raw, backtrace, &errors)) }
    }

    init(_ keyPath: SendableWritableKeyPath<S, T>, _ parse: @escaping @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<T>) {
        self.keyPath = keyPath
        self.parse = { raw, backtrace, _ -> ResOrConfigParseDiagnostic<T> in parse(raw, backtrace) }
    }
}

private let keyMappingConfigRootKey = "key_mapping"
let modeConfigRootKey = "mode"
let persistentWorkspacesKey = "persistent_workspaces"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over config options if possible
// 3. Document it in docs/config-reference.lua. ConfigReferenceTest fails until every key of the parser tables is there
let configParser: [String: any ParserProtocol<Config>] = [
    "after_startup_command": Parser(\.afterStartupCommand, parseShellOfCommandsForConfig),

    "on_focus_changed": Parser(\.onFocusChanged, parseShellOfCommandsForConfig),
    "on_mode_changed": Parser(\.onModeChanged, parseShellOfCommandsForConfig),
    "on_focused_monitor_changed": Parser(\.onFocusedMonitorChanged, parseShellOfCommandsForConfig),
    // "on-focused-workspace-changed": Parser(\.onFocusedWorkspaceChanged, { parseCommandOrCommands($0).toParsedConfig($1) }),

    "enable_normalization_flatten_containers": Parser(\.enableNormalizationFlattenContainers, parseBool),
    "enable_normalization_opposite_orientation_for_nested_containers": Parser(\.enableNormalizationOppositeOrientationForNestedContainers, parseBool),

    "default_root_container_layout": Parser(\.defaultRootContainerLayout, parseLayout),
    "default_root_container_orientation": Parser(\.defaultRootContainerOrientation, parseDefaultContainerOrientation),

    "start_at_login": Parser(\.startAtLogin, parseBool),
    "auto_reload_config": Parser(\.autoReloadConfig, parseBool),
    "automatically_unhide_macos_hidden_apps": Parser(\.automaticallyUnhideMacosHiddenApps, parseBool),
    persistentWorkspacesKey: Parser(\.persistentWorkspaces, parsePersistentWorkspaces),
    workspacesKey: Parser(\._workspaces, skipParsing(())), // Expanded before the config is parsed. See: expandWorkspaces
    workspaceKeysKey: Parser(\._workspaces, skipParsing(())), // The same
    builtInConfigKey: Parser(\._builtInConfig, skipParsing(())), // Read before the config is parsed. See: mergedConfig
    "exec_on_workspace_change": Parser(\.execOnWorkspaceChange, parseArrayOfStrings),
    "exec": Parser(\.execConfig, parseExecConfig),

    keyMappingConfigRootKey: Parser(\.keyMapping, skipParsing(Config().keyMapping)), // Parsed manually
    modeConfigRootKey: Parser(\.modes, skipParsing(Config().modes)), // Parsed manually

    "gaps": Parser(\.gaps, parseGaps),
    "focus_follows_mouse": Parser(\.focusFollowsMouse, parseFocusFollowsMouse),
    "tiling": Parser(\.tiling, parseTiling),
    "menu_bar": Parser(\.menuBar, parseMenuBar),
    "borders": Parser(\.borders, parseBorders),
    "animations": Parser(\.animations, parseAnimations),
    themeKey: Parser(\._theme, skipParsing(())), // Parsed manually, before 'borders' and 'menu_bar'. See: ThemeResolver
    "notifications": Parser(\._notifications, parseObsolete("The notice of the reload is gone")),
    "settings": Parser(\._settings, parseObsolete("The Settings window is gone: the config is only this file")),
    "workspace_to_monitor_force_assignment": Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    "on_window_detected": Parser(\.onWindowDetected, parseOnWindowDetectedArray),
]

extension ParsedCmd {
    func toResult() -> ResOrStr<T> {
        return switch self {
            case .cmd(let a): .success(a)
            case .help(let a): .failure(a)
            case .failure(let a): .failure(a.msg)
        }
    }
}

/// A table or a key that Inlay had once and doesn't have anymore: a warning instead of an error, so an old config
/// still loads
func parseObsolete(_ reason: String) -> @Sendable (OrderedJson, ConfigBacktrace, inout ConfigParserContext) -> Void {
    { _, backtrace, c in
        c.warnings.append(.init(backtrace, "\(reason). It is ignored: please drop it from the config"))
    }
}

func parseCommandForConfig(_ raw: String, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext, allowExecAndForget: Bool) -> Shell<any Command> {
    let shell = parseCommand(raw, allowExecAndForget: allowExecAndForget, allowEval: false).toResult().toParsedConfig(backtrace).getOrNil(appendErrorTo: &c.errors) ?? .empty
    c.warnings += shell.flatten().filterIsInstance(of: LayoutCommand.self).compactMap(\.args.accordionWarning).map { .init(backtrace, $0) }
    return shell
}

func parseShellOfCommandsForConfig(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Shell<any Command> {
    if let rawString = raw.asStringOrNil {
        return parseCommandForConfig(rawString, backtrace, &c, allowExecAndForget: true)
    } else if let rawArray = raw.asArrayOrNil {
        var result = [Shell<any Command>]()
        for (index, elem) in rawArray.enumerated() {
            let backtrace = backtrace + .index(index)
            if let elem = elem.asStringOrNil {
                result.append(parseCommandForConfig(elem, backtrace, &c, allowExecAndForget: true))
            } else {
                c.errors.append(.init(backtrace, expectedActualTypeError(expected: .string, actual: elem.valueType)))
            }
        }
        return .newCompound(result, Shell<any Command>.seq)
    } else {
        c.errors.append(.init(backtrace, expectedActualTypeError(expected: [.string, .array], actual: raw.valueType)))
        return .empty
    }
}

struct ParseConfigResult {
    let config: Config
    let errors: [ConfigParseDiagnostic]
    let warnings: [ConfigParseDiagnostic]
    /// The themes of the config folder that were read or looked for. See: ThemeResolver
    var themeFiles: [LuaConfigFile] = []

    var allowReloadConfig: Bool { errors.allSatisfy { !$0.preventConfigReload } }
}

@MainActor func parseConfig(_ lua: LuaConfig, base: OrderedJson.JsonDict? = nil) -> ParseConfigResult {
    parseConfig(json: lua.table, errors: lua.errors, configFolder: lua.files.first?.url?.deletingLastPathComponent(), base: base)
}

/// The config from the text of an inlay.lua that has no modules
@MainActor func parseConfig(lua text: String, base: OrderedJson.JsonDict? = nil) -> ParseConfigResult {
    parseConfig(LuaConfigLoader.load(text), base: base)
}

/// The config of the user over the built-in one, the way readConfig loads it
@MainActor func parseConfigOverBuiltIn(_ lua: LuaConfig) -> ParseConfigResult {
    parseConfig(lua, base: builtInConfigTable)
}

/// The config from the table that inlay.lua returns.
/// - Parameter errors: the ones of running the file
/// - Parameter configFolder: the folder of inlay.lua, where the themes of the user are. See: ThemeResolver
/// - Parameter base: the table of the built-in config, under the one of the user. See: mergedConfig
@MainActor func parseConfig(
    json configTable: OrderedJson.JsonDict,
    errors: [ConfigParseDiagnostic] = [],
    configFolder: URL? = nil,
    base: OrderedJson.JsonDict? = nil,
) -> ParseConfigResult {
    var c = ConfigParserContext(errors: errors, warnings: [ConfigParseDiagnostic]())

    let layers = layeredConfig(user: configTable, base: base, configFolder: configFolder, &c)
    var rawTable = layers.dark
    let workspaceNames = expandWorkspaces(&rawTable, &c)

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &c)
    config.workspaceNames = workspaceNames

    if var lightTable = layers.light {
        // The same tables of the config, with other colors: their problems are already reported
        var quiet = ConfigParserContext(errors: [], warnings: [])
        _ = expandWorkspaces(&lightTable, &quiet)
        config.lightAppearance = AppearanceColors(
            borders: lightTable["borders"].map { parseBorders($0, .rootKey("borders"), &quiet) } ?? BordersConfig(),
            menuBar: lightTable["menu_bar"].map { parseMenuBar($0, .rootKey("menu_bar"), &quiet) } ?? MenuBarConfig(),
        )
    }

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &c) }) {
        config.keyMapping = mapping
    }

    // Parse modeConfigRootKey after keyMappingConfigRootKey
    if let modes = rawTable[modeConfigRootKey].flatMap({ parseModes($0, .rootKey(modeConfigRootKey), &c, config.keyMapping.resolve()) }) {
        config.modes = modes
    }

    if config.enableNormalizationFlattenContainers {
        let containsSplitCommand = config.modes.values.lazy.flatMap { $0.bindings.values }
            .flatMap { $0.commands.flatten() }
            .contains { $0 is SplitCommand }
        if containsSplitCommand {
            c.errors += [.init(
                .emptyRoot, // todo Make 'split' + flatten normalization prettier
                """
                The config contains:
                1. usage of 'split' command
                2. enable_normalization_flatten_containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable_normalization_flatten_containers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """,
            )]
        }
    }
    return ParseConfigResult(config: config, errors: c.errors, warnings: c.warnings, themeFiles: layers.themeFiles)
}

func parseInt(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    raw.asIntOrNil.toResult(expectedActualTypeDiagnostic(expected: .int, actual: raw.valueType, backtrace))
}

func parseString(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<String> {
    raw.asStringOrNil.toResult(expectedActualTypeDiagnostic(expected: .string, actual: raw.valueType, backtrace))
}

func parseSimpleType<T>(_ raw: OrderedJson, ofType: T.Type) -> T? {
    (raw.asIntOrNil as? T) ?? (raw.asStringOrNil as? T) ?? (raw.asBoolOrNil as? T)
}

extension OrderedJson {
    func unwrapTableWithSingleKey(expectedKey: String? = nil, _ backtrace: inout ConfigBacktrace) -> ResOrConfigParseDiagnostic<(key: String, value: OrderedJson)> {
        guard let asDictOrNil else {
            return .failure(expectedActualTypeDiagnostic(expected: .table, actual: valueType, backtrace))
        }
        let singleKeyError: ConfigParseDiagnostic = .init(
            backtrace,
            expectedKey != nil
                ? "The table is expected to have a single key '\(expectedKey.orDie())'"
                : "The table is expected to have a single key",
        )
        guard let (actualKey, value): (String, OrderedJson) = asDictOrNil.count == 1 ? asDictOrNil.first : nil else {
            return .failure(singleKeyError)
        }
        if expectedKey != nil && expectedKey != actualKey {
            return .failure(singleKeyError)
        }
        backtrace = backtrace + .key(actualKey)
        return .success((actualKey, value))
    }
}

func parseConfigArray(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<OrderedJson.JsonArray> {
    raw.asArrayOrNil.toResult(expectedActualTypeDiagnostic(expected: .array, actual: raw.valueType, backtrace))
}

func parseTable<T: ConvenienceMutable>(
    _ raw: OrderedJson,
    _ initial: T,
    _ fieldsParser: [String: any ParserProtocol<T>],
    _ backtrace: ConfigBacktrace,
    _ c: inout ConfigParserContext,
) -> T {
    switch raw {
        case .dict(let table):
            return table.parseTable(initial, fieldsParser, backtrace, &c)
        default:
            c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.valueType, backtrace))
            return initial
    }
}

private func parseLayout(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> Layout {
    let layout = parseString(raw, backtrace)
        .flatMap { (raw: String) -> ResOrConfigParseDiagnostic<Layout> in
            // Accepted to make it possible to use the config of AeroSpace as is
            if raw == "accordion" {
                c.warnings.append(.init(backtrace, "Inlay has no accordion layout: 'accordion' is treated as 'tiles'"))
                return .success(.tiles)
            }
            return raw.parseLayout().toResult(.init(backtrace, "Can't parse layout '\(raw)'"))
        }
        .getOrNil(appendErrorTo: &c.errors)
    return layout ?? Config().defaultRootContainerLayout
}

private func skipParsing<T: Sendable>(_ value: T) -> @Sendable (_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<T> {
    { _, _ in .success(value) }
}

private func parsePersistentWorkspaces(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<OrderedSet<String>> {
    parseArrayOfStrings(raw, backtrace)
        .flatMap { arr in
            let set = arr.toOrderedSet()
            return set.count == arr.count ? .success(set) : .failure(.init(backtrace, "Contains duplicated workspace names"))
        }
}

func parseArrayOfStrings(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<[String]> {
    parseConfigArray(raw, backtrace)
        .flatMap { arr in
            arr.enumerated().mapAllOrFailure { (index, elem) in
                parseString(elem, backtrace + .index(index))
            }
        }
}

private func parseDefaultContainerOrientation(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<DefaultContainerOrientation> {
    parseString(raw, backtrace).flatMap {
        DefaultContainerOrientation(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse default container orientation '\($0)'"))
    }
}

extension ResOrStr where Failure == String {
    func toParsedConfig(_ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Success> {
        mapError { .init(backtrace, $0) }
    }
}

func parseBool(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Bool> {
    raw.asBoolOrNil.toResult(expectedActualTypeDiagnostic(expected: .bool, actual: raw.valueType, backtrace))
}

struct ConfigBacktrace: CustomStringConvertible, Equatable {
    private var path: [ConfigBacktraceItem] = []
    private init(_ path: [ConfigBacktraceItem]) {
        check(path.first?.isKey != false, "Tried to construct invalid config path: \(path)")
        self.path = path
    }

    static func rootKey(_ key: String) -> Self { .init([.key(key)]) }
    static let emptyRoot: Self = .init([])

    var description: String {
        var result = ""
        for (i, elem) in path.enumerated() {
            switch elem {
                case .key(let rootKey) where i == 0: result += rootKey
                case .key(let key): result += ".\(key)"
                case .index(let index): result += "[\(index)]"
            }
        }
        return result
    }

    var isRootKey: Bool { path.singleOrNil().map(\.isKey) == true }

    static func + (lhs: consuming Self, rhs: ConfigBacktraceItem) -> Self {
        lhs.path += [rhs]
        return lhs
    }
}

enum ConfigBacktraceItem: Equatable {
    case key(String)
    case index(Int)

    var isKey: Bool {
        switch self {
            case .key: true
            case .index: false
        }
    }
}

extension OrderedJson.JsonDict {
    func parseTable<T: ConvenienceMutable>(
        _ initial: T,
        _ fieldsParser: [String: any ParserProtocol<T>],
        _ backtrace: ConfigBacktrace,
        _ c: inout ConfigParserContext,
    ) -> T {
        var raw = initial

        for (key, value) in self {
            let backtrace: ConfigBacktrace = backtrace + .key(key)
            switch fieldsParser[key] {
                case let parser?: raw = parser.transformRawConfig(raw, value, backtrace, &c)
                case nil: c.errors.append(unknownKeyDiagnostic(backtrace, key: key, knownKeys: Set(fieldsParser.keys)))
            }
        }

        return raw
    }
}

func unknownKeyDiagnostic(_ backtrace: ConfigBacktrace, key: String? = nil, knownKeys: Set<String> = []) -> ConfigParseDiagnostic {
    let message = backtrace.isRootKey ? "Unknown top-level key" : "Unknown key"
    // The keys of Inlay 0.2 and of AeroSpace ('corner-radius') and of Inlay 0.3 to 0.6.1 ('cornerRadius')
    guard let key else { return .init(backtrace, message) }
    let snakeCase = snakeCaseKey(key)
    guard snakeCase != key, knownKeys.contains(snakeCase) else { return .init(backtrace, message) }
    return .init(backtrace, "\(message). The keys are snake_case since Inlay 0.6.2: '\(snakeCase)'")
}

/// 'corner-radius' and 'cornerRadius' are 'corner_radius'
func snakeCaseKey(_ key: String) -> String {
    var result = ""
    for char in key {
        if char == "-" {
            result.append("_")
        } else if char.isUppercase {
            result.append("_")
            result.append(contentsOf: char.lowercased())
        } else {
            result.append(char)
        }
    }
    return result
}

func expectedActualTypeDiagnostic(expected: ConfigValueType, actual: ConfigValueType, _ backtrace: ConfigBacktrace) -> ConfigParseDiagnostic {
    .init(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}

func expectedActualTypeDiagnostic(expected: [ConfigValueType], actual: ConfigValueType, _ backtrace: ConfigBacktrace) -> ConfigParseDiagnostic {
    .init(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}

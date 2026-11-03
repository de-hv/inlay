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
            case .noCustomConfigExists: configUrl = defaultConfigUrl
            case .legacyConfig(let url): return .fatal(configUrl: url, message: legacyConfigMessage(url))
            case .ambiguousConfigError(let candidates):
                let msg = """
                    Ambiguous config error. Several configs found:
                    \(candidates.map(\.path).joined(separator: "\n"))
                    """
                return .fatal(configUrl: defaultConfigUrl, message: msg)
        }
    }
    let lua = LuaConfigLoader.load(file: configUrl)
    // A file that can't be read has no files
    return ReadConfigResult(configUrl: configUrl, text: lua.files.first?.text, files: lua.files, parseConfigResult: parseConfig(lua))
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
    var configVersion: ConfigVersion
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

private let keyMappingConfigRootKey = "keyMapping"
private let configVersionConfigRootKey = "configVersion"
private let modeConfigRootKey = "mode"
let persistentWorkspacesKey = "persistentWorkspaces"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over config options if possible
// 3. Document it in docs/config-reference.lua. ConfigReferenceTest fails until every key of the parser tables is there
let configParser: [String: any ParserProtocol<Config>] = [
    configVersionConfigRootKey: Parser(\.configVersion, skipParsing(Config().configVersion)), // Parsed manually

    "afterLoginCommand": Parser(\._afterLoginCommand, parseDeprecatedAfterLoginCommand),
    "afterStartupCommand": Parser(\.afterStartupCommand, parseShellOfCommandsForConfig),

    "onFocusChanged": Parser(\.onFocusChanged, parseShellOfCommandsForConfig),
    "onModeChanged": Parser(\.onModeChanged, parseShellOfCommandsForConfig),
    "onFocusedMonitorChanged": Parser(\.onFocusedMonitorChanged, parseShellOfCommandsForConfig),
    // "on-focused-workspace-changed": Parser(\.onFocusedWorkspaceChanged, { parseCommandOrCommands($0).toParsedConfig($1) }),

    "enableNormalizationFlattenContainers": Parser(\.enableNormalizationFlattenContainers, parseBool),
    "enableNormalizationOppositeOrientationForNestedContainers": Parser(\.enableNormalizationOppositeOrientationForNestedContainers, parseBool),

    "defaultRootContainerLayout": Parser(\.defaultRootContainerLayout, parseLayout),
    "defaultRootContainerOrientation": Parser(\.defaultRootContainerOrientation, parseDefaultContainerOrientation),

    "startAtLogin": Parser(\.startAtLogin, parseBool),
    "autoReloadConfig": Parser(\.autoReloadConfig, parseBool),
    "automaticallyUnhideMacosHiddenApps": Parser(\.automaticallyUnhideMacosHiddenApps, parseBool),
    "accordionPadding": Parser(\._accordionPadding, parseAccordionPadding),
    persistentWorkspacesKey: Parser(\.persistentWorkspaces, parsePersistentWorkspaces),
    "execOnWorkspaceChange": Parser(\.execOnWorkspaceChange, parseArrayOfStrings),
    "exec": Parser(\.execConfig, parseExecConfig),

    keyMappingConfigRootKey: Parser(\.keyMapping, skipParsing(Config().keyMapping)), // Parsed manually
    modeConfigRootKey: Parser(\.modes, skipParsing(Config().modes)), // Parsed manually

    "gaps": Parser(\.gaps, parseGaps),
    "focusFollowsMouse": Parser(\.focusFollowsMouse, parseFocusFollowsMouse),
    "tiling": Parser(\.tiling, parseTiling),
    "menuBar": Parser(\.menuBar, parseMenuBar),
    "borders": Parser(\.borders, parseBorders),
    "animations": Parser(\.animations, parseAnimations),
    "theme": Parser(\._theme, parseObsolete("The palettes are gone: every color is set on its own in [menuBar.colors] and [borders]")),
    "notifications": Parser(\._notifications, parseObsolete("The notice of the reload is gone")),
    "settings": Parser(\._settings, parseObsolete("The Settings window is gone: the config is only this file")),
    "workspaceToMonitorForceAssignment": Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    "onWindowDetected": Parser(\.onWindowDetected, parseOnWindowDetectedArray),

    // Deprecated
    "nonEmptyWorkspacesRootContainersLayoutOnStartup": Parser(\._nonEmptyWorkspacesRootContainersLayoutOnStartup, parseStartupRootContainerLayout),
    "indentForNestedContainersWithTheSameOrientation": Parser(\._indentForNestedContainersWithTheSameOrientation, parseIndentForNestedContainersWithTheSameOrientation),
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

func parseDeprecatedAfterLoginCommand(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<[any Command]> {
    if let array = raw.asArrayOrNil, array.count == 0 {
        return .success([])
    }
    let msg = "afterLoginCommand is deprecated since AeroSpace 0.19.0. https://github.com/nikitabobko/AeroSpace/issues/1482"
    return .failure(.init(backtrace, msg))
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

    var allowReloadConfig: Bool { errors.allSatisfy { !$0.preventConfigReload } }
}

@MainActor func parseConfig(_ lua: LuaConfig) -> ParseConfigResult {
    parseConfig(json: lua.table, errors: lua.errors)
}

/// The config from the text of an inlay.lua that has no modules
@MainActor func parseConfig(lua text: String) -> ParseConfigResult {
    parseConfig(LuaConfigLoader.load(text))
}

/// The config from the table that inlay.lua returns.
/// - Parameter errors: the ones of running the file
@MainActor func parseConfig(json rawTable: OrderedJson.JsonDict, errors: [ConfigParseDiagnostic] = []) -> ParseConfigResult {
    var errors = NonCopyable(errors)

    let configVersion: ConfigVersion = rawTable[configVersionConfigRootKey]
        .flatMap { parseConfigVersion($0, .rootKey(configVersionConfigRootKey)).getOrNil(appendErrorTo: &errors.value) }
        ?? .min

    var c = ConfigParserContext(configVersion: configVersion, errors: errors.consume(), warnings: [ConfigParseDiagnostic]())

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &c)
    config.configVersion = configVersion

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &c) }) {
        config.keyMapping = mapping
    }

    // Parse modeConfigRootKey after keyMappingConfigRootKey
    if let modes = rawTable[modeConfigRootKey].flatMap({ parseModes($0, .rootKey(modeConfigRootKey), &c, config.keyMapping.resolve()) }) {
        config.modes = modes
    }

    if config.configVersion <= ._1 {
        if rawTable.keys.contains(persistentWorkspacesKey) {
            c.errors += [.init(.rootKey(persistentWorkspacesKey), "This config option is only available since 'configVersion = 2'")]
        }
        config.persistentWorkspaces = (config.modes.values.lazy
            .flatMap { (mode: Mode) -> [HotkeyBinding] in Array(mode.bindings.values) }
            .flatMap { (binding: HotkeyBinding) -> [String] in
                let commands = binding.commands.flatten()
                return commands.filterIsInstance(of: WorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw } +
                    commands.filterIsInstance(of: MoveNodeToWorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw }
            }
            + (config.workspaceToMonitorForceAssignment).keys)
            .toOrderedSet()
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
                2. enableNormalizationFlattenContainers = true
                These two settings don't play nicely together. 'split' command has no effect when enableNormalizationFlattenContainers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """,
            )]
        }
    }
    if config.configVersion < .max {
        let msg = "The current 'configVersion = \(config.configVersion)' is outdated. " +
            "Please consider migrating to 'configVersion = \(ConfigVersion.max)'. " +
            "See https://nikitabobko.github.io/AeroSpace/guide#config-version for the migration guide."
        c.warnings.append(.init(.emptyRoot, msg))
    }
    return ParseConfigResult(config: config, errors: c.errors, warnings: c.warnings)
}

func parseIndentForNestedContainersWithTheSameOrientation(_ _: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Void> {
    let msg = "Deprecated. Please drop it from the config. See https://github.com/nikitabobko/AeroSpace/issues/96"
    return .failure(.init(backtrace, msg))
}

func parseConfigVersion(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<ConfigVersion> {
    parseInt(raw, backtrace)
        .flatMap { ConfigVersion.init(rawValue: $0).toResult(.init(backtrace, "configVersion must be in [\(ConfigVersion.min), \(ConfigVersion.max)] range")) }
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

private func parseStartupRootContainerLayout(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Void> {
    parseString(raw, backtrace)
        .filter(.init(backtrace, "'nonEmptyWorkspacesRootContainersLayoutOnStartup' is deprecated. Please drop it from your config")) { raw in raw == "smart" }
        .map { _ in () }
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

// Accepted to make it possible to use the config of AeroSpace as is
private func parseAccordionPadding(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) {
    if parseInt(raw, backtrace).getOrNil(appendErrorTo: &c.errors) != nil {
        c.warnings.append(.init(backtrace, "Inlay has no accordion layout: 'accordionPadding' is ignored. Please drop it from the config"))
    }
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
                case nil: c.errors.append(unknownKeyDiagnostic(backtrace, key: key))
            }
        }

        return raw
    }
}

func unknownKeyDiagnostic(_ backtrace: ConfigBacktrace, key: String? = nil) -> ConfigParseDiagnostic {
    let message = backtrace.isRootKey ? "Unknown top-level key" : "Unknown key"
    // The keys of Inlay 0.2 and of AeroSpace: 'corner-radius'
    guard let key, key.contains("-") else { return .init(backtrace, message) }
    let words = key.split(separator: "-")
    let camelCase = String(words.first ?? "") + words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    return .init(backtrace, "\(message). The keys are camelCase since Inlay 0.3.0: '\(camelCase)'")
}

func expectedActualTypeDiagnostic(expected: ConfigValueType, actual: ConfigValueType, _ backtrace: ConfigBacktrace) -> ConfigParseDiagnostic {
    .init(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}

func expectedActualTypeDiagnostic(expected: [ConfigValueType], actual: ConfigValueType, _ backtrace: ConfigBacktrace) -> ConfigParseDiagnostic {
    .init(backtrace, expectedActualTypeError(expected: expected, actual: actual))
}

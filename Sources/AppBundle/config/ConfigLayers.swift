import Common
import Foundation

/// The config in use is made of layers, each one over the one before:
/// 1. the defaults of the code (Config());
/// 2. the built-in config (builtin-config.lua, in the app): workspaces, key bindings, window rules, gaps…;
/// 3. the theme ('theme'): the look of the borders and of the menu bar;
/// 4. the config of the user (inlay.lua): only what is theirs.
/// The tables are put together before they are parsed (see: mergedConfig), so the errors point at the keys of the
/// user. `builtInConfig = false` leaves out the second layer: the config of the user over the defaults of the code
let builtInConfigKey = "builtInConfig"
let onWindowDetectedKey = "onWindowDetected"

/// The raw tables of the config, put together
struct LayeredConfig {
    /// The config to parse: for the dark appearance, or the only one
    var dark: OrderedJson.JsonDict
    /// With `theme = { dark = …, light = … }`: the same config with the colors of the light theme
    var light: OrderedJson.JsonDict?
    /// The layers on their own, for 'config --show'
    var base: OrderedJson.JsonDict?
    var user: OrderedJson.JsonDict
    /// The values of the theme that went into the config: its 'borders' and 'menuBar'
    var themeValues: OrderedJson.JsonDict
    /// The name of the theme, for 'config --show'. nil: a table written in the config
    var themeName: String?
    var themeFiles: [LuaConfigFile]
}

@MainActor
func layeredConfig(user: OrderedJson.JsonDict, base: OrderedJson.JsonDict?, configFolder: URL?, _ c: inout ConfigParserContext) -> LayeredConfig {
    var base = base
    if let raw = user[builtInConfigKey] {
        switch parseBool(raw, .rootKey(builtInConfigKey)) {
            case .success(false): base = nil
            case .success(true): break
            case .failure(let error): c.errors.append(error)
        }
    }
    let rawTheme = user[themeKey] ?? base?[themeKey] ?? .string(defaultThemeName)
    var resolver = ThemeResolver(configFolder: configFolder)
    let theme = resolver.resolve(rawTheme, &c)
    // The theme goes over the built-in config, and the user over both
    func layered(_ theme: OrderedJson.JsonDict?) -> OrderedJson.JsonDict {
        let under = applyTheme(over: base ?? [:], theme ?? [:])
        return base == nil && theme == nil ? user : mergedConfig(under, user)
    }
    // Without the key, a theme that doesn't exist in the config folder is no file of the config
    let themeFiles = user[themeKey] == nil ? resolver.files.filter { $0.text != nil } : resolver.files
    return LayeredConfig(
        dark: layered(theme.dark),
        light: theme.light.map(layered),
        base: base,
        user: user,
        themeValues: (isLightAppearance ? theme.light : theme.dark) ?? [:],
        themeName: rawTheme.asStringOrNil,
        themeFiles: themeFiles,
    )
}

@MainActor private var isLightAppearance: Bool { !isSystemAppearanceDark }

/// The values of the theme over the tables 'borders' and 'menuBar' of the config: the theme wins
private func applyTheme(over config: OrderedJson.JsonDict, _ theme: OrderedJson.JsonDict) -> OrderedJson.JsonDict {
    var result = config
    for key in ["borders", "menuBar"] {
        guard case .dict(let themeTable)? = theme[key] else { continue }
        switch config[key] {
            case nil: result[key] = .dict(themeTable)
            case .dict(let configTable)?: result[key] = .dict(mergedTheme(configTable, themeTable))
            default: break
        }
    }
    return result
}

/// The config of the user over another one (the built-in config):
/// - a table is merged key by key, also the tables in it;
/// - anything else (a value, a list) replaces the one of the base, and so does 'theme', whatever it is;
/// - the window rules of the user go before the ones of the base: the first rule that matches is the one that runs.
/// The keys of the user come first, in their order, so the errors are reported in the order of the user's config.
/// A key binding set to false removes the one of the base: see removeUnboundKeys
func mergedConfig(_ base: OrderedJson.JsonDict, _ user: OrderedJson.JsonDict) -> OrderedJson.JsonDict {
    var result: OrderedJson.JsonDict = [:]
    for (key, value) in user {
        switch (key, base[key], value) {
            case (themeKey, _, _): result[key] = value
            case (onWindowDetectedKey, .array(let baseRules)?, .array(let userRules)): result[key] = .array(userRules + baseRules)
            // '{}' is an empty table for Lua: no rules of the user
            case (onWindowDetectedKey, .array?, .dict(let dict)) where dict.isEmpty: result[key] = base[key]
            default: result[key] = mergedValue(base[key], value)
        }
    }
    for (key, value) in base where result[key] == nil {
        result[key] = value
    }
    return result
}

private func mergedValue(_ base: OrderedJson?, _ user: OrderedJson) -> OrderedJson {
    guard case .dict(let baseTable)? = base, case .dict(let userTable) = user else { return user }
    var result: OrderedJson.JsonDict = [:]
    for (key, value) in userTable {
        result[key] = mergedValue(baseTable[key], value)
    }
    for (key, value) in baseTable where result[key] == nil {
        result[key] = value
    }
    return .dict(result)
}

// MARK: - Workspaces

let workspacesKey = "workspaces"
let workspaceKeysKey = "workspaceKeys"
/// In 'onWindowDetected', the place of the rules that 'workspaces' makes for its apps
let workspacesRulesMarker = "workspaces"

/// The keys of an item of 'workspaces', and of 'workspaceKeys'. See: ConfigReferenceTest
let workspaceSpecKeys = ["id", "name", "key", "monitor", "apps"]
let workspaceKeysKeys = ["focus", "move"]

/// One workspace of 'workspaces'
struct WorkspaceSpec: Equatable {
    var id: String
    var name: String? = nil
    var key: String? = nil
    var monitor: OrderedJson? = nil
    var apps: [String] = []
}

/// 'workspaces' and 'workspaceKeys' become the keys that they stand for, in the raw table of the config:
/// - persistentWorkspaces: the ids, in order (unless the config sets it);
/// - workspaceToMonitorForceAssignment: the monitor of each one, 'main' without one (the config's own entries win);
/// - two key bindings of the 'main' mode for each workspace with a key: go to it (workspaceKeys.focus + key) and move
///   the window there (workspaceKeys.move + key). A binding that the config sets wins, and false removes it;
/// - a window rule for each app: tiling, and to its workspace. They take the place of the item 'workspaces' of
///   'onWindowDetected' (the built-in config has it after the rule of the file dialogs), or go first without it.
/// Then the key bindings set to false are removed (see: mergedConfig). Returns the names of the workspaces
func expandWorkspaces(_ raw: inout OrderedJson.JsonDict, _ c: inout ConfigParserContext) -> [String: String] {
    let workspaces = raw[workspacesKey].map { parseWorkspaces($0, .rootKey(workspacesKey), &c) } ?? []
    let keys = parseWorkspaceKeys(raw[workspaceKeysKey], &c)

    if !workspaces.isEmpty {
        if raw[persistentWorkspacesKey] == nil {
            raw[persistentWorkspacesKey] = .array(workspaces.map { .string($0.id) })
        }
        var monitors: OrderedJson.JsonDict = [:]
        for workspace in workspaces { monitors[workspace.id] = workspace.monitor ?? .string("main") }
        let assignmentKey = "workspaceToMonitorForceAssignment"
        if case .dict(let own)? = raw[assignmentKey] {
            raw[assignmentKey] = .dict(mergedTheme(monitors, own))
        } else if raw[assignmentKey] == nil {
            raw[assignmentKey] = .dict(monitors)
        }

        var bindings: OrderedJson.JsonDict = [:]
        for workspace in workspaces {
            guard let key = workspace.key else { continue }
            if let focus = keys.focus {
                bindings["\(focus)-\(key)"] = .array([.string("workspace \(workspace.id)"), .string("mode main")])
            }
            if let move = keys.move {
                bindings["\(move)-\(key)"] = .string("move-node-to-workspace \(workspace.id)")
            }
        }
        if !bindings.isEmpty {
            var modes = raw[modeConfigRootKey]?.asDictOrNil ?? [:]
            var main = modes["main"]?.asDictOrNil ?? [:]
            let own = main["binding"]?.asDictOrNil ?? [:]
            main["binding"] = .dict(mergedTheme(bindings, own))
            modes["main"] = .dict(main)
            raw[modeConfigRootKey] = .dict(modes)
        }
    }

    let appRules: [OrderedJson] = workspaces.flatMap { workspace in
        workspace.apps.map { app -> OrderedJson in
            .dict(["match": .dict(["appId": .string(app)]), "run": .array([.string("layout tiling"), .string("move-node-to-workspace \(workspace.id)")])])
        }
    }
    switch raw[onWindowDetectedKey] {
        case .array(let rules)?:
            let marker = rules.firstIndex { $0.asStringOrNil == workspacesRulesMarker }
            var result = rules
            result.insert(contentsOf: appRules, at: marker ?? 0)
            raw[onWindowDetectedKey] = .array(result.filter { $0.asStringOrNil != workspacesRulesMarker })
        case nil where !appRules.isEmpty:
            raw[onWindowDetectedKey] = .array(appRules)
        default:
            if !appRules.isEmpty { raw[onWindowDetectedKey] = .array(appRules) }
    }

    removeUnboundKeys(&raw)
    return Dictionary(workspaces.compactMap { workspace in workspace.name.map { (workspace.id, $0) } }, uniquingKeysWith: { first, _ in first })
}

/// `['cmd-alt-h'] = false`: the key binding of the built-in config (or of 'workspaces') is removed
private func removeUnboundKeys(_ raw: inout OrderedJson.JsonDict) {
    guard case .dict(var modes)? = raw[modeConfigRootKey] else { return }
    for (name, mode) in modes {
        guard case .dict(var table) = mode, case .dict(let bindings)? = table["binding"] else { continue }
        table["binding"] = .dict(bindings.filter { $0.value != .bool(false) })
        modes[name] = .dict(table)
    }
    raw[modeConfigRootKey] = .dict(modes)
}

private func parseWorkspaces(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [WorkspaceSpec] {
    // '{}' is an empty table for Lua: no workspaces
    if case .dict(let dict) = raw, dict.isEmpty { return [] }
    guard case .array(let items) = raw else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .array, actual: raw.valueType, backtrace))
        return []
    }
    var result: [WorkspaceSpec] = []
    for (index, item) in items.enumerated() {
        let backtrace = backtrace + .index(index)
        guard case .dict(let table) = item else {
            c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: item.valueType, backtrace))
            continue
        }
        var workspace = WorkspaceSpec(id: "")
        for (key, value) in table {
            let backtrace = backtrace + .key(key)
            switch key {
                case "id", "name", "key":
                    guard let string = value.asStringOrNil, !string.isEmpty else {
                        c.errors.append(.init(backtrace, "Expected a string that isn't empty"))
                        continue
                    }
                    switch key {
                        case "id": workspace.id = string
                        case "name": workspace.name = string
                        default: workspace.key = string
                    }
                case "monitor":
                    workspace.monitor = value
                case "apps":
                    switch parseArrayOfStrings(value, backtrace) {
                        case .success(let apps): workspace.apps = apps
                        // '{}': no apps
                        case .failure where value.asDictOrNil?.isEmpty == true: break
                        case .failure(let error): c.errors.append(error)
                    }
                default:
                    c.errors.append(unknownKeyDiagnostic(backtrace))
            }
        }
        if workspace.id.isEmpty {
            if table["id"] == nil { c.errors.append(.init(backtrace, "A workspace needs an 'id': its name in the commands, like 'workspace 1'")) }
            continue
        }
        if result.contains(where: { $0.id == workspace.id }) {
            c.errors.append(.init(backtrace + .key("id"), "The workspace '\(workspace.id)' is already in the list"))
            continue
        }
        result.append(workspace)
    }
    return result
}

/// The modifiers of the key bindings of 'workspaces'. nil: no binding of that kind
private func parseWorkspaceKeys(_ raw: OrderedJson?, _ c: inout ConfigParserContext) -> (focus: String?, move: String?) {
    var result: (focus: String?, move: String?) = ("cmd-alt-ctrl", "cmd-alt-shift")
    guard let raw else { return result }
    guard case .dict(let table) = raw else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.valueType, .rootKey(workspaceKeysKey)))
        return result
    }
    for (key, value) in table {
        let backtrace = ConfigBacktrace.rootKey(workspaceKeysKey) + .key(key)
        let modifiers: String?
        switch value {
            case .string(let string) where !string.isEmpty: modifiers = string
            case .bool(false): modifiers = nil
            default:
                c.errors.append(.init(backtrace, "Expected the modifiers of the keys, like 'cmd-alt-ctrl', or false: no key bindings"))
                continue
        }
        switch key {
            case "focus": result.focus = modifiers
            case "move": result.move = modifiers
            default: c.errors.append(unknownKeyDiagnostic(backtrace))
        }
    }
    return result
}

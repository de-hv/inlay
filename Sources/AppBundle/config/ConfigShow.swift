import Common
import Foundation

/// 'inlay config --show': the config in use, as the calls of Lua that make it (inlay.config, inlay.workspace,
/// inlay.bind, inlay.window_rule…), each value with where it comes from (the config of the user, the theme, the
/// built-in config of Inlay, or the default of the code) and its possible values (from the config reference).
/// It reads the files again, the same way readConfig does: see layeredConfig.
/// 'inlay config --files' and '--file <name>': the files that the config is made of
enum ConfigShow {
    enum Origin: Equatable {
        /// The config of the user. The file and the line, when they are known
        case yours(String?)
        case theme(String?)
        case inlay
        case `default`

        var text: String {
            switch self {
                case .yours(let place?): "yours (\(place))"
                case .yours(nil): "yours"
                case .theme(let name?): "theme \(name)"
                case .theme(nil): "theme"
                case .inlay: "Inlay"
                case .default: "default"
            }
        }
    }

    /// A value to print: the value of a layer, or the default of the reference, written in Lua already
    indirect enum Node {
        case table([(key: String, node: Node)])
        case value(OrderedJson, Origin)
        case literal(String, Origin)
        /// The window rules, or the workspaces: each one with its origin
        case rules([(rule: OrderedJson, origin: Origin)])
    }

    /// The tables whose keys are names that the user chooses: their keys in the reference are examples
    static let freeFormTables = ["mode", "borders.modeColors", "exec.envVars", "keyMapping.keyNotationToKeyCode", "workspaceToMonitorForceAssignment", "animations.curves"]

    /// The names of the functions that --show takes for the keys they set
    static let functionKeys = ["bind": "mode", "unbind": "mode", "window_rule": onWindowDetectedKey, "workspace": workspacesKey]

    /// The config of the user, and the layers that it makes with the built-in config and the theme
    @MainActor
    private static func load() -> (show: Show, lua: LuaConfig?, layers: LayeredConfig, isBuiltIn: Bool) {
        let reference = (try? ConfigReference.load().get()) ?? ConfigReference("")
        let isBuiltIn = configUrl == builtInConfigUrl
        let lua: LuaConfig? = isBuiltIn ? nil : LuaConfigLoader.load(file: configUrl)
        let builtIn = LuaConfigLoader.load(file: builtInConfigUrl)
        let files = (lua?.files ?? []).filter { $0.text != nil }
        var c = ConfigParserContext(errors: [], warnings: [])
        var layers = layeredConfig(
            user: (isBuiltIn ? builtIn.table : lua?.table) ?? [:],
            base: isBuiltIn ? nil : builtIn.table,
            configFolder: isBuiltIn ? nil : configUrl.deletingLastPathComponent(),
            &c,
        )
        if isBuiltIn { layers = builtInLayers(layers) }
        let show = Show(layers: layers, reference: reference, files: files, origins: lua?.origins ?? [:])
        return (show, lua, layers, isBuiltIn)
    }

    @MainActor
    static func text(key: String?, mine: Bool, keys: Bool, json: Bool) -> Result<String, String> {
        let (show, lua, _, isBuiltIn) = load()
        if mine { return .success(show.mine(fileNames: lua?.files.filter { $0.text != nil }.map { relativeName($0.url) } ?? [])) }
        let name = key.map { functionKeys[$0.removingInlayPrefix] ?? $0.removingInlayPrefix } ?? nil
        let path = name.map { $0.split(separator: ".").map(String.init) } ?? []
        guard let node = show.tree.find(path) else {
            let similar = show.tree.leafPaths([]).map { $0.joined(separator: ".") }.filter { $0.localizedCaseInsensitiveContains(path.last ?? "") }
            let hint = similar.isEmpty ? "'config --show --keys' lists every key" : "Did you mean: \(similar.prefix(8).joined(separator: ", "))"
            return .failure("The config has no key or table '\(path.joined(separator: "."))'. \(hint)")
        }
        if keys { return .success(node.leafPaths(path).map(dotted).joined(separator: "\n")) }
        if json { return .success(jsonText(node.json, indent: 0)) }
        let header = key == nil
            ? """
            -- The config in use: \(isBuiltIn ? "the built-in config of Inlay (there is no config of yours)" : "\(configUrl.path.tildePath) over the built-in config of Inlay")
            -- Where each value comes from: yours · theme · Inlay · default. 'inlay config --explain <key>' tells what a key does,
            -- and 'inlay config --files' lists the files

            """
            : ""
        return .success(header + show.render(path: path, node: node))
    }

    // MARK: - --files, --file

    /// The files of the config in use: the built-in config and the theme, in the app, and the ones of the user
    @MainActor
    static func filesText() -> String {
        let (_, lua, layers, isBuiltIn) = load()
        var lines: [String] = []
        if layers.base != nil || isBuiltIn { lines.append("Inlay   \(builtInConfigUrl.path.tildePath)") }
        if let name = layers.themeName {
            let users = layers.themeFiles.first { $0.url?.lastPathComponent == name + ".lua" && $0.text != nil }?.url
            let builtIn = builtInThemesUrl.appending(component: name + ".lua")
            if let url = users ?? (FileManager.default.fileExists(atPath: builtIn.path) ? builtIn : nil) {
                lines.append("theme   \(url.path.tildePath)")
            }
        }
        guard let lua, !isBuiltIn else {
            lines.append("yours   none: the config in use is the built-in config of Inlay")
            return lines.joined(separator: "\n")
        }
        let real = configUrl.resolvingSymlinksInPath()
        lines.append("yours   \(configUrl.path.tildePath)" + (real.path != configUrl.path ? "  → \(real.path.tildePath)" : ""))
        let modules = lua.files.dropFirst()
        let width = modules.map { relativeName($0.url) .count }.max() ?? 0
        for (index, module) in modules.enumerated() {
            let branch = index == modules.count - 1 ? "└─" : "├─"
            let name = relativeName(module.url)
            let from = module.requiredAt.map { "require at \($0)" } ?? ""
            let missing = module.text == nil ? "  (missing)" : ""
            lines.append("          \(branch) \(name.padding(toLength: width, withPad: " ", startingAt: 0))   \(from)\(missing)")
        }
        for theme in layers.themeFiles where theme.text != nil && !lines.contains(where: { $0.contains(theme.url?.path.tildePath ?? "\u{0}") }) {
            lines.append("          ·  \(relativeName(theme.url))   theme")
        }
        lines.append("")
        lines.append("'inlay config --file <name>' prints one: builtin-config · themes/<name> · \(modules.first.map { relativeName($0.url).replacingOccurrences(of: ".lua", with: "") } ?? "inlay")")
        return lines.joined(separator: "\n")
    }

    /// The text of a file of the config: 'builtin-config', 'themes/<name>' (of the user, or else of Inlay), or a file
    /// of the folder of the config ('inlay', 'binds', 'conf/binds', with or without .lua)
    @MainActor
    static func fileText(_ name: String) -> Result<String, String> {
        let bare = name.hasSuffix(".lua") ? String(name.dropLast(4)) : name
        let folder = configUrl == builtInConfigUrl ? nil : configUrl.deletingLastPathComponent()
        var candidates: [URL] = []
        if bare == "builtin-config" { candidates.append(builtInConfigUrl) }
        if let theme = bare.removingPrefix(themesFolderName + "/") {
            if let folder { candidates.append(folder.appending(path: "\(themesFolderName)/\(theme).lua")) }
            candidates.append(builtInThemesUrl.appending(component: theme + ".lua"))
        }
        if let folder, !bare.contains("..") { candidates.append(folder.appending(path: bare.replacingOccurrences(of: ".", with: "/") + ".lua")) }
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return .success("-- \(url.path.tildePath)\n\n" + text.trimmingCharacters(in: .newlines))
            }
        }
        return .failure("There is no file '\(name)' in the config. 'inlay config --files' lists them")
    }

    /// The name of a file of the config folder, as require names it: 'binds.lua', 'conf/binds.lua'
    @MainActor
    static func relativeName(_ url: URL?) -> String {
        guard let url else { return "inlay.lua" }
        let folder = configUrl.deletingLastPathComponent().path + "/"
        return url.path.hasPrefix(folder) ? String(url.path.dropFirst(folder.count)) : url.lastPathComponent
    }

    /// Without a config of the user, the built-in config is the config: its values come from Inlay
    @MainActor private static func builtInLayers(_ layers: LayeredConfig) -> LayeredConfig {
        var result = layers
        result.base = layers.user
        result.user = [:]
        return result
    }

    static func dotted(_ path: [String]) -> String {
        path.enumerated().map { index, key in
            isIdentifier(key) ? (index == 0 ? key : "." + key) : "['\(key)']"
        }.joined()
    }
}

private struct Show {
    let layers: LayeredConfig
    let reference: ConfigReference
    let files: [LuaConfigFile]
    /// Where the calls of the user set each value. See: LuaConfig.origins
    let origins: [[String]: String]
    let entries: [String: ConfigReference.Entry]
    let order: [String]
    let tree: ConfigShow.Node

    @MainActor
    init(layers: LayeredConfig, reference: ConfigReference, files: [LuaConfigFile], origins: [[String]: String]) {
        self.layers = layers
        self.reference = reference
        self.files = files
        self.origins = origins
        let all = reference.entries
        var entries: [String: ConfigReference.Entry] = [:]
        for entry in all where entries[entry.path] == nil { entries[entry.path] = entry }
        self.entries = entries
        self.order = all.map(\.path)
        let merged = isSystemAppearanceDark ? layers.dark : (layers.light ?? layers.dark)
        var tree = ConfigShow.Node.table([])
        // The values of the layers…
        tree = Show.build(.dict(merged), [], layers: layers, origins: origins)
        // … and the defaults of the reference for the keys that no layer sets
        // A key that is only documented (commented out) and has a default: 'theme'
        for entry in all where !entry.isTable {
            guard let fallback = entry.fallback else { continue }
            let path = entry.path.split(separator: ".").map(String.init)
            if ConfigShow.freeFormTables.contains(where: { entry.path.hasPrefix($0 + ".") }) { continue }
            if entry.path.hasPrefix("onWindowDetected") || entry.path.hasPrefix("workspaces") { continue }
            // Made from 'workspaces'
            if merged[workspacesKey] != nil, [persistentWorkspacesKey, "workspaceToMonitorForceAssignment"].contains(entry.path) { continue }
            tree.insertIfMissing(path, .literal(fallback, .default))
        }
        self.tree = tree.sorted(by: order)
    }

    @MainActor
    private static func build(_ value: OrderedJson, _ path: [String], layers: LayeredConfig, origins: [[String]: String]) -> ConfigShow.Node {
        // The lists whose items come from calls: each item with the place of its call
        if path == [onWindowDetectedKey] || path == [workspacesKey], case .array(let items) = value {
            let key = path[0]
            let userCount = layers.user[key]?.asArrayOrNil?.count ?? 0
            let isFromInlay = key == onWindowDetectedKey ? layers.base?[key] != nil : layers.user[key] == nil
            return .rules(items.enumerated().map { index, item in
                if index < userCount && !(key == workspacesKey && isFromInlay) {
                    return (item, .yours(origins[[key, String(index + 1)]] ?? Show.place(path, origins)))
                }
                return (item, isFromInlay || layers.base != nil ? .inlay : Show.origin(path, layers: layers, origins: origins))
            })
        }
        // A table of values (not a list): its keys one by one. 'theme' is one value, whatever it is
        if case .dict(let dict) = value, !dict.isEmpty, path != [themeKey] {
            return .table(dict.map { key, child in (key, build(child, path + [key], layers: layers, origins: origins)) })
        }
        return .value(value, origin(path, layers: layers, origins: origins))
    }

    @MainActor
    static func origin(_ path: [String], layers: LayeredConfig, origins: [[String]: String]) -> ConfigShow.Origin {
        if lookup(.dict(layers.user), path) != nil { return .yours(place(path, origins)) }
        if lookup(.dict(layers.themeValues), path) != nil { return .theme(layers.themeName) }
        if let base = layers.base, lookup(.dict(base), path) != nil { return .inlay }
        return .default
    }

    static func lookup(_ value: OrderedJson, _ path: [String]) -> OrderedJson? {
        guard let first = path.first else { return value }
        guard case .dict(let dict) = value, let child = dict[first] else { return nil }
        return lookup(child, Array(path.dropFirst()))
    }

    /// 'binds.lua:12': the call that set the value, or the table it is in
    static func place(_ path: [String], _ origins: [[String]: String]) -> String? {
        var path = path
        while !path.isEmpty {
            if let place = origins[path] { return place }
            path.removeLast()
        }
        return nil
    }

    // MARK: - Lua

    /// The part of the config at the path, as the calls that make it. An empty path: all of it
    func render(path: [String], node: ConfigShow.Node) -> String {
        guard let first = path.first else {
            guard case .table(let children) = node else { return "" }
            var sections: [[String]] = []
            if let theme = children.first(where: { $0.key == themeKey })?.node { sections.append(renderTheme(theme)) }
            let config = children.filter { ![themeKey, workspacesKey, "mode", onWindowDetectedKey].contains($0.key) }
            if !config.isEmpty {
                sections.append(["inlay.config({"] + config.flatMap { renderEntry($0.key, $0.node, [$0.key], 1) } + ["})"])
            }
            if let workspaces = children.first(where: { $0.key == workspacesKey })?.node { sections.append(renderCalls(workspacesKey, workspaces)) }
            if let modes = children.first(where: { $0.key == "mode" })?.node { sections.append(renderBindings(["mode"], modes)) }
            if let rules = children.first(where: { $0.key == onWindowDetectedKey })?.node { sections.append(renderCalls(onWindowDetectedKey, rules)) }
            return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
        }
        switch first {
            case themeKey where path.count == 1: return renderTheme(node).joined(separator: "\n")
            case workspacesKey where path.count == 1, onWindowDetectedKey where path.count == 1:
                return renderCalls(first, node).joined(separator: "\n")
            case "mode": return renderBindings(path, node).joined(separator: "\n")
            default: break
        }
        // The tables that the part is in, so that it is clear where it goes
        var lines = ["inlay.config({"]
        for (depth, key) in path.dropLast().enumerated() {
            lines.append(String(repeating: "  ", count: depth + 1) + "\(luaKey(key)) = {")
        }
        lines += renderEntry(path.last ?? "", node, path, path.count)
        for depth in (0 ..< max(path.count - 1, 0)).reversed() {
            lines.append(String(repeating: "  ", count: depth + 1) + "},")
        }
        lines.append("})")
        return lines.joined(separator: "\n")
    }

    private func renderTheme(_ node: ConfigShow.Node) -> [String] {
        switch node {
            case .value(let value, let origin): return withComment("inlay.theme(\(lua(value, depth: 0)))", origin, [themeKey])
            case .literal(let text, let origin): return withComment("inlay.theme(\(text))", origin, [themeKey])
            default: return []
        }
    }

    /// inlay.workspace(…) or inlay.window_rule(…), one per item
    private func renderCalls(_ key: String, _ node: ConfigShow.Node) -> [String] {
        let function = key == workspacesKey ? "inlay.workspace" : "inlay.window_rule"
        var lines: [String] = []
        if key == onWindowDetectedKey {
            lines.append("-- The window rules: the first one that matches runs. 'workspaces': the rules of the apps of the workspaces")
        }
        switch node {
            case .rules(let items):
                for (item, origin) in items { lines.append("\(function)(\(lua(item, depth: 0)))  -- \(origin.text)") }
            case .value(.array(let items), let origin):
                for item in items { lines.append("\(function)(\(lua(item, depth: 0)))  -- \(origin.text)") }
            case .literal(let text, let origin):
                lines.append("-- \(function): none. \(key) = \(text)  -- \(origin.text)")
            default: break
        }
        return lines
    }

    /// inlay.bind(…) and inlay.unbind(…) of the modes under the path: 'mode', 'mode.service', 'mode.main.binding.alt-h'
    private func renderBindings(_ path: [String], _ node: ConfigShow.Node) -> [String] {
        var lines: [String] = []
        if layers.dark[workspacesKey] != nil, path.count < 3 || path[1] == "main" {
            lines.append("-- With the key bindings that the workspaces make (workspaceKeys + the key of each workspace)")
        }
        func visit(_ path: [String], _ node: ConfigShow.Node) {
            switch node {
                case .table(let children):
                    // The main mode first
                    let sorted = path.count == 1 ? children.filter { $0.key == "main" } + children.filter { $0.key != "main" } : children
                    for (key, child) in sorted { visit(path + [key], child) }
                case .value(let value, let origin) where path.count == 4:
                    let mode = path[1] == "main" ? "" : ", { mode = \(lua(.string(path[1]), depth: 0)) }"
                    let keys = lua(.string(path[3]), depth: 0)
                    let call = value == .bool(false) ? "inlay.unbind(\(keys)\(mode))" : "inlay.bind(\(keys), \(lua(value, depth: 0))\(mode))"
                    lines += withComment(call, origin, path)
                case .value(let value, let origin):
                    lines += withComment("-- \(ConfigShow.dotted(path)) = \(lua(value, depth: 0))", origin, path)
                default: break
            }
        }
        visit(path, node)
        return lines
    }

    private func renderEntry(_ key: String, _ node: ConfigShow.Node, _ path: [String], _ depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        switch node {
            case .table(let children):
                var lines = ["\(indent)\(luaKey(key)) = {"]
                for (childKey, child) in children { lines += renderEntry(childKey, child, path + [childKey], depth + 1) }
                lines.append("\(indent)},")
                return lines
            case .value(.array(let items), let origin) where items.contains(where: { $0.asDictOrNil != nil }):
                // A list of tables: one per line
                return withComment("\(indent)\(luaKey(key)) = {", origin, path) + items.map { "\(indent)  \(lua($0, depth: depth + 1))," } + ["\(indent)},"]
            case .value(let value, let origin):
                return withComment("\(indent)\(luaKey(key)) = \(lua(value, depth: depth)),", origin, path)
            case .literal(let text, let origin):
                return withComment("\(indent)\(luaKey(key)) = \(text),", origin, path)
            case .rules(let rules):
                var lines = ["\(indent)\(luaKey(key)) = {"]
                for (rule, origin) in rules {
                    lines.append("\(indent)  \(lua(rule, depth: depth + 1)),  -- \(origin.text)")
                }
                lines.append("\(indent)},")
                return lines
        }
    }

    private func withComment(_ line: String, _ origin: ConfigShow.Origin, _ path: [String]) -> [String] {
        var comment = origin.text
        if let possible = entries[path.joined(separator: ".")]?.possibleValues { comment += " · " + possible }
        // A long value: the comment goes above it
        if line.count + comment.count > 140 {
            let indent = String(line.prefix { $0 == " " })
            return ["\(indent)-- \(comment)", line]
        }
        let padded = line.padding(toLength: max(line.count, 52), withPad: " ", startingAt: 0)
        return ["\(padded)  -- \(comment)"]
    }

    // MARK: - --mine

    /// The calls of the user, by file in the order they were read, and by line: the ones that change something,
    /// then the ones that repeat the base
    @MainActor
    func mine(fileNames: [String]) -> String {
        let user = layers.user
        guard !user.isEmpty else { return "-- There is no config of yours: the config in use is the built-in config of Inlay" }
        var effective: [(place: String?, line: String)] = []
        var noEffect: [(place: String?, line: String)] = []
        for path in leafPaths(.dict(user), []) where path != [builtInConfigKey] {
            guard let value = Show.lookup(.dict(user), path) else { continue }
            if path == [onWindowDetectedKey] || path == [workspacesKey], case .array(let items) = value {
                let function = path[0] == workspacesKey ? "inlay.workspace" : "inlay.window_rule"
                for (index, item) in items.enumerated() {
                    effective.append((origins[[path[0], String(index + 1)]] ?? Show.place(path, origins), "\(function)(\(lua(item, depth: 0)))"))
                }
                continue
            }
            let entry = (Show.place(path, origins), call(path, value))
            if repeatsTheBase(path, value) { noEffect.append(entry) } else { effective.append(entry) }
        }
        let fileOrder = fileNames
        func grouped(_ entries: [(place: String?, line: String)]) -> [String] {
            func split(_ place: String?) -> (file: String, line: Int) {
                guard let place else { return ("", 0) }
                let parts = place.split(separator: ":")
                return (String(parts.first ?? ""), parts.count > 1 ? Int(parts[1]) ?? 0 : 0)
            }
            let sorted = entries.enumerated().sorted { a, b in
                let (fa, la) = split(a.element.place), (fb, lb) = split(b.element.place)
                let (ra, rb) = (fileOrder.firstIndex(of: fa) ?? Int.max, fileOrder.firstIndex(of: fb) ?? Int.max)
                return (ra, la, a.offset) < (rb, lb, b.offset)
            }.map(\.element)
            var lines: [String] = []
            var current: String? = nil
            for entry in sorted {
                let file = split(entry.place).file
                if file != current {
                    lines.append("-- \(file.isEmpty ? "elsewhere" : file)")
                    current = file
                }
                lines.append(entry.line + (entry.place.map { "  -- \($0)" } ?? ""))
            }
            return lines
        }
        var out = ["-- Yours, in \(fileNames.joined(separator: ", ")): \(effective.count) value(s)"] + grouped(effective)
        if !noEffect.isEmpty {
            out += ["", "-- The same as without them: nothing changes if you delete them (\(noEffect.count))"] + grouped(noEffect)
        }
        return out.joined(separator: "\n")
    }

    /// The call that sets one value: inlay.bind for a key binding, inlay.theme, inlay.config for the rest
    private func call(_ path: [String], _ value: OrderedJson) -> String {
        if path == [themeKey] { return "inlay.theme(\(lua(value, depth: 0)))" }
        if path.count == 4, path[0] == "mode", path[2] == "binding" {
            let mode = path[1] == "main" ? "" : ", { mode = \(lua(.string(path[1]), depth: 0)) }"
            let keys = lua(.string(path[3]), depth: 0)
            return value == .bool(false) ? "inlay.unbind(\(keys)\(mode))" : "inlay.bind(\(keys), \(lua(value, depth: 0))\(mode))"
        }
        let table = path.reversed().reduce(lua(value, depth: 0)) { inner, key in "{ \(luaKey(key)) = \(inner) }" }
        return "inlay.config(\(table))"
    }

    /// The value of the user is the one that the config would have without it
    private func repeatsTheBase(_ path: [String], _ value: OrderedJson) -> Bool {
        // The rules of the user go before the ones of Inlay: they always add something
        if path == [onWindowDetectedKey] { return false }
        if path == [themeKey] { return value == (layers.base?[themeKey] ?? .string(defaultThemeName)) }
        if let below = Show.lookup(.dict(layers.themeValues), path) ?? layers.base.flatMap({ Show.lookup(.dict($0), path) }) {
            return below == value
        }
        if let fallback = entries[path.joined(separator: ".")]?.fallback {
            return fallback == lua(value, depth: 0)
        }
        return false
    }

    /// The paths of the values: a table that isn't a list is gone into; a list, 'theme' and a value are one
    private func leafPaths(_ value: OrderedJson, _ path: [String]) -> [[String]] {
        if case .dict(let dict) = value, !dict.isEmpty, path != [themeKey] {
            return dict.flatMap { key, child in leafPaths(child, path + [key]) }
        }
        return [path]
    }
}

extension String {
    /// 'bind' for 'inlay.bind' and 'inlay.bind()'
    fileprivate var removingInlayPrefix: String {
        (hasPrefix("inlay.") ? String(dropFirst(6)) : self).replacingOccurrences(of: "()", with: "")
    }

    fileprivate func removingPrefix(_ prefix: String) -> String? { hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil }
}

extension ConfigShow.Node {
    func find(_ path: [String]) -> ConfigShow.Node? {
        guard let first = path.first else { return self }
        guard case .table(let children) = self, let child = children.first(where: { $0.key == first })?.node else { return nil }
        return child.find(Array(path.dropFirst()))
    }

    mutating func insertIfMissing(_ path: [String], _ node: ConfigShow.Node) {
        guard let first = path.first, case .table(var children) = self else { return }
        if path.count == 1 {
            if !children.contains(where: { $0.key == first }) { children.append((first, node)) }
        } else if let index = children.firstIndex(where: { $0.key == first }) {
            // A value that isn't a table (a list, a number of points for each monitor) stays as it is
            guard case .table = children[index].node else { return }
            children[index].node.insertIfMissing(Array(path.dropFirst()), node)
        } else {
            var table = ConfigShow.Node.table([])
            table.insertIfMissing(Array(path.dropFirst()), node)
            children.append((first, table))
        }
        self = .table(children)
    }

    /// The keys in the order of the reference; the ones that it doesn't have, after them, in alphabetical order
    func sorted(by order: [String], _ path: [String] = []) -> ConfigShow.Node {
        guard case .table(let children) = self else { return self }
        func rank(_ key: String) -> Int {
            let full = (path + [key]).joined(separator: ".")
            return order.firstIndex { $0 == full || $0.hasPrefix(full + ".") } ?? Int.max
        }
        let sorted = children.map { ($0.key, $0.node.sorted(by: order, path + [$0.key])) }
            .sorted { lhs, rhs in
                let (l, r) = (rank(lhs.0), rank(rhs.0))
                return l != r ? l < r : lhs.0 < rhs.0
            }
        return .table(sorted.map { (key: $0.0, node: $0.1) })
    }

    func leafPaths(_ path: [String]) -> [[String]] {
        switch self {
            case .table(let children): children.flatMap { $0.node.leafPaths(path + [$0.key]) }
            default: [path]
        }
    }

    var json: OrderedJson {
        switch self {
            case .table(let children):
                var dict = OrderedJson.JsonDict()
                for (key, child) in children { dict[key] = child.json }
                return .dict(dict)
            case .value(let value, _): return value
            case .literal(let text, _): return jsonOfLiteral(text)
            case .rules(let rules): return .array(rules.map(\.rule))
        }
    }
}

/// A default of the reference, written in Lua: a number, a boolean or a string. Anything else as text
private func jsonOfLiteral(_ text: String) -> OrderedJson {
    if text == "true" { return .bool(true) }
    if text == "false" { return .bool(false) }
    if let int = Int64(text) { return .int(int) }
    if let double = Double(text) { return .double(double) }
    if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") { return .string(String(text.dropFirst().dropLast())) }
    if text == "{}" { return .array([]) }
    return .string(text)
}

func isIdentifier(_ key: String) -> Bool {
    key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
}

private func luaKey(_ key: String) -> String {
    isIdentifier(key) ? key : "['\(key.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'"))']"
}

/// The value written in Lua, on one line
func lua(_ value: OrderedJson, depth: Int) -> String {
    switch value {
        case .null: return "nil"
        case .bool(let bool): return bool ? "true" : "false"
        case .int(let int): return String(int)
        case .double(let double): return String(double)
        case .string(let string):
            let escaped = string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n")
            return "'\(escaped)'"
        case .array(let items):
            return items.isEmpty ? "{}" : "{ " + items.map { lua($0, depth: depth) }.joined(separator: ", ") + " }"
        case .dict(let dict):
            // The keys that people write first, first: the id of a workspace, the match of a rule
            let first = ["id", "name", "key", "monitor", "apps", "match", "checkFurtherCallbacks", "run"]
            let keys = dict.keys.sorted { (first.firstIndex(of: $0) ?? Int.max, $0) < (first.firstIndex(of: $1) ?? Int.max, $1) }
            return dict.isEmpty ? "{}" : "{ " + keys.map { "\(luaKey($0)) = \(lua(dict[$0]!, depth: depth))" }.joined(separator: ", ") + " }"
    }
}

/// JSON with the keys in their order (an OrderedDictionary encodes itself as an array of keys and values)
private func jsonText(_ value: OrderedJson, indent: Int) -> String {
    let pad = String(repeating: "  ", count: indent + 1)
    let end = String(repeating: "  ", count: indent)
    func string(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
    switch value {
        case .null: return "null"
        case .bool(let bool): return bool ? "true" : "false"
        case .int(let int): return String(int)
        case .double(let double): return String(double)
        case .string(let text): return string(text)
        case .array(let items):
            return items.isEmpty ? "[]" : "[\n" + items.map { pad + jsonText($0, indent: indent + 1) }.joined(separator: ",\n") + "\n\(end)]"
        case .dict(let dict):
            return dict.isEmpty ? "{}" : "{\n" + dict.map { pad + string($0.key) + ": " + jsonText($0.value, indent: indent + 1) }.joined(separator: ",\n") + "\n\(end)}"
    }
}

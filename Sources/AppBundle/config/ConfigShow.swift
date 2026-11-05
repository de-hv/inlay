import Common
import Foundation

/// 'inlay config --show': the config in use, as Lua, each value with where it comes from (the config of the user,
/// the theme, the built-in config of Inlay, or the default of the code) and its possible values (from the
/// config reference). It reads the files again, the same way readConfig does: see layeredConfig
enum ConfigShow {
    enum Origin: Equatable {
        /// The config of the user. The file and the line, when they can be found
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
        /// The window rules: each one with its origin
        case rules([(rule: OrderedJson, origin: Origin)])
    }

    /// The tables whose keys are names that the user chooses: their keys in the reference are examples
    static let freeFormTables = ["mode", "borders.modeColors", "exec.envVars", "keyMapping.keyNotationToKeyCode", "workspaceToMonitorForceAssignment", "animations.curves"]

    @MainActor
    static func text(key: String?, mine: Bool, keys: Bool, json: Bool) -> Result<String, String> {
        let reference = (try? ConfigReference.load().get()) ?? ConfigReference("")
        let isBuiltIn = configUrl == builtInConfigUrl
        let lua: LuaConfig? = isBuiltIn ? nil : LuaConfigLoader.load(file: configUrl)
        let files = (lua?.files ?? []).filter { $0.text != nil }
        var c = ConfigParserContext(errors: [], warnings: [])
        let layers = layeredConfig(
            user: lua?.table ?? [:],
            base: isBuiltIn ? nil : builtInConfigTable,
            configFolder: isBuiltIn ? nil : configUrl.deletingLastPathComponent(),
            &c,
        )
        let show = Show(layers: isBuiltIn ? builtInLayers(layers) : layers, reference: reference, files: files)
        if mine { return .success(show.mine(fileNames: files.compactMap { $0.url?.lastPathComponent })) }
        let path = key.map { $0.split(separator: ".").map(String.init) } ?? []
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
            -- Where each value comes from: yours · theme · Inlay · default. 'inlay config --explain <key>' tells what a key does

            """
            : ""
        return .success(header + show.render(path: path, node: node))
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
    let entries: [String: ConfigReference.Entry]
    let order: [String]
    let tree: ConfigShow.Node

    @MainActor
    init(layers: LayeredConfig, reference: ConfigReference, files: [LuaConfigFile]) {
        self.layers = layers
        self.reference = reference
        self.files = files
        let all = reference.entries
        var entries: [String: ConfigReference.Entry] = [:]
        for entry in all where entries[entry.path] == nil { entries[entry.path] = entry }
        self.entries = entries
        self.order = all.map(\.path)
        let merged = isSystemAppearanceDark ? layers.dark : (layers.light ?? layers.dark)
        var tree = ConfigShow.Node.table([])
        // The values of the layers…
        tree = Show.build(.dict(merged), [], layers: layers, files: files)
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
    private static func build(_ value: OrderedJson, _ path: [String], layers: LayeredConfig, files: [LuaConfigFile]) -> ConfigShow.Node {
        if path == [onWindowDetectedKey], case .array(let rules) = value {
            let userCount = layers.user[onWindowDetectedKey]?.asArrayOrNil?.count ?? 0
            let origin = Show.origin(path, layers: layers, files: files)
            return .rules(rules.enumerated().map { index, rule in
                let isUser = index < userCount
                return (rule, isUser ? origin : (layers.base?[onWindowDetectedKey] != nil ? .inlay : origin))
            })
        }
        // A table of values (not a list): its keys one by one. 'theme' is one value, whatever it is
        if case .dict(let dict) = value, !dict.isEmpty, path != [themeKey] {
            return .table(dict.map { key, child in (key, build(child, path + [key], layers: layers, files: files)) })
        }
        return .value(value, origin(path, layers: layers, files: files))
    }

    @MainActor
    static func origin(_ path: [String], layers: LayeredConfig, files: [LuaConfigFile]) -> ConfigShow.Origin {
        if lookup(.dict(layers.user), path) != nil { return .yours(place(path, files)) }
        if lookup(.dict(layers.themeValues), path) != nil { return .theme(layers.themeName) }
        if let base = layers.base, lookup(.dict(base), path) != nil { return .inlay }
        return .default
    }

    static func lookup(_ value: OrderedJson, _ path: [String]) -> OrderedJson? {
        guard let first = path.first else { return value }
        guard case .dict(let dict) = value, let child = dict[first] else { return nil }
        return lookup(child, Array(path.dropFirst()))
    }

    /// 'binds.lua:12': the first line of the files of the config that sets the last key of the path
    static func place(_ path: [String], _ files: [LuaConfigFile]) -> String? {
        guard let key = path.last else { return nil }
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = isIdentifier(key) ? "(^|[^A-Za-z0-9_.'\"])\(escaped)\\s*=" : "\\[\\s*['\"]\(escaped)['\"]\\s*\\]\\s*="
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        for file in files {
            guard let text = file.text, let name = file.url?.lastPathComponent else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = String(line)
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("--") { continue }
                if regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil { return "\(name):\(index + 1)" }
            }
        }
        return nil
    }

    // MARK: - Lua

    func render(path: [String], node: ConfigShow.Node) -> String {
        // The tables that the part is in, so that it is clear where it goes
        var lines: [String] = []
        for (depth, key) in path.dropLast().enumerated() {
            lines.append(String(repeating: "  ", count: depth) + "\(luaKey(key)) = {")
        }
        let depth = max(path.count - 1, 0)
        if let key = path.last {
            lines += renderEntry(key, node, path, depth)
        } else if case .table(let children) = node {
            lines.append("return {")
            for (key, child) in children { lines += renderEntry(key, child, [key], 1) }
            lines.append("}")
        }
        for depth in (0 ..< max(path.count - 1, 0)).reversed() {
            lines.append(String(repeating: "  ", count: depth) + "},")
        }
        return lines.joined(separator: "\n")
    }

    private func renderEntry(_ key: String, _ node: ConfigShow.Node, _ path: [String], _ depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        switch node {
            case .table(let children):
                var lines = ["\(indent)\(luaKey(key)) = {"]
                if path == ["mode", "main", "binding"], layers.dark[workspacesKey] != nil {
                    lines.append("\(indent)  -- with the ones that 'workspaces' makes (workspaceKeys + the key of each workspace)")
                }
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
                if path == [onWindowDetectedKey] {
                    lines.append("\(indent)  -- the first one that matches runs. 'workspaces': the rules of the apps of the workspaces")
                }
                for (rule, origin) in rules {
                    lines.append("\(indent)  \(lua(rule, depth: depth + 1)),  -- \(origin.text)")
                }
                lines.append("\(indent)},")
                return lines
        }
    }

    private func withComment(_ line: String, _ origin: ConfigShow.Origin, _ path: [String]) -> [String] {
        let generalized = generalizedPath(path)
        var comment = origin.text
        if let possible = entries[generalized]?.possibleValues { comment += " · " + possible }
        // A long value: the comment goes above it
        if line.count + comment.count > 140 {
            let indent = String(line.prefix { $0 == " " })
            return ["\(indent)-- \(comment)", line]
        }
        let padded = line.padding(toLength: max(line.count, 52), withPad: " ", startingAt: 0)
        return ["\(padded)  -- \(comment)"]
    }

    private func generalizedPath(_ path: [String]) -> String {
        path.joined(separator: ".")
    }

    // MARK: - --mine

    func mine(fileNames: [String]) -> String {
        let user = layers.user
        guard !user.isEmpty else { return "-- There is no config of yours: the config in use is the built-in config of Inlay" }
        var effective: [String] = []
        var noEffect: [String] = []
        for path in leafPaths(.dict(user), []) where path != [builtInConfigKey] {
            guard let value = Show.lookup(.dict(user), path) else { continue }
            var place = Show.place(path, files).map { "  -- \($0)" } ?? ""
            var line = "\(ConfigShow.dotted(path)) = \(lua(value, depth: 0))"
            if case .array(let items) = value, items.contains(where: { $0.asDictOrNil != nil }) {
                line = "\(ConfigShow.dotted(path)) = {\(place)\n" + items.map { "  \(lua($0, depth: 1))," }.joined(separator: "\n") + "\n}"
                place = ""
            }
            if repeatsTheBase(path, value) {
                noEffect.append(line + place)
            } else {
                effective.append(line + place)
            }
        }
        var out = ["-- Yours, in \(fileNames.joined(separator: ", ")): \(effective.count) value(s)"] + effective
        if !noEffect.isEmpty {
            out += ["", "-- The same as without them: nothing changes if you delete them (\(noEffect.count))"] + noEffect
        }
        return out.joined(separator: "\n")
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

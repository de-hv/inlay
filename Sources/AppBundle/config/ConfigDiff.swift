import Common
import OrderedCollections
import TOMLDecoder

/// A key of the config whose value is different in two texts of the config. See: ConfigDiff
struct ConfigChange: Equatable, Sendable {
    /// The dotted path: 'borders.width', 'mode.main.binding.cmd-alt-ctrl-j', 'on-window-detected[2].run'
    var key: String
    /// The value as TOML: '4', ''pills'', '['workspace 1', 'mode main']'. nil: the key isn't in that text
    var old: String?
    var new: String?
}

/// What changed between two texts of the config, key by key. Comments, blank lines, the order of the keys and the
/// way a value is written ('inner.horizontal = 8' or '[gaps.inner] horizontal = 8') don't count. Pure
enum ConfigDiff {
    /// The keys whose values differ, sorted by their paths. nil if one of the texts isn't valid TOML
    static func changes(from oldText: String, to newText: String) -> [ConfigChange]? {
        guard let old = flatten(oldText), let new = flatten(newText) else { return nil }
        return Set(old.keys).union(new.keys).sorted().compactMap { key in
            old[key] == new[key] ? nil : ConfigChange(key: key, old: old[key], new: new[key])
        }
    }

    /// Every value of the config by its dotted path. An array of tables ([[on-window-detected]]) is split by index,
    /// any other array is a single value
    static func flatten(_ text: String) -> OrderedDictionary<String, String>? {
        guard let dict = try? [String: Any](TOMLTable(source: text)) else { return nil }
        var errors: [ConfigParseDiagnostic] = []
        guard case .dict(let root) = tomlAnyToOrderedJsonRecursive(any: dict, .emptyRoot, &errors) else { return nil }
        var result: OrderedDictionary<String, String> = [:]
        func visit(_ json: OrderedJson, _ path: String) {
            switch json {
                case .dict(let table):
                    for (key, value) in table { visit(value, path.isEmpty ? tomlKey(key) : path + "." + tomlKey(key)) }
                case .array(let array) where !array.isEmpty && array.allSatisfy({ $0.asDictOrNil != nil }):
                    for (index, value) in array.enumerated() { visit(value, "\(path)[\(index)]") }
                default:
                    result[path] = tomlValue(json)
            }
        }
        visit(.dict(root), "")
        return result
    }

    /// A key as it is written in a dotted path: bare if it can be, quoted otherwise
    private static func tomlKey(_ key: String) -> String {
        let isBare = !key.isEmpty && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return isBare ? key : tomlString(key)
    }

    private static func tomlString(_ string: String) -> String {
        string.contains("'") || string.contains("\n") ? "\"\(string.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"").replacing("\n", with: "\\n"))\"" : "'\(string)'"
    }

    private static func tomlValue(_ json: OrderedJson) -> String {
        switch json {
            case .null: "null"
            case .string(let value): tomlString(value)
            case .int(let value): String(value)
            case .double(let value): String(value)
            case .bool(let value): String(value)
            case .array(let array): "[" + array.map(tomlValue).joined(separator: ", ") + "]"
            case .dict(let table): "{ " + table.map { "\(tomlKey($0.key)) = \(tomlValue($0.value))" }.joined(separator: ", ") + " }"
        }
    }
}

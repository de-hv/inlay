import Foundation
import TOMLDecoder

/// A key of a TOML document: `key` inside of the `[table]`. An empty `table` is the top level
struct TomlKeyPath: Hashable, Sendable, CustomStringConvertible {
    var table: [String]
    var key: String

    init(_ table: [String] = [], _ key: String) {
        self.table = table
        self.key = key
    }

    var full: [String] { table + [key] }
    var description: String { full.joined(separator: ".") }
}

/// A scalar that the patcher can write
enum TomlValue: Equatable, Sendable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case float(Double)

    /// The value as it is written in a TOML document
    var literal: String {
        switch self {
            case .bool(let value): return value ? "true" : "false"
            case .int(let value): return String(value)
            case .float(let value):
                // TOML floats need a fractional part or an exponent
                let string = String(value)
                return string.contains(where: { ".eE".contains($0) }) || !value.isFinite ? string : string + ".0"
            case .string(let value):
                // Literal string, the style of the config examples. It can't hold a quote or a control character
                if !value.unicodeScalars.contains(where: { $0 == "'" || $0.value < 0x20 || $0.value == 0x7F }) {
                    return "'\(value)'"
                }
                var escaped = ""
                for scalar in value.unicodeScalars {
                    switch scalar {
                        case "\"": escaped += "\\\""
                        case "\\": escaped += "\\\\"
                        case "\n": escaped += "\\n"
                        case "\r": escaped += "\\r"
                        case "\t": escaped += "\\t"
                        case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                            let hex = String(scalar.value, radix: 16, uppercase: true)
                            escaped += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                        default: escaped.unicodeScalars.append(scalar)
                    }
                }
                return "\"\(escaped)\""
        }
    }

    /// A value decoded from a TOML document, if it has the same type as `other`
    init?(_ any: Any?, like other: TomlValue) {
        switch other {
            case .string:
                guard let value = any as? String else { return nil }
                self = .string(value)
            case .bool:
                guard let value = any as? Bool else { return nil }
                self = .bool(value)
            case .int:
                guard !(any is Bool), let value = (any as? Int64).flatMap({ Int(exactly: $0) }) else { return nil }
                self = .int(value)
            case .float:
                guard !(any is Bool), let value = any as? Double else { return nil }
                self = .float(value)
        }
    }

    /// Is `any`, a value decoded from a TOML document, the same as this value
    func matches(_ any: Any?) -> Bool {
        switch self {
            case .string(let value): (any as? String) == value
            case .bool(let value): (any as? Bool) == value
            case .int(let value): !(any is Bool) && (any as? Int64).map { Int(exactly: $0) == value } == true
            case .float(let value): !(any is Bool) && (any as? Double) == value
        }
    }
}

/// Edits one key of a TOML document, leaving the rest of the text as it is: comments, order, spacing, line endings.
///
/// - A key that is in its table: only its value is replaced. The comment after it stays
/// - A key that isn't: it is added after the last key of the table
/// - A table that isn't: it is added to the end of the document
/// - A sub-table that isn't, of a table that is (`[borders.mode-colors]` when there is a `[borders]`): it is added
///   after its parent table and the sub-tables that the parent already has, indented like them
/// - A top level key that isn't: it is added after the last top level key, before the first table
/// - `remove` drops the line of the key
///
/// The result is parsed before it is returned, to check that it is valid TOML and that the key has the new value.
///
/// A key written in a way that can't be edited safely is refused: with dots (`menu-bar.theme = 'chips'`),
/// inside of an inline table (`menu-bar = { theme = 'chips' }`), or with a value that spans several lines
enum TomlPatcher {
    enum Reason: Equatable, Sendable {
        /// `a.b = 1`: the key, or its table, is defined with a dotted key
        case dottedKey
        /// `a = { b = 1 }`
        case inlineTable
        /// The value of the key spans several lines, or it isn't a single value
        case multilineValue
        /// The table of the key is an array of tables: `[[a]]`
        case arrayOfTables
        /// The key or its table are defined more than once, or the key is used as a table
        case conflict
    }

    enum Location: Equatable, Sendable {
        /// The key isn't in the document. It can be added
        case absent
        /// The key is in this line (0-based), and its value can be replaced
        case line(Int)
        case unsupported(Reason)
    }

    enum PatchError: Error, Equatable {
        case unsupported(Reason)
        /// The document isn't valid TOML after the change. Most likely, it wasn't valid before either
        case invalidToml(String)
        /// The document is valid after the change, but the key doesn't have the expected value
        case verificationFailed
    }

    static func locate(_ text: String, _ path: TomlKeyPath) -> Location {
        Document(text).locate(path)
    }

    static func set(_ text: String, _ path: TomlKeyPath, _ value: TomlValue) throws(PatchError) -> String {
        var document = Document(text)
        switch document.locate(path) {
            case .unsupported(let reason):
                throw .unsupported(reason)
            case .line(let index):
                // Don't touch a value that is already right, however it is spelled
                if value.matches(decodedValue(text, path)) { return text }
                document.replaceValue(inLine: index, with: value.literal)
            case .absent:
                document.insert(path, value.literal)
        }
        let result = document.text
        guard value.matches(try decode(result, path)) else { throw .verificationFailed }
        return result
    }

    /// Without the key, the default value applies. Nothing changes if the key isn't in the document
    static func remove(_ text: String, _ path: TomlKeyPath) throws(PatchError) -> String {
        var document = Document(text)
        switch document.locate(path) {
            case .unsupported(let reason): throw .unsupported(reason)
            case .absent: return text
            case .line(let index): document.lines.remove(at: index)
        }
        let result = document.text
        guard try decode(result, path) == nil else { throw .verificationFailed }
        return result
    }

    /// The value of the key in a document, as TOMLDecoder gives it. nil if the document isn't valid or doesn't have the key
    static func decodedValue(_ text: String, _ path: TomlKeyPath) -> Any? {
        try? decode(text, path)
    }

    private static func decode(_ text: String, _ path: TomlKeyPath) throws(PatchError) -> Any? {
        value(in: try decode(text), path)
    }

    /// The whole document, as TOMLDecoder gives it
    static func decode(_ text: String) throws(PatchError) -> [String: Any] {
        do {
            return try .init(try TOMLTable(source: text))
        } catch {
            throw .invalidToml(String(describing: error))
        }
    }

    static func value(in root: [String: Any], _ path: TomlKeyPath) -> Any? {
        var node: Any? = root
        for key in path.full {
            node = (node as? [String: Any])?[key]
        }
        return node
    }
}

// MARK: - The document, line by line

extension TomlPatcher {
    struct Line: Equatable {
        var content: String
        /// "\n", "\r\n", or "" in the last line of a document that doesn't end with a line break
        var terminator: String
    }

    /// `key = value`
    struct Entry: Equatable {
        var firstLine: Int
        var lastLine: Int
        /// The table the entry is in. nil inside of an array of tables
        var table: [String]?
        var key: [String]
        /// The value, in `firstLine`. Only for a value that ends in the line it starts in
        var valueRange: Range<String.Index>?
        var isInlineTable: Bool
    }

    struct Header: Equatable {
        var line: Int
        var path: [String]
        var isArrayOfTables: Bool
    }

    struct Document {
        var lines: [Line]
        private(set) var entries: [Entry] = []
        private(set) var headers: [Header] = []

        init(_ text: String) {
            lines = Document.split(text)
            scan()
        }

        var text: String { lines.map { $0.content + $0.terminator }.joined() }

        private static func split(_ text: String) -> [Line] {
            var lines: [Line] = []
            var content = ""
            // "\r\n" is one Character
            for character in text {
                if character == "\n" || character == "\r\n" {
                    lines.append(Line(content: content, terminator: String(character)))
                    content = ""
                } else {
                    content.append(character)
                }
            }
            if !content.isEmpty { lines.append(Line(content: content, terminator: "")) }
            return lines
        }

        private mutating func scan() {
            entries = []
            headers = []
            var table: [String]? = []
            var pending: (entry: Entry, scanner: ValueScanner)? = nil
            for (index, line) in lines.enumerated() {
                let content = line.content
                if var (entry, scanner) = pending {
                    // Inside of a value that started in a previous line
                    pending = nil
                    entry.lastLine = index
                    if scanner.feed(content, from: content.startIndex) == nil {
                        pending = (entry, scanner)
                    } else {
                        entries.append(entry)
                    }
                    continue
                }
                var cursor = Cursor(content)
                cursor.skipWhitespace()
                guard let first = cursor.peek, first != "#" else { continue }
                if first == "[" {
                    cursor.advance()
                    let isArray = cursor.peek == "["
                    if isArray { cursor.advance() }
                    guard let path = cursor.parseDottedKey(), cursor.consume("]"), !isArray || cursor.consume("]") else {
                        // Not a header that can be understood. Keys after it belong to nobody
                        table = nil
                        continue
                    }
                    headers.append(Header(line: index, path: path, isArrayOfTables: isArray))
                    table = isArray ? nil : path
                    continue
                }
                guard let key = cursor.parseDottedKey(), cursor.consume("=") else { continue }
                cursor.skipWhitespace()
                var entry = Entry(firstLine: index, lastLine: index, table: table, key: key, valueRange: nil, isInlineTable: cursor.peek == "{")
                var scanner = ValueScanner()
                let start = cursor.index
                if let end = scanner.feed(content, from: start) {
                    // Something that isn't one value ('chips' oops) isn't replaced: the document is broken, and it isn't ours to fix
                    entry.valueRange = Document.isSingleValue(content[start ..< end]) ? start ..< end : nil
                    entries.append(entry)
                } else {
                    pending = (entry, scanner)
                }
            }
            if let pending { entries.append(pending.entry) }
        }

        private static func isSingleValue(_ value: Substring) -> Bool {
            guard let first = value.first else { return false }
            switch first {
                case "[", "{": return true
                case "'":
                    return value.dropFirst().firstIndex(of: "'") == value.indices.last
                case "\"":
                    var index = value.index(after: value.startIndex)
                    while index < value.endIndex, value[index] != "\"" {
                        index = value.index(index, offsetBy: value[index] == "\\" ? 2 : 1, limitedBy: value.endIndex) ?? value.endIndex
                    }
                    return index == value.indices.last
                default:
                    return !value.contains { $0 == " " || $0 == "\t" }
            }
        }

        // MARK: Locate

        func locate(_ path: TomlKeyPath) -> Location {
            let full = path.full
            if headers.contains(where: { $0.isArrayOfTables && full.starts(with: $0.path) }) {
                return .unsupported(.arrayOfTables)
            }
            if headers.count(where: { $0.path == path.table }) > 1 || headers.contains(where: { $0.path.starts(with: full) }) {
                return .unsupported(.conflict)
            }
            var found: Entry? = nil
            for entry in entries {
                guard let table = entry.table else { continue }
                let absolute = table + entry.key
                if absolute == full {
                    if table != path.table { return .unsupported(.dottedKey) }
                    if found != nil { return .unsupported(.conflict) }
                    found = entry
                } else if full.starts(with: absolute) {
                    // The entry is the table of the key, or one of its parents
                    return .unsupported(entry.isInlineTable ? .inlineTable : .conflict)
                } else if absolute.starts(with: full) {
                    // The key is used as a table
                    return .unsupported(.conflict)
                } else if entry.key.count > 1, table.count < path.table.count, absolute.dropLast().starts(with: path.table) {
                    // The table of the key is defined with dotted keys of a parent table: `menu-bar.theme = 'chips'`.
                    // TOML doesn't allow to open such a table with a [header] afterwards
                    return .unsupported(.dottedKey)
                }
            }
            guard let found else { return .absent }
            if found.isInlineTable { return .unsupported(.conflict) }
            return found.valueRange == nil ? .unsupported(.multilineValue) : .line(found.firstLine)
        }

        // MARK: Edit

        mutating func replaceValue(inLine index: Int, with literal: String) {
            guard let range = entries.first(where: { $0.firstLine == index })?.valueRange else { return }
            let content = lines[index].content
            let old = content[range]
            var rest = content[range.upperBound...]
            // Keep the comment after the value in its column when the value changes its length
            let spaces = rest.prefix { $0 == " " }
            if !spaces.isEmpty, rest.dropFirst(spaces.count).first == "#" {
                let padding = max(1, spaces.count - (literal.count - old.count))
                rest = String(repeating: " ", count: padding) + rest.dropFirst(spaces.count)
            }
            lines[index].content = content[..<range.lowerBound] + literal + rest
            scan()
        }

        mutating func insert(_ path: TomlKeyPath, _ literal: String) {
            let key = TomlPatcher.keyLiteral(path.key)
            let newline = lines.first { !$0.terminator.isEmpty }?.terminator ?? "\n"
            // The last line break of the document may be missing. It is added only if the new line goes after
            // the last one: a line that is added in the middle leaves the end of the document as it is
            func terminateLastLine(ifInsertingAt index: Int? = nil) {
                if let index, index < lines.count { return }
                if let last = lines.indices.last, lines[last].terminator.isEmpty { lines[last].terminator = newline }
            }
            let sectionEntries = entries.filter { $0.table == path.table }
            if let last = sectionEntries.last {
                // After the last key of the table, with its indentation
                let indent = lines[last.firstLine].content.prefix { $0 == " " || $0 == "\t" }
                terminateLastLine(ifInsertingAt: last.lastLine + 1)
                lines.insert(Line(content: "\(indent)\(key) = \(literal)", terminator: newline), at: last.lastLine + 1)
            } else if let header = headers.first(where: { $0.path == path.table }) {
                // An empty table: right after its header
                let indent = lines[header.line].content.prefix { $0 == " " || $0 == "\t" }
                terminateLastLine(ifInsertingAt: header.line + 1)
                lines.insert(Line(content: "\(indent)\(key) = \(literal)", terminator: newline), at: header.line + 1)
            } else if path.table.isEmpty, let firstHeader = headers.first {
                // No top level keys: before the first table and the comments attached to it
                var index = firstHeader.line
                while index > 0, lines[index - 1].content.trimmingCharacters(in: .whitespaces).hasPrefix("#") { index -= 1 }
                lines.insert(contentsOf: [Line(content: "\(key) = \(literal)", terminator: newline), Line(content: "", terminator: newline)], at: index)
            } else if let place = placeForSubtable(path.table) {
                // A new sub-table: after the last table of its family
                let header = path.table.map(TomlPatcher.keyLiteral).joined(separator: ".")
                var block = [
                    Line(content: "", terminator: newline),
                    Line(content: "\(place.headerIndent)[\(header)]", terminator: newline),
                    Line(content: "\(place.keyIndent)\(key) = \(literal)", terminator: newline),
                ]
                // Something follows right away, without an empty line in between: the comment or the header of the next table
                if place.line < lines.count, !lines[place.line].content.trimmingCharacters(in: .whitespaces).isEmpty {
                    block.append(Line(content: "", terminator: newline))
                }
                terminateLastLine(ifInsertingAt: place.line)
                lines.insert(contentsOf: block, at: place.line)
            } else {
                // A new table, or a top level key of a document without tables: at the end
                terminateLastLine()
                if !path.table.isEmpty {
                    if let last = lines.last, !last.content.trimmingCharacters(in: .whitespaces).isEmpty {
                        lines.append(Line(content: "", terminator: newline))
                    }
                    let header = path.table.map(TomlPatcher.keyLiteral).joined(separator: ".")
                    lines.append(Line(content: "[\(header)]", terminator: newline))
                }
                lines.append(Line(content: "\(key) = \(literal)", terminator: newline))
            }
            scan()
        }

        /// Where the header of a new sub-table goes: after the last table of its family (its parent table, and
        /// the sub-tables of the parent), before the empty lines and the comment that precede the next table.
        /// nil if the table isn't a sub-table, or if nothing of its family is in the document
        private func placeForSubtable(_ table: [String]) -> (line: Int, headerIndent: String, keyIndent: String)? {
            let parent = Array(table.dropLast())
            guard !parent.isEmpty, let last = headers.last(where: { !$0.isArrayOfTables && $0.path.starts(with: parent) }) else { return nil }
            func indent(_ line: Int) -> String { String(lines[line].content.prefix { $0 == " " || $0 == "\t" }) }
            let end = headers.first { $0.line > last.line }?.line ?? lines.count
            // Never inside of the last value of the table, whatever its lines look like
            let lowerBound = (entries.last { $0.firstLine > last.line && $0.firstLine < end }?.lastLine ?? last.line) + 1
            var line = end
            // The comment right above the next header is the comment of that table
            while line > lowerBound, end < lines.count, lines[line - 1].content.trimmingCharacters(in: .whitespaces).hasPrefix("#") { line -= 1 }
            while line > lowerBound, lines[line - 1].content.trimmingCharacters(in: .whitespaces).isEmpty { line -= 1 }

            // Like a sibling, if there is one. Otherwise, one level deeper than the keys of the parent
            if let sibling = headers.last(where: { !$0.isArrayOfTables && $0.path.count == table.count && $0.path.starts(with: parent) }) {
                let headerIndent = indent(sibling.line)
                let keyIndent = entries.first { $0.table == sibling.path }.map { indent($0.firstLine) }
                return (line, headerIndent, keyIndent ?? headerIndent)
            }
            guard let parentHeader = headers.first(where: { $0.path == parent }) else { return (line, indent(last.line), indent(last.line)) }
            let parentIndent = indent(parentHeader.line)
            let headerIndent = entries.last { $0.table == parent }.map { indent($0.firstLine) } ?? parentIndent
            let step = headerIndent.hasPrefix(parentIndent) ? String(headerIndent.dropFirst(parentIndent.count)) : ""
            return (line, headerIndent, headerIndent + step)
        }
    }

    /// Bare if possible, quoted otherwise
    static func keyLiteral(_ key: String) -> String {
        let isBare = !key.isEmpty && key.unicodeScalars.allSatisfy {
            ("a" ... "z").contains($0) || ("A" ... "Z").contains($0) || ("0" ... "9").contains($0) || $0 == "-" || $0 == "_"
        }
        return isBare ? key : TomlValue.string(key).literal
    }
}

// MARK: - Lexing

/// Reads the beginning of a line: `key.path =`, `[table.path]`
private struct Cursor {
    let string: String
    var index: String.Index

    init(_ string: String) {
        self.string = string
        index = string.startIndex
    }

    var peek: Character? { index < string.endIndex ? string[index] : nil }
    mutating func advance() { index = string.index(after: index) }

    mutating func skipWhitespace() {
        while let character = peek, character == " " || character == "\t" { advance() }
    }

    /// Skips the whitespace, then consumes the character if it is the next one
    mutating func consume(_ character: Character) -> Bool {
        skipWhitespace()
        guard peek == character else { return false }
        advance()
        return true
    }

    /// `a`, `a.b`, `a . "b c" . 'd'`
    mutating func parseDottedKey() -> [String]? {
        var result: [String] = []
        while true {
            skipWhitespace()
            guard let part = parseSimpleKey() else { return nil }
            result.append(part)
            skipWhitespace()
            guard peek == "." else { return result }
            advance()
        }
    }

    private mutating func parseSimpleKey() -> String? {
        guard let first = peek else { return nil }
        var key = ""
        switch first {
            case "'":
                advance()
                while let character = peek, character != "'" {
                    key.append(character)
                    advance()
                }
                guard peek == "'" else { return nil }
                advance()
                return key
            case "\"":
                advance()
                while let character = peek, character != "\"" {
                    // Escapes are rare in keys. A key with one never matches the keys the patcher looks for, which is safe
                    key.append(character)
                    advance()
                    if character == "\\", let escaped = peek {
                        key.append(escaped)
                        advance()
                    }
                }
                guard peek == "\"" else { return nil }
                advance()
                return key
            default:
                while let character = peek, character.isASCII, character.isLetter || character.isNumber || character == "-" || character == "_" {
                    key.append(character)
                    advance()
                }
                return key.isEmpty ? nil : key
        }
    }
}

/// Finds where a value ends. A value can span several lines: multi-line strings and arrays
private struct ValueScanner {
    private enum Mode { case code, basic, literal, multilineBasic, multilineLiteral }
    private var mode: Mode = .code
    /// Open [ and {
    private var depth = 0

    /// - Returns: the index after the last character of the value, or nil if the value continues in the next line
    mutating func feed(_ line: String, from start: String.Index) -> String.Index? {
        var index = start
        /// The end of the value, if the line ends without anything else
        var end = start
        func starts(with prefix: String) -> Bool { line[index...].hasPrefix(prefix) }
        while index < line.endIndex {
            let character = line[index]
            var step = 1
            switch mode {
                case .code:
                    if character == "#" {
                        // A comment up to the end of the line
                        return depth == 0 ? end : nil
                    } else if starts(with: "\"\"\"") {
                        mode = .multilineBasic
                        step = 3
                    } else if starts(with: "'''") {
                        mode = .multilineLiteral
                        step = 3
                    } else if character == "\"" {
                        mode = .basic
                    } else if character == "'" {
                        mode = .literal
                    } else if character == "[" || character == "{" {
                        depth += 1
                    } else if character == "]" || character == "}" {
                        depth = max(0, depth - 1)
                    }
                case .basic:
                    if character == "\\" { step = 2 } else if character == "\"" { mode = .code }
                case .literal:
                    if character == "'" { mode = .code }
                case .multilineBasic:
                    if character == "\\" {
                        step = 2
                    } else if starts(with: "\"\"\"") {
                        // Up to two quotes may precede the closing ones
                        step = 3
                        while line[index...].dropFirst(step).first == "\"", step < 5 { step += 1 }
                        mode = .code
                    }
                case .multilineLiteral:
                    if starts(with: "'''") {
                        step = 3
                        while line[index...].dropFirst(step).first == "'", step < 5 { step += 1 }
                        mode = .code
                    }
            }
            index = line.index(index, offsetBy: step, limitedBy: line.endIndex) ?? line.endIndex
            if mode != .code || (character != " " && character != "\t") { end = index }
        }
        switch mode {
            // A string that isn't closed. The document isn't valid, and the validation of the result will tell
            case .basic, .literal:
                mode = .code
                return depth == 0 ? end : nil
            case .code: return depth == 0 ? end : nil
            case .multilineBasic, .multilineLiteral: return nil
        }
    }
}

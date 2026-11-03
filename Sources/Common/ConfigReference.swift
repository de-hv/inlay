import Foundation

/// The reference of the config (docs/config-reference.lua, a copy of which is in the app bundle), split into the
/// parts that document a key or a table. See: 'inlay config --explain'
///
/// The file is a Lua config that returns one table, written one key per line: `name = {` opens a table, a line
/// with `}` closes it, a line with `{` alone is an item of an array (a rule of onWindowDetected), and
/// `name = value,` is a key. The comment lines right above a key or a table document it.
/// A key that can't be written with a value (a deprecated one) is documented by a block of comment lines
/// whose last line is the key, commented out: `-- accordionPadding = 30`
public struct ConfigReference: Sendable {
    public let text: String
    private let lines: [String]
    private let tables: [Part]
    private let keys: [Part]

    private struct Part {
        /// The dotted path: 'borders', 'borders.width', 'onWindowDetected.match.appId'
        var path: String
        /// The lines of the part, with its comment
        var range: Range<Int>
        /// The lines that open the tables that the part is in, outermost first
        var headerLines: [Int] = []
    }

    public init(_ text: String) {
        self.text = text
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var tables: [Part] = []
        var keys: [Part] = []
        var commentStart: Int? = nil // The first line of the block of comment lines that ends at the previous line
        // The open tables: the path, the line that opens it, the index of its part in 'tables'. The table that the
        // file returns has no path and no part
        var open: [(path: String?, line: Int, part: Int?)] = []

        func qualified(_ key: String) -> String {
            guard let table = open.last?.path else { return key }
            return table + "." + key
        }
        var headerLines: [Int] { open.filter { $0.path != nil }.map(\.line) }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if let start = commentStart, let key = commentedOutKey(lines[index - 1]) {
                    keys.append(Part(path: qualified(key), range: start ..< index, headerLines: headerLines))
                }
                commentStart = nil
            } else if trimmed.hasPrefix("--") {
                commentStart = commentStart ?? index
            } else if trimmed == "return {" {
                open.append((nil, index, nil))
                commentStart = nil
            } else if trimmed == "{" { // An item of the array: a part of the array, like a table of it
                let path = open.last?.path ?? ""
                tables.append(Part(path: path, range: (commentStart ?? index) ..< lines.count, headerLines: headerLines))
                open.append((path, index, tables.count - 1))
                commentStart = nil
            } else if trimmed.hasSuffix("{"), let key = assignedKey(trimmed) {
                let path = qualified(key)
                tables.append(Part(path: path, range: (commentStart ?? index) ..< lines.count, headerLines: headerLines))
                open.append((path, index, tables.count - 1))
                commentStart = nil
            } else if trimmed.hasPrefix("}") {
                // A key commented out at the end of the table
                if let start = commentStart, let key = commentedOutKey(lines[index - 1]) {
                    keys.append(Part(path: qualified(key), range: start ..< index, headerLines: headerLines))
                }
                if let part = open.popLast()?.part { tables[part].range = tables[part].range.lowerBound ..< index + 1 }
                commentStart = nil
            } else if let key = assignedKey(trimmed) {
                keys.append(Part(path: qualified(key), range: (commentStart ?? index) ..< index + 1, headerLines: headerLines))
                commentStart = nil
            }
        }
        self.lines = lines
        self.tables = tables
        self.keys = keys
    }

    /// The paths of all the keys and tables that the reference documents, in the order of the file, without duplicates
    public var documentedKeys: [String] {
        var seen: Set<String> = []
        return (tables + keys).sorted { $0.range.lowerBound < $1.range.lowerBound }.map(\.path).filter { seen.insert($0).inserted }
    }

    /// The part of the reference about a key or a table, and about everything under it. nil key: the whole reference
    public func explain(_ key: String?) -> Result<String, String> {
        guard let key else { return .success(text.trimmingCharacters(in: .newlines)) }
        let path = key.split(separator: ".").joined(separator: ".") // '.borders.' is 'borders'
        func covers(_ part: Part) -> Bool { part.path == path || part.path.hasPrefix(path + ".") }

        // A table that is in another one that matches is already in it
        let matchedTables = tables.filter(covers)
        let outermost = matchedTables.filter { table in
            !matchedTables.contains { $0.range != table.range && $0.range.contains(table.range.lowerBound) && $0.range.contains(table.range.upperBound - 1) }
        }
        if !outermost.isEmpty {
            return .success(outermost.map { render($0.headerLines, $0.range) }.joined(separator: "\n\n"))
        }
        let matchedKeys = keys.filter(covers)
        if !matchedKeys.isEmpty {
            var result: [String] = []
            var lastHeaders: [Int]? = nil
            for part in matchedKeys {
                // The tables that the key is in, once, so that it is clear where the key goes
                result.append(render(part.headerLines == lastHeaders ? [] : part.headerLines, part.range))
                lastHeaders = part.headerLines
            }
            return .success(dedented(result.joined(separator: "\n\n")))
        }
        let similar = documentedKeys.filter { $0.contains(path) }
        let hint = similar.isEmpty
            ? "'config --explain' without a key prints the whole reference"
            : "Did you mean: \(similar.joined(separator: ", "))"
        return .failure("The config reference has no key or table '\(path)'. \(hint)")
    }

    /// The lines of the part, after the lines that open the tables it is in, and a blank line
    private func render(_ headerLines: [Int], _ range: Range<Int>) -> String {
        var slice = lines[range]
        while slice.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { slice.removeLast() }
        let headers = headerLines.map { lines[$0] }
        return dedented((headers.isEmpty ? [] : headers + [""]) + slice)
    }

    /// The lines without the indentation that they all have
    private func dedented(_ text: String) -> String {
        dedented(text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
    }

    private func dedented(_ lines: [String]) -> String {
        let indentation = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { $0.prefix { $0 == " " }.count }.min() ?? 0
        return lines.map { String($0.dropFirst(min(indentation, $0.prefix { $0 == " " }.count))) }.joined(separator: "\n")
    }

    /// The reference that ships with Inlay
    public static func load() -> Result<ConfigReference, String> {
        guard let url = shippedFile(inResources: fileName, inRepo: "docs/\(fileName)"), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure("Can't find \(fileName). Is Inlay installed correctly? It is expected in Inlay.app/Contents/Resources")
        }
        return .success(ConfigReference(text))
    }

    private static let fileName = "config-reference.lua"
}

/// A file that ships with Inlay, for the app and for the CLI.
/// - Parameter inResources: its path in Inlay.app/Contents/Resources
/// - Parameter inRepo: its path in the repo. A binary that isn't in an app bundle (swift build) uses the files
///   of the repo it was built from
/// - Parameter executable: the path of the running binary. Contents/MacOS/Inlay or Contents/Resources/bin/inlay,
///   also when it is run through a symlink
public func shippedFile(
    inResources: String,
    inRepo: String,
    executable: String = CommandLine.arguments[0],
    sourceFile: String = #filePath,
) -> URL? {
    var candidates: [URL] = []
    if let app = appBundle(ofExecutable: executable) {
        candidates.append(app.appending(path: "Contents/Resources").appending(path: inResources))
    }
    var repo = URL(filePath: sourceFile)
    while repo.path != "/" {
        repo.deleteLastPathComponent()
        if FileManager.default.fileExists(atPath: repo.appending(path: "Package.swift").path) {
            candidates.append(repo.appending(path: inRepo))
        }
    }
    return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
}

/// The Inlay.app that contains the binary. nil if it isn't in an app bundle
public func appBundle(ofExecutable executable: String = CommandLine.arguments[0]) -> URL? {
    var url = URL(filePath: executable).resolvingSymlinksInPath()
    while url.path != "/" {
        url.deleteLastPathComponent()
        if url.pathExtension == "app" { return url }
    }
    return nil
}

/// 'inner' for 'inner = {', 'horizontal' for 'horizontal = 0,', 'alt-h' for "['alt-h'] = 'focus left',"
private func assignedKey(_ trimmedLine: String) -> String? {
    guard let equals = trimmedLine.firstIndex(of: "="), let first = trimmedLine.first else { return nil }
    let key = trimmedLine[trimmedLine.startIndex ..< equals].trimmingCharacters(in: .whitespaces)
    let isKeyCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber || "-_.'\"[]".contains($0) }
    return !key.isEmpty && isKeyCharacter(first) && key.allSatisfy(isKeyCharacter) ? normalizedKey(key) : nil
}

/// 'accordionPadding' for '-- accordionPadding = 30'
private func commentedOutKey(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("-- ") else { return nil }
    let content = String(trimmed.dropFirst(3))
    guard content.first?.isLowercase == true, let key = assignedKey(content) else { return nil }
    return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." } ? key : nil
}

private func normalizedKey(_ key: String) -> String {
    key.filter { !"'\"[] ".contains($0) }
}

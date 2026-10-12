import Foundation

/// The reference of the config (docs/config-reference.toml, a copy of which is in the app bundle), split into the
/// parts that document a key or a table. See: 'inlay config --explain'
///
/// The file is a TOML file where the comment lines right above a key or a table header document it.
/// A key that can't be written with a value (a deprecated one) is documented by a block of comment lines
/// whose last line is the key, commented out: `# accordion-padding = 30`
public struct ConfigReference: Sendable {
    public let text: String
    private let lines: [String]
    private let tables: [Part]
    private let keys: [Part]

    private struct Part {
        /// The dotted path: 'borders', 'borders.width', 'on-window-detected.if.app-id'
        var path: String
        /// The lines of the part, with its comment
        var range: Range<Int>
        /// The line of the header of the table that the key belongs to. nil for a table, and for a key of the root table
        var headerLine: Int? = nil
    }

    public init(_ text: String) {
        self.text = text
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var tables: [Part] = []
        var keys: [Part] = []
        var commentStart: Int? = nil // The first line of the block of comment lines that ends at the previous line
        var table: (path: String, headerLine: Int)? = nil
        var openKey: Int? = nil // The index, in 'keys', of the key whose value may continue on the current line

        func closeTable(at end: Int) {
            if let last = tables.indices.last { tables[last].range = tables[last].range.lowerBound ..< end }
        }
        func closeKey(at end: Int) {
            if let openKey { keys[openKey].range = keys[openKey].range.lowerBound ..< end }
            openKey = nil
        }
        func qualified(_ key: String) -> String { table.map { $0.path + "." + key } ?? key }

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                closeKey(at: index)
                if let start = commentStart, let key = commentedOutKey(lines[index - 1]) {
                    keys.append(Part(path: qualified(key), range: start ..< index, headerLine: table?.headerLine))
                }
                commentStart = nil
            } else if trimmed.hasPrefix("#") {
                closeKey(at: index)
                commentStart = commentStart ?? index
            } else if let path = tableHeader(trimmed) {
                closeKey(at: index)
                let start = commentStart ?? index
                closeTable(at: start)
                tables.append(Part(path: path, range: start ..< lines.count))
                table = (path, index)
                commentStart = nil
            } else if let key = assignedKey(trimmed) {
                closeKey(at: index)
                keys.append(Part(path: qualified(key), range: (commentStart ?? index) ..< index + 1, headerLine: table?.headerLine))
                openKey = keys.count - 1
                commentStart = nil
            } else if let openKey { // A value that takes several lines
                keys[openKey].range = keys[openKey].range.lowerBound ..< index + 1
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

        let matchedTables = tables.filter(covers)
        if !matchedTables.isEmpty {
            return .success(matchedTables.map { render($0.range) }.joined(separator: "\n\n"))
        }
        let matchedKeys = keys.filter(covers)
        if !matchedKeys.isEmpty {
            var result: [String] = []
            var lastHeader: Int? = nil
            for part in matchedKeys {
                // The header of the table, once, so that it is clear where the key goes
                if let header = part.headerLine, header != lastHeader { result.append(lines[header]) }
                lastHeader = part.headerLine
                result.append(render(part.range))
            }
            return .success(result.joined(separator: "\n\n"))
        }
        let similar = documentedKeys.filter { $0.contains(path) }
        let hint = similar.isEmpty
            ? "'config --explain' without a key prints the whole reference"
            : "Did you mean: \(similar.joined(separator: ", "))"
        return .failure("The config reference has no key or table '\(path)'. \(hint)")
    }

    private func render(_ range: Range<Int>) -> String {
        var slice = lines[range]
        while slice.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { slice.removeLast() }
        return slice.joined(separator: "\n")
    }

    /// The reference that ships with Inlay
    public static func load() -> Result<ConfigReference, String> {
        guard let url = shippedFile(inResources: fileName, inRepo: "docs/\(fileName)"), let text = try? String(contentsOf: url, encoding: .utf8) else {
            return .failure("Can't find \(fileName). Is Inlay installed correctly? It is expected in Inlay.app/Contents/Resources")
        }
        return .success(ConfigReference(text))
    }

    private static let fileName = "config-reference.toml"
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

/// 'borders' for '[borders]', 'on-window-detected' for '[[on-window-detected]]'
private func tableHeader(_ trimmedLine: String) -> String? {
    guard trimmedLine.hasPrefix("["), let end = trimmedLine.firstIndex(of: "]") else { return nil }
    let name = trimmedLine[trimmedLine.startIndex ..< end].drop { $0 == "[" }
    return name.isEmpty ? nil : normalizedKey(String(name))
}

/// 'inner.horizontal' for 'inner.horizontal = 0'
private func assignedKey(_ trimmedLine: String) -> String? {
    guard let equals = trimmedLine.firstIndex(of: "="), let first = trimmedLine.first else { return nil }
    let key = trimmedLine[trimmedLine.startIndex ..< equals].trimmingCharacters(in: .whitespaces)
    let isKeyCharacter: (Character) -> Bool = { $0.isLetter || $0.isNumber || "-_.'\"".contains($0) }
    return !key.isEmpty && isKeyCharacter(first) && key.allSatisfy(isKeyCharacter) ? normalizedKey(key) : nil
}

/// 'accordion-padding' for '# accordion-padding = 30'
private func commentedOutKey(_ line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("# ") else { return nil }
    let content = String(trimmed.dropFirst(2))
    guard content.first?.isLowercase == true, let key = assignedKey(content) else { return nil }
    return key.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" || $0 == "." } ? key : nil
}

private func normalizedKey(_ key: String) -> String {
    key.filter { $0 != "'" && $0 != "\"" && $0 != " " }
}

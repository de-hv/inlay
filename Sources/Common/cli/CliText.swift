import Foundation

/// What the CLI prints for people: the help, the status of 'inlay' alone, the errors, and the Lua of the config.
/// Pure functions of their input and of a CliStyle, so that they are tested without a terminal
public enum CliText {
    // MARK: - Help

    /// The commands, by what they are for. Every command of the CLI is in one group. See: CliTextTest
    public static let groups: [(name: String, commands: [String])] = [
        ("Windows", ["focus", "move", "swap", "resize", "fullscreen", "close", "focus-back-and-forth", "close-all-windows-but-current", "macos-native-fullscreen", "macos-native-minimize"]),
        ("Layout", ["layout", "split", "join-with", "balance-sizes", "arrange-workspace", "flatten-workspace-tree"]),
        ("Workspaces", ["workspace", "move-node-to-workspace", "summon-workspace", "workspace-back-and-forth"]),
        ("Monitors", ["focus-monitor", "move-node-to-monitor", "move-workspace-to-monitor", "move-mouse"]),
        ("Inspect", ["list-windows", "list-workspaces", "list-monitors", "list-apps", "list-modes", "list-exec-env-vars"]),
        ("Config", ["config", "reload-config", "mode", "trigger-binding", "run-callback"]),
        ("Scripting", ["eval", "subscribe", "echo", "test", "test-not", "true", "false"]),
        ("App", ["enable", "volume", "debug-stats", "debug-windows", "uninstall"]),
    ]

    static let examples: [(command: String, what: String)] = [
        ("inlay workspace 3", "go to workspace 3"),
        ("inlay move-node-to-workspace 2", "send the focused window there"),
        ("inlay list-windows --workspace focused", "the windows of this workspace"),
        ("inlay config --show bind", "the key bindings, and their files"),
    ]

    /// 'inlay --help': the examples first, then the commands by group. `descriptions`: one command per line with
    /// what it does ('inlay --help --all')
    public static func help(descriptions: [String: String]? = nil, width: Int, style: CliStyle) -> String {
        let width = width - 2
        var lines = [
            "Tiling window manager for macOS. The commands talk to the running Inlay.app",
            "",
            "\(style.strong("Usage"))  inlay \(style.paint("<command> [args]", .muted))",
            "",
            style.strong("Examples"),
        ]
        let commandWidth = (examples.map(\.command.count).max() ?? 0) + 2
        lines += examples.map { "  \($0.command.padded(commandWidth))\(style.paint($0.what, .muted))" }
        lines.append("")
        let labelWidth = (groups.map(\.name.count).max() ?? 0) + 2
        for group in groups {
            if let descriptions {
                lines.append(style.strong(group.name))
                let nameWidth = (group.commands.map(\.count).max() ?? 0) + 2
                for command in group.commands {
                    let description = (descriptions[command] ?? "").truncatedTail(max(width - 2 - nameWidth, 20))
                    lines.append("  \(command.padded(nameWidth))\(style.paint(description, .muted))")
                }
                lines.append("")
            } else {
                lines += wrapped(group.commands, label: style.strong(group.name.padded(labelWidth)), labelWidth: labelWidth, width: width)
            }
        }
        if descriptions == nil { lines.append("") }
        lines.append("\(style.paint("inlay <command> --help", .muted))  what a command does, and its flags")
        lines.append("\(style.paint("inlay --help --all", .muted))      every command, with what it does")
        lines.append("\(style.paint("Docs", .muted)) \(style.paint("https://github.com/de-hv/inlay", .path))")
        return indented(lines)
    }

    /// Two cells of margin, like the tables. Empty lines stay empty
    static func indented(_ lines: [String]) -> String {
        lines.map { $0.isEmpty ? "" : "  " + $0 }.joined(separator: "\n")
    }

    /// The names after the label, wrapped to the width with the next lines under the first name
    static func wrapped(_ names: [String], label: String, labelWidth: Int, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for name in names {
            let candidate = current.isEmpty ? name : current + "  " + name
            if !current.isEmpty && labelWidth + candidate.count > width - 1 {
                lines.append(current)
                current = name
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.enumerated().map { index, line in (index == 0 ? label : String(repeating: " ", count: labelWidth)) + line }
    }

    // MARK: - inlay alone

    /// What 'inlay' alone shows: the server, where you are, the config
    public struct Status: Sendable {
        public var version: String
        /// nil: Inlay.app isn't running, or doesn't answer
        public var serverVersion: String?
        public var mode: String?
        public var workspace: String?
        public var workspaceName: String?
        public var windows: Int?
        public var monitor: String?
        public var configPath: String?
        /// Where the folder of the config links to, when it is a link
        public var configTarget: String?
        /// The errors of the config: 0 is ok. nil: unknown
        public var configErrors: Int?
        public var theme: String?
        public var workspaces: Int?
        public var bindings: Int?

        public init(version: String) { self.version = version }
    }

    static let quickGroups: [(name: String, commands: [String])] = [
        ("windows", ["focus", "move", "swap", "resize", "fullscreen", "layout"]),
        ("workspaces", ["workspace", "move-node-to-workspace", "summon-workspace"]),
        ("inspect", ["list-windows", "list-workspaces", "list-monitors"]),
        ("config", ["config", "reload-config"]),
    ]

    public static func status(_ status: Status, width: Int, style: CliStyle) -> String {
        let width = width - 2
        let dot = style.paint(" · ", .muted)
        var lines: [String] = []
        let title = "\(style.strong("inlay")) \(style.paint(status.version, .muted))"
        let state: String
        if status.serverVersion == nil {
            state = "\(style.paint("○", .warning)) not running"
        } else {
            state = "\(style.paint("●", .success)) running" + (status.mode.map { "\(dot)mode \(style.paint($0, .accent))" } ?? "")
        }
        let gap = max(3, min(width, 72) - 2 - title.cellWidth - state.cellWidth)
        lines.append(title + String(repeating: " ", count: gap) + state)
        lines.append("")

        let labelWidth = 12
        func row(_ label: String, _ value: String) -> String { style.paint(label.padded(labelWidth), .muted) + value }
        if status.serverVersion != nil {
            if let workspace = status.workspace {
                var parts = [style.paint(workspace, .accent) + (status.workspaceName.map { " \($0)" } ?? "")]
                if let windows = status.windows { parts.append(windows == 1 ? "1 window" : "\(windows) windows") }
                if let monitor = status.monitor { parts.append(monitor) }
                lines.append(row("workspace", parts.joined(separator: dot)))
            }
        }
        if let path = status.configPath {
            var value = style.paint(path, .path)
            if let target = status.configTarget { value += style.paint(" → ", .muted) + style.paint(target, .path) }
            switch status.configErrors {
                case 0?: value += dot + style.paint("ok", .success)
                case let count?: value += dot + style.paint(count == 1 ? "1 error" : "\(count) errors", .error)
                case nil: break
            }
            lines.append(row("config", value))
        }
        var details: [String] = []
        if let theme = status.theme { details.append(theme) }
        if let workspaces = status.workspaces { details.append("\(workspaces) workspaces") }
        if let bindings = status.bindings { details.append("\(bindings) bindings") }
        if !details.isEmpty { lines.append(row("theme", details.joined(separator: dot))) }
        if lines.count > 2 { lines.append("") }

        for group in quickGroups {
            lines += wrapped(group.commands, label: style.paint(group.name.padded(labelWidth), .muted), labelWidth: labelWidth, width: width)
        }
        lines.append("")
        if status.serverVersion == nil {
            lines.append("\(style.paint("hint:", .muted)) open Inlay: \(style.paint("open -a Inlay", .accent))")
        } else if let server = status.serverVersion, server != status.version {
            lines.append("\(style.paint("warning:", .warning)) Inlay.app is \(server), this inlay is \(status.version)")
            lines.append("\(style.paint("hint:", .muted)) restart Inlay: \(style.paint("open -a Inlay", .accent))")
        } else {
            lines.append(style.paint("inlay --help for every command · inlay <command> --help", .muted))
        }
        return indented(lines)
    }

    // MARK: - Errors

    /// The command closest to a mistyped one, if it is close enough: 'worksapce' → 'workspace'
    public static func closest(_ name: String, among candidates: [String]) -> String? {
        // The start of a single command: 'reload' → 'reload-config'
        let starting = candidates.filter { $0.hasPrefix(name) }
        if name.count >= 3, starting.count == 1 { return starting[0] }
        let scored = candidates.map { ($0, distance(name, $0)) }.min { $0.1 < $1.1 }
        guard let (best, score) = scored else { return nil }
        let isPrefix = best.hasPrefix(name) && name.count >= 3
        return score <= max(2, name.count / 3) || isPrefix ? best : nil
    }

    /// The edits from one word to the other (Damerau–Levenshtein: a swap of two letters is one)
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0 ... a.count { d[i][0] = i }
        for j in 0 ... b.count { d[0][j] = j }
        for i in 1 ... a.count {
            for j in 1 ... b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = Swift.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = Swift.min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    /// 'error: unknown command', and the one it was probably meant to be, with its arguments
    public static func unknownCommand(_ name: String, arguments: [String], commands: [String], style: CliStyle) -> String {
        var lines = ["\(style.paint("error:", .error)) unknown command '\(name)'"]
        if let guess = closest(name, among: commands) {
            let suggestion = (["inlay", guess] + arguments).joined(separator: " ")
            lines.append("\(style.paint("hint:", .muted))  did you mean \(style.paint(suggestion, .accent))")
        } else {
            lines.append("\(style.paint("hint:", .muted))  inlay --help lists the commands")
        }
        return lines.joined(separator: "\n")
    }

    /// The diagnostics of the server, for a terminal: '[ERROR] x' and 'ERROR: x' are 'error: x', a line of a file of the
    /// config ('binds.lua:12: …') is followed by that line of the file. Without a style the text stays as it is: scripts
    /// read it
    public static func diagnostics(_ text: String, style: CliStyle, readLine: (String, Int) -> String? = { _, _ in nil }) -> String {
        guard style.isEnabled else { return text }
        var out: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            var body = line
            var label: String? = nil
            for (prefix, word) in [("[ERROR] ", "error:"), ("ERROR: ", "error:"), ("error: ", "error:"), ("[WARNING] ", "warning:"), ("Warning: ", "warning:"), ("warning: ", "warning:")] where body.hasPrefix(prefix) {
                body = String(body.dropFirst(prefix.count))
                label = word
                break
            }
            if let label {
                out.append(style.paint(label, label == "error:" ? .error : .warning) + " " + body)
                // The line of Lua that fails
                if let match = body.firstMatch(of: /^([\w.\/-]+\.lua):(\d+):/), let number = Int(match.2), let source = readLine(String(match.1), number) {
                    out.append("   " + style.paint("\(number) │", .muted) + " " + lua(source.trimmingCharacters(in: .whitespaces), style: style))
                }
            } else if body.hasPrefix("hint:") {
                out.append(style.paint("hint:", .muted) + body.dropFirst(5))
            } else {
                out.append(body)
            }
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Lua

    static let keywords: Set<String> = ["local", "function", "end", "for", "in", "do", "return", "if", "then", "else", "elseif", "while", "repeat", "until", "and", "or", "not", "true", "false", "nil"]

    /// The Lua of the config, highlighted like an editor does. The origin at the end of a line ('-- yours (binds.lua:4)')
    /// in the accent: it is what you came to find
    public static func lua(_ text: String, style: CliStyle) -> String {
        guard style.isEnabled else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { luaLine(String($0), style: style) }.joined(separator: "\n")
    }

    static func luaLine(_ line: String, style: CliStyle) -> String {
        var out = ""
        var index = line.startIndex
        func peek(_ offset: Int) -> Character? {
            line.index(index, offsetBy: offset, limitedBy: line.endIndex).flatMap { $0 < line.endIndex ? line[$0] : nil }
        }
        while index < line.endIndex {
            let character = line[index]
            if character == "-", peek(1) == "-" {
                out += comment(String(line[index...]), style: style)
                break
            }
            if character == "'" || character == "\"" {
                var end = line.index(after: index)
                while end < line.endIndex, line[end] != character {
                    if line[end] == "\\" { end = line.index(after: end) }
                    if end < line.endIndex { end = line.index(after: end) }
                }
                if end < line.endIndex { end = line.index(after: end) }
                out += style.paint(String(line[index ..< end]), .string)
                index = end
                continue
            }
            if character.isNumber, index == line.startIndex || !(line[line.index(before: index)].isLetter || line[line.index(before: index)] == "_") {
                var end = index
                while end < line.endIndex, line[end].isNumber || line[end] == "." { end = line.index(after: end) }
                out += style.paint(String(line[index ..< end]), .number)
                index = end
                continue
            }
            if character.isLetter || character == "_" {
                var end = index
                while end < line.endIndex, line[end].isLetter || line[end].isNumber || line[end] == "_" || line[end] == "." { end = line.index(after: end) }
                let word = String(line[index ..< end])
                if word.hasPrefix("inlay.") || word == "require" {
                    out += style.paint(word, .accent)
                } else if keywords.contains(word) {
                    out += style.paint(word, .keyword)
                } else {
                    out += word
                }
                index = end
                continue
            }
            out.append(character)
            index = line.index(after: index)
        }
        return out
    }

    static func comment(_ text: String, style: CliStyle) -> String {
        // '-- yours (binds.lua:4) · true|false': the origin in the accent, the rest dim
        if let range = text.range(of: #"yours( \([^)]*\))?"#, options: .regularExpression) {
            return style.paint(String(text[..<range.lowerBound]), .muted) + style.paint(String(text[range]), .accent) + style.paint(String(text[range.upperBound...]), .muted)
        }
        return style.paint(text, .muted)
    }

    /// 'inlay config --explain': the Lua of the reference highlighted, the prose of the functions plain
    public static func explain(_ text: String, style: CliStyle) -> String {
        guard style.isEnabled else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // A sentence starts with a capital letter, a line of Lua doesn't
            let isProse = trimmed.first?.isUppercase == true || line.hasPrefix("  ") && !trimmed.hasPrefix("inlay.") && !trimmed.hasPrefix("--") && !trimmed.contains(" = ")
            let isCode = !isProse && (trimmed.hasPrefix("inlay.") || trimmed.hasPrefix("--") || trimmed.hasPrefix("}") || trimmed.hasSuffix("{") || trimmed.contains(" = "))
            return isCode ? luaLine(String(line), style: style) : String(line)
        }.joined(separator: "\n")
    }

    /// 'inlay config --files': the labels dim, yours in the accent, the paths in their color
    public static func files(_ text: String, style: CliStyle) -> String {
        guard style.isEnabled else { return text }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let line = String(line)
            for label in ["Inlay", "theme", "yours"] where line.hasPrefix(label + "   ") {
                let rest = String(line.dropFirst(label.count))
                let parts = rest.components(separatedBy: "  → ")
                let path = parts[0].trimmingCharacters(in: .whitespaces)
                let link = parts.count > 1 ? style.paint("  → " + parts[1], .muted) : ""
                return style.paint(label, label == "yours" ? .accent : .muted) + "   " + style.paint(path, .path) + link
            }
            if let branch = line.range(of: #"^\s+[├└]─ "#, options: .regularExpression) {
                let rest = String(line[branch.upperBound...])
                let name = rest.prefix { $0 != " " }
                return style.paint(String(line[branch]), .muted) + name + style.paint(String(rest.dropFirst(name.count)), .muted)
            }
            return line.hasPrefix("'inlay config") ? style.paint(line, .muted) : line
        }.joined(separator: "\n")
    }
}

import Darwin
import Foundation

/// The meaning of a piece of text in the output of the CLI. The colors are a choice of the palette, never of the
/// code that prints: see CliStyle
public enum CliTone: Sendable, CaseIterable {
    /// What is current, what is yours: the focused workspace, a file of your config
    case accent
    /// Headings of the groups, the keywords of Lua
    case keyword
    /// Labels, headers, metadata: everything secondary
    case muted
    case success
    case warning
    case error
    /// Paths and links
    case path
    /// The strings of Lua
    case string
    /// The numbers of Lua
    case number
    /// Bold, in the color of the text
    case strong
}

/// How the CLI paints a stream: One Dark in truecolor, the 16 colors of the terminal theme otherwise, nothing when
/// the stream isn't a terminal (or NO_COLOR, or TERM=dumb). INLAY_COLOR=always|never wins over all of it
public struct CliStyle: Sendable, Equatable {
    public enum Depth: Sendable, Equatable { case none, ansi, truecolor }

    public let depth: Depth

    public init(depth: Depth) { self.depth = depth }

    public static let plain = CliStyle(depth: .none)

    public var isEnabled: Bool { depth != .none }

    /// The style of a stream: STDOUT_FILENO or STDERR_FILENO
    public static func of(fd: Int32, environment: [String: String] = ProcessInfo.processInfo.environment) -> CliStyle {
        resolve(isTerminal: isatty(fd) == 1, environment: environment)
    }

    public static func resolve(isTerminal: Bool, environment: [String: String]) -> CliStyle {
        let truecolor = ["truecolor", "24bit"].contains(environment["COLORTERM"]?.lowercased() ?? "")
        let depth: Depth = truecolor ? .truecolor : .ansi
        switch environment["INLAY_COLOR"]?.lowercased() {
            case "always"?: return CliStyle(depth: depth)
            case "never"?: return .plain
            default: break
        }
        if let noColor = environment["NO_COLOR"], !noColor.isEmpty { return .plain }
        if environment["TERM"] == "dumb" { return .plain }
        let forced = [environment["FORCE_COLOR"], environment["CLICOLOR_FORCE"]].contains { $0 != nil && $0 != "0" && $0 != "" }
        return isTerminal || forced ? CliStyle(depth: depth) : .plain
    }

    /// The text in the color of its tone. Plain: the text as it is
    public func paint(_ text: String, _ tone: CliTone) -> String {
        guard isEnabled, !text.isEmpty else { return text }
        return sgr(tone) + text + "\u{1B}[0m"
    }

    /// Bold, plus the color of the tone: the row of what is current
    public func strong(_ text: String, _ tone: CliTone? = nil) -> String {
        guard isEnabled, !text.isEmpty else { return text }
        return "\u{1B}[1m" + (tone.map(sgr) ?? "") + text + "\u{1B}[0m"
    }

    private func sgr(_ tone: CliTone) -> String {
        switch depth {
            case .none: return ""
            case .ansi: return "\u{1B}[\(Self.ansi[tone] ?? "39")m"
            case .truecolor:
                guard let (r, g, b) = Self.oneDark[tone] else { return "\u{1B}[1m" }
                return "\u{1B}[38;2;\(r);\(g);\(b)m"
        }
    }

    /// One Dark
    static let oneDark: [CliTone: (Int, Int, Int)] = [
        .accent: (0x61, 0xAF, 0xEF),
        .keyword: (0xC6, 0x78, 0xDD),
        .muted: (0x7F, 0x84, 0x8E), // A step lighter than #5c6370: it is read, not only seen
        .success: (0x98, 0xC3, 0x79),
        .warning: (0xE5, 0xC0, 0x7B),
        .error: (0xE0, 0x6C, 0x75),
        .path: (0x56, 0xB6, 0xC2),
        .string: (0x98, 0xC3, 0x79),
        .number: (0xD1, 0x9A, 0x66),
    ]

    /// The colors of the theme of the terminal, by meaning
    static let ansi: [CliTone: String] = [
        .accent: "34", .keyword: "35", .muted: "90", .success: "32", .warning: "33", .error: "31",
        .path: "36", .string: "32", .number: "33", .strong: "1",
    ]
}

/// The columns of the terminal of the stream: its window, else $COLUMNS, else 80
public func terminalColumns(fd: Int32 = STDOUT_FILENO, environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
    var size = winsize()
    if unsafe ioctl(fd, TIOCGWINSZ, &size) == 0, size.ws_col > 0 { return Int(size.ws_col) }
    if let columns = environment["COLUMNS"].flatMap(Int.init), columns > 0 { return columns }
    return 80
}

extension String {
    /// The path with ~ for the home folder, as the user writes it
    public var tildePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home + "/") ? "~" + dropFirst(home.count) : self
    }

    /// Without the escape sequences of color
    public var withoutAnsi: String {
        replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    /// The cells it takes in a terminal: the wide characters (CJK, emoji) take two, the combining ones none
    public var cellWidth: Int {
        withoutAnsi.reduce(0) { width, character in width + character.cellWidth }
    }

    /// At most `width` cells: the end cut, with an ellipsis
    public func truncatedTail(_ width: Int) -> String {
        guard cellWidth > width else { return self }
        guard width > 1 else { return width == 1 ? "…" : "" }
        var result = ""
        var used = 0
        for character in self {
            let w = character.cellWidth
            if used + w > width - 1 { break }
            result.append(character)
            used += w
        }
        return result + "…"
    }

    /// At most `width` cells: the middle cut, so that the start and the end (a file name) stay
    public func truncatedMiddle(_ width: Int) -> String {
        guard cellWidth > width else { return self }
        guard width > 2 else { return truncatedTail(width) }
        let characters = Array(self)
        let tailBudget = (width - 1) / 2 + (width - 1) % 2
        let headBudget = width - 1 - tailBudget
        var head = ""
        var used = 0
        for character in characters {
            if used + character.cellWidth > headBudget { break }
            head.append(character)
            used += character.cellWidth
        }
        var tail = ""
        used = 0
        for character in characters.reversed() {
            if used + character.cellWidth > tailBudget { break }
            tail.insert(character, at: tail.startIndex)
            used += character.cellWidth
        }
        return head + "…" + tail
    }

    /// Padded with spaces to `width` cells
    public func padded(_ width: Int) -> String {
        self + String(repeating: " ", count: max(0, width - cellWidth))
    }
}

extension Character {
    var cellWidth: Int {
        guard let scalar = unicodeScalars.first else { return 0 }
        // Marks that combine with the previous character, and the invisible ones (U+200E, the mark of the direction of
        // the text, starts the name of WhatsApp)
        let invisible: Set<Unicode.GeneralCategory> = [.nonspacingMark, .enclosingMark, .format, .control]
        if unicodeScalars.allSatisfy({ invisible.contains($0.properties.generalCategory) }) { return 0 }
        if scalar.properties.isEmojiPresentation || unicodeScalars.contains(where: { $0.value == 0xFE0F }) { return 2 }
        switch scalar.value {
            case 0x1100 ... 0x115F, 0x2E80 ... 0x303E, 0x3041 ... 0x33FF, 0x3400 ... 0x4DBF, 0x4E00 ... 0x9FFF,
                 0xA000 ... 0xA4CF, 0xAC00 ... 0xD7A3, 0xF900 ... 0xFAFF, 0xFE30 ... 0xFE4F, 0xFF00 ... 0xFF60,
                 0xFFE0 ... 0xFFE6, 0x20000 ... 0x3FFFD:
                return 2
            default:
                return 1
        }
    }
}

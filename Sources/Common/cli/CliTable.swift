/// A table for people: no borders, a dim header, one row per record. The row that is current has a ● and the
/// accent; no other row has a mark. When the terminal is narrow, the columns of the lowest priority go first, then
/// the ones that can shrink are cut; nothing wraps
public struct CliTable: Sendable {
    public struct Column: Sendable {
        public enum Truncation: Sendable { case tail, middle, none }

        public var title: String
        /// Lower goes first when the table doesn't fit. 0: never dropped
        public var priority: Int
        public var truncation: Truncation
        /// The narrowest it is cut to
        public var minWidth: Int

        public init(_ title: String, priority: Int = 0, truncation: Truncation = .none, minWidth: Int = 8) {
            self.title = title
            self.priority = priority
            self.truncation = truncation
            self.minWidth = minWidth
        }
    }

    public struct Row: Sendable {
        public var cells: [String]
        public var isCurrent: Bool
        /// A cell with a tone of its own: the column and the tone (floating in warning)
        public var tones: [Int: CliTone]

        public init(_ cells: [String], isCurrent: Bool = false, tones: [Int: CliTone] = [:]) {
            self.cells = cells
            self.isCurrent = isCurrent
            self.tones = tones
        }
    }

    public var columns: [Column]
    public var rows: [Row]

    public init(columns: [Column], rows: [Row]) {
        self.columns = columns
        self.rows = rows
    }

    /// The gutter between two columns
    static let gutter = 2
    /// '  ' before the table, and the column of the mark: '● ' or '  '
    static let indent = 4

    /// The lines of the table, at most `width` cells wide. `wide`: every column, cut nowhere
    public func render(width: Int, style: CliStyle, wide: Bool = false) -> [String] {
        var visible = Array(columns.indices)
        func natural(_ index: Int) -> Int {
            ([columns[index].title] + rows.map { $0.cells.getOrNil(atIndex: index) ?? "" }).map(\.cellWidth).max() ?? 0
        }
        var widths = columns.indices.map(natural)
        func total() -> Int { Self.indent + visible.map { widths[$0] }.reduce(0, +) + Self.gutter * max(visible.count - 1, 0) }
        if !wide {
            // The columns of the lowest priority go first, while the ones that can be cut would have to be cut below a
            // width that still reads (24 cells, or their own if it is smaller)
            func comfortable() -> Int {
                total() - visible.filter { columns[$0].truncation != .none }
                    .map { widths[$0] - min(widths[$0], max(columns[$0].minWidth, 24)) }.reduce(0, +)
            }
            while comfortable() > width {
                guard let drop = visible.filter({ columns[$0].priority > 0 }).min(by: { columns[$0].priority < columns[$1].priority }) else { break }
                visible.removeAll { $0 == drop }
            }
            // Then the widest of the ones that can be cut, one cell at a time
            while total() > width {
                guard let widest = visible.filter({ columns[$0].truncation != .none && widths[$0] > columns[$0].minWidth }).max(by: { widths[$0] < widths[$1] }) else { break }
                widths[widest] -= 1
            }
        }

        func cell(_ text: String, _ index: Int, isLast: Bool) -> String {
            let column = columns[index]
            let cut: String = switch column.truncation {
                case _ where wide: text
                case .tail: text.truncatedTail(widths[index])
                case .middle: text.truncatedMiddle(widths[index])
                case .none: text
            }
            return isLast ? cut : cut.padded(widths[index])
        }
        func line(_ texts: [String], tones: [Int: CliTone], render: (String, CliTone?) -> String) -> String {
            visible.enumerated().map { position, index in
                let text = cell(texts.getOrNil(atIndex: index) ?? "", index, isLast: position == visible.count - 1)
                // Padding outside of the color: the escape sequences don't count as cells
                let trimmed = String(text.reversed().drop { $0 == " " }.reversed())
                return render(trimmed, tones[index]) + String(repeating: " ", count: text.count - trimmed.count)
            }.joined(separator: String(repeating: " ", count: Self.gutter))
        }

        var lines = ["    " + style.paint(line(columns.map(\.title), tones: [:]) { text, _ in text }, .muted)]
        for row in rows {
            let body = line(row.cells, tones: row.tones) { text, tone in
                if text == "–" { return style.paint(text, .muted) }
                if row.isCurrent { return style.strong(text, tone) }
                return tone.map { style.paint(text, $0) } ?? text
            }
            lines.append((row.isCurrent ? "  " + style.paint("●", .accent) + " " : "    ") + body)
        }
        return lines.map { String($0.reversed().drop { $0 == " " }.reversed()) }
    }
}

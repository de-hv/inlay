import Common
import Foundation
import Testing

extension InlayTests {
    /// What the CLI prints for people: colors only for a terminal, tables that fit, the help, the errors
    @Suite struct CliTextTest {
        private let color = CliStyle(depth: .truecolor)

        @Test func testWhenThereIsColor() {
            assertEquals(CliStyle.resolve(isTerminal: true, environment: [:]), CliStyle(depth: .ansi))
            assertEquals(CliStyle.resolve(isTerminal: true, environment: ["COLORTERM": "truecolor"]), CliStyle(depth: .truecolor))
            assertEquals(CliStyle.resolve(isTerminal: false, environment: [:]), .plain)
            assertEquals(CliStyle.resolve(isTerminal: true, environment: ["NO_COLOR": "1"]), .plain)
            assertEquals(CliStyle.resolve(isTerminal: true, environment: ["NO_COLOR": ""]), CliStyle(depth: .ansi))
            assertEquals(CliStyle.resolve(isTerminal: true, environment: ["TERM": "dumb"]), .plain)
            assertEquals(CliStyle.resolve(isTerminal: false, environment: ["FORCE_COLOR": "1"]), CliStyle(depth: .ansi))
            assertEquals(CliStyle.resolve(isTerminal: false, environment: ["FORCE_COLOR": "0"]), .plain)
            // INLAY_COLOR wins over everything
            assertEquals(CliStyle.resolve(isTerminal: false, environment: ["INLAY_COLOR": "always", "NO_COLOR": "1"]), CliStyle(depth: .ansi))
            assertEquals(CliStyle.resolve(isTerminal: true, environment: ["INLAY_COLOR": "never"]), .plain)

            assertEquals(CliStyle.plain.paint("text", .error), "text")
            assertEquals(CliStyle(depth: .ansi).paint("text", .error), "\u{1B}[31mtext\u{1B}[0m")
            assertEquals(color.paint("text", .accent), "\u{1B}[38;2;97;175;239mtext\u{1B}[0m")
        }

        @Test func testCellWidth() {
            assertEquals("abc".cellWidth, 3)
            assertEquals("日本".cellWidth, 4)
            assertEquals("👍".cellWidth, 2)
            assertEquals("e\u{301}".cellWidth, 1) // e + a combining accent
            assertEquals("\u{200E}WhatsApp".cellWidth, 8) // The invisible mark of the direction of the text
            assertEquals(color.paint("abc", .accent).cellWidth, 3)
        }

        @Test func testTruncation() {
            assertEquals("Telegram".truncatedTail(5), "Tele…")
            assertEquals("Telegram".truncatedTail(8), "Telegram")
            assertEquals("~/dev/projects/inlay".truncatedMiddle(11), "~/dev…inlay")
            assertEquals("日本語のタイトル".truncatedTail(7).cellWidth <= 7, true)
        }

        private var table: CliTable {
            CliTable(
                columns: [
                    CliTable.Column("ID"),
                    CliTable.Column("TITLE", truncation: .middle, minWidth: 10),
                    CliTable.Column("LAYOUT", priority: 1),
                ],
                rows: [
                    CliTable.Row(["9478", "inlay — ConfigShow.swift", "tiling"], isCurrent: true),
                    CliTable.Row(["9043", "~/dev/projects/inlay/Sources", "floating"], tones: [2: .warning]),
                ],
            )
        }

        @Test func testTable() {
            assertEquals(table.render(width: 80, style: .plain), [
                "    ID    TITLE                         LAYOUT",
                "  ● 9478  inlay — ConfigShow.swift      tiling",
                "    9043  ~/dev/projects/inlay/Sources  floating",
            ])
            // Narrow: the column of the lowest priority goes first, then the title is cut in the middle
            let narrow = table.render(width: 30, style: .plain)
            assertEquals(narrow[0], "    ID    TITLE")
            assertEquals(narrow[2], "    9043  " + "~/dev/projects/inlay/Sources".truncatedMiddle(20))
            for line in table.render(width: 24, style: .plain) { assertEquals(line.cellWidth <= 24, true, additionalMsg: line) }
            // In color the cells stay aligned: the escape sequences take no cells
            let colored = table.render(width: 80, style: color)
            assertEquals(colored.map(\.withoutAnsi), table.render(width: 80, style: .plain))
            assertEquals(colored[2].contains(color.paint("floating", .warning)), true)
            assertEquals(colored[1].contains(color.paint("●", .accent)), true)
        }

        @Test func testEveryCommandIsInTheHelp() {
            let grouped = CliText.groups.flatMap(\.commands)
            assertEquals(grouped.count, Set(grouped).count, additionalMsg: "a command in two groups")
            // exec-and-forget only runs in the bindings: the CLI has no such command
            let commands = Set(CmdKind.allCases.map(\.rawValue)).subtracting(["exec-and-forget"]).union(["uninstall"])
            assertEquals(Set(grouped), commands)

            let help = CliText.help(width: 80, style: .plain)
            for line in help.split(separator: "\n") { assertEquals(String(line).cellWidth <= 80, true, additionalMsg: String(line)) }
            assertEquals(help.contains("  Examples\n    inlay workspace 3"), true, additionalMsg: help)
            let all = CliText.help(descriptions: ["focus": "Set focus to a window."], width: 80, style: .plain)
            assertEquals(all.contains("  Windows\n    focus "), true, additionalMsg: all)
            assertEquals(all.contains("Set focus to a window."), true)
            assertEquals(CliText.help(width: 80, style: color).withoutAnsi, help)
        }

        @Test func testStatus() {
            var status = CliText.Status(version: "0.6.0")
            let stopped = CliText.status(status, width: 80, style: .plain)
            assertEquals(stopped.hasPrefix("  inlay 0.6.0"), true, additionalMsg: stopped)
            assertEquals(stopped.contains("○ not running"), true)
            assertEquals(stopped.hasSuffix("  hint: open Inlay: open -a Inlay"), true, additionalMsg: stopped)

            status.serverVersion = "0.6.0"
            status.mode = "main"
            status.workspace = "2"
            status.workspaceName = "Code"
            status.windows = 3
            status.configPath = "~/.config/inlay"
            status.configTarget = "~/.dotfiles/inlay"
            status.configErrors = 0
            let running = CliText.status(status, width: 80, style: .plain)
            assertEquals(running.contains("● running · mode main"), true, additionalMsg: running)
            assertEquals(running.contains("  workspace   2 Code · 3 windows\n"), true, additionalMsg: running)
            assertEquals(running.contains("  config      ~/.config/inlay → ~/.dotfiles/inlay · ok"), true, additionalMsg: running)

            status.serverVersion = "0.5.0"
            status.configErrors = 2
            let old = CliText.status(status, width: 80, style: .plain)
            assertEquals(old.contains("· 2 errors"), true, additionalMsg: old)
            assertEquals(old.contains("warning: Inlay.app is 0.5.0, this inlay is 0.6.0\n  hint: restart Inlay: open -a Inlay"), true, additionalMsg: old)
        }

        @Test func testDidYouMean() {
            let commands = CliText.groups.flatMap(\.commands)
            assertEquals(CliText.closest("worksapce", among: commands), "workspace")
            assertEquals(CliText.closest("lsit-windows", among: commands), "list-windows")
            assertEquals(CliText.closest("reload", among: commands), "reload-config")
            assertEquals(CliText.closest("xyzzy", among: commands), nil)
            assertEquals(CliText.unknownCommand("worksapce", arguments: ["3"], commands: commands, style: .plain), """
                error: unknown command 'worksapce'
                hint:  did you mean inlay workspace 3
                """)
        }

        @Test func testDiagnostics() {
            let text = "[ERROR] binds.lua:12: inlay.bind: the command is a string, or a list of them\n[WARNING] gaps.smart: gone"
            // Scripts read it as it is
            assertEquals(CliText.diagnostics(text, style: .plain), text)
            let styled = CliText.diagnostics(text, style: color) { file, line in file == "binds.lua" && line == 12 ? "  inlay.bind('cmd-alt-t', 3)" : nil }
            assertEquals(styled.withoutAnsi, """
                error: binds.lua:12: inlay.bind: the command is a string, or a list of them
                   12 │ inlay.bind('cmd-alt-t', 3)
                warning: gaps.smart: gone
                """)
        }

        @Test func testLua() {
            let lua = "inlay.bind('cmd-alt-h', 'focus left')  -- yours (binds.lua:4) · true|false\nlocal x = 12 -- Inlay"
            assertEquals(CliText.lua(lua, style: .plain), lua)
            let styled = CliText.lua(lua, style: color)
            assertEquals(styled.withoutAnsi, lua)
            assertEquals(styled.contains(color.paint("'cmd-alt-h'", .string)), true)
            assertEquals(styled.contains(color.paint("inlay.bind", .accent)), true)
            assertEquals(styled.contains(color.paint("yours (binds.lua:4)", .accent)), true)
            assertEquals(styled.contains(color.paint("12", .number)), true)
            assertEquals(styled.contains(color.paint("local", .keyword)), true)
            // A string with '--' in it isn't a comment
            assertEquals(CliText.lua("x = 'a -- b'", style: color).contains(color.paint("'a -- b'", .string)), true)
            // The prose of --explain stays plain
            assertEquals(CliText.explain("  A key binding: and a command or a list", style: color), "  A key binding: and a command or a list")
            assertEquals(CliText.explain("  A key binding. options: { mode = 'x' } or not", style: color), "  A key binding. options: { mode = 'x' } or not")
            assertEquals(CliText.explain("  mode (without it, 'main'). See: mode", style: color), "  mode (without it, 'main'). See: mode")
            assertEquals(CliText.explain("  inlay.bind('x', 'close')", style: color).withoutAnsi, "  inlay.bind('x', 'close')")
            assertEquals(CliText.explain("    width = 4,", style: color) != "    width = 4,", true)
        }

        @Test func testWorkspacesTable() {
            let workspaces = CliLists.objects(#"[{"workspace":"1","workspace-is-focused":false,"monitor-name":"Built-in Retina Display"},{"workspace":"2","workspace-is-focused":true,"monitor-name":"Built-in Retina Display"},{"workspace":"6","workspace-is-focused":false,"monitor-name":"Built-in Retina Display"}]"#)
            let windows = CliLists.objects(#"[{"workspace":"2","app-name":"Zed"},{"workspace":"2","app-name":"Code"},{"workspace":"1","app-name":"Ghostty"},{"workspace":"2","app-name":"Zed"}]"#)
            let table = CliLists.workspaces(workspaces, windows: windows, names: ["1": "Terminals", "2": "Code"])
            assertEquals(table.render(width: 80, style: .plain), [
                "    WS  NAME       WINDOWS  APPS",
                "    1   Terminals  1        Ghostty",
                "  ● 2   Code       3        Zed · Code",
                "    6              –        –",
            ])
            assertEquals(CliLists.appNames(["A", "B", "C", "D"]), "A · B · +2")
        }
    }
}

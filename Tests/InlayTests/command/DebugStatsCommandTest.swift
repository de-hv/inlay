@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct DebugStatsCommandTest {
        init() {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
            ServerState.shared.isEnabled = true
        }

        private func counted(_ name: String) -> Int { DebugStats.counters[name, default: 0] }

        @Test func testParse() {
            testParseSingleCommandSucc("debug-stats", DebugStatsCmdArgs(rawArgs: []))
            testParseSingleCommandSucc("debug-stats --watch 2", DebugStatsCmdArgs(rawArgs: []).copy(\.watch, 2))
            testParseCommandFail("debug-stats --watch", msg: "ERROR: '--watch' must be followed by '<seconds>'", exitCode: 2)
            for bad in ["0", "-1", "1.5", "soon", "3601"] {
                #expect(parseCommand("debug-stats --watch \(bad)").errorOrNil != nil, "\(bad)")
            }
            testParseCommandFail("debug-stats foo", msg: "ERROR: Unknown argument 'foo'", exitCode: 2)
            testParseCommandHelp("debug-stats -h")
            testParseCommandHelp("debug-stats --help")
        }

        @Test func testReport() {
            let report = DebugStatsReport(
                version: "0.1.0 abc",
                uptime: 100.04,
                interval: 4,
                gauges: [("windows", 12), ("apps", 5)],
                counters: ["ui.publish": 30, "menu-bar.draw.drawn": 7, "session.trigger.ax.AXMoved": 1000],
                previous: ["ui.publish": 20, "menu-bar.draw.drawn": 7],
            )
            assertEquals(report.text, """
                Inlay 0.1.0 abc, running for 100.0 s
                windows: 12   apps: 5

                new and per-sec: the last 4.0 s (since the previous debug-stats). Counters that are still 0 aren't listed

                counter                      total    new   per-sec
                menu-bar.draw.drawn              7      0       0.0
                session.trigger.ax.AXMoved    1000   1000     250.0
                ui.publish                      30     10       2.5
                """)
        }

        @Test func testFirstReportIsSinceTheStart() {
            let report = DebugStatsReport(version: "v", uptime: 10, interval: nil, gauges: [], counters: ["a": 5], previous: [:])
            #expect(report.text.contains("the last 10.0 s (since Inlay started)"))
            #expect(report.text.contains("a             5     5       0.5"))
        }

        @Test func testCommandPrintsTheCounters() async {
            DebugStats.count("test.debug-stats-command", 3)
            let result = await parseCommand("debug-stats").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(result.exitCode.rawValue, 0)
            let out = result.stdout.joined(separator: "\n")
            #expect(out.contains("test.debug-stats-command"))
            #expect(out.contains("windows: 0"))
            #expect(out.contains("border-panels: 0"))

            // The second report only has what was counted since the first one
            DebugStats.count("test.debug-stats-command", 2)
            let second = await parseCommand("debug-stats").cmdOrDie.run(.defaultEnv, .emptyStdin).stdout.joined(separator: "\n")
            #expect(second.contains("since the previous debug-stats"))
            let row = second.split(separator: "\n").first { $0.hasPrefix("test.debug-stats-command") }.map { $0.split(separator: " ") }
            assertEquals(row?.dropFirst().prefix(2).map(String.init), ["5", "2"])
        }

        @Test func testThePublishingOfTheUiStateIsCounted() {
            MenuBarStore.shared.refresh()
            let (publishes, same, changed) = (counted("ui.publish"), counted("menu-bar.snapshot.same"), counted("menu-bar.snapshot.changed"))
            publishUiState()
            publishUiState()
            assertEquals(counted("ui.publish") - publishes, 2)
            assertEquals(counted("menu-bar.snapshot.same") - same, 2)
            assertEquals(counted("menu-bar.snapshot.changed") - changed, 0)

            TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
            publishUiState()
            assertEquals(counted("menu-bar.snapshot.changed") - changed, 1)
        }

        @Test func testTriggerNames() {
            assertEquals(RefreshSessionEvent.ax("AXMoved").statName, "ax.AXMoved")
            assertEquals(RefreshSessionEvent.globalObserver("NSWorkspaceDidActivateApplicationNotification").statName, "workspace.NSWorkspaceDidActivateApplicationNotification")
            assertEquals(RefreshSessionEvent.socketServer(ReloadConfigCmdArgs(rawArgs: [])).statName, "cli.reload-config")
            assertEquals(RefreshSessionEvent.configAutoReload.statName, "config-auto-reload")
            assertEquals(BorderOp.recolor(windowId: 1, .black).statName, "recolor")
        }
    }
}

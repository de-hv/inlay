@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct ListMonitorsTest {
        @Test func testParseListMonitorsCommand() {
            testParseSingleCommandSucc("list-monitors", ListMonitorsCmdArgs(rawArgs: []))
            testParseSingleCommandSucc("list-monitors --focused", ListMonitorsCmdArgs(rawArgs: []).copy(\.focused, true))
            testParseSingleCommandSucc("list-monitors --count", ListMonitorsCmdArgs(rawArgs: []).copy(\.outputOnlyCount, true))
            assertEquals(parseCommand("list-monitors --format %{monitor-id} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        }
    }
}

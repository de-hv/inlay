@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct SummonWorkspaceCommandTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            assertEquals(parseCommand("summon-workspace").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
            testParseSingleCommandSucc("summon-workspace foo", SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())))
        }

        @Test func testParseDashDash() {
            testParseSingleCommandSucc(
                "summon-workspace -- foo",
                SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())),
            )
            testParseSingleCommandSucc(
                "summon-workspace --fail-if-noop -- foo",
                SummonWorkspaceCmdArgs(rawArgs: []).copy(\.target, .initialized(.parse("foo").getOrDie())).copy(\.failIfNoop, true),
            )
            assertEquals(parseCommand("summon-workspace --").errorOrNil, "ERROR: Argument '<workspace>' is mandatory")
            assertEquals(parseCommand("summon-workspace -- --fail-if-noop").errorOrNil, "ERROR: Workspace names starting with dash are disallowed")
        }
    }
}

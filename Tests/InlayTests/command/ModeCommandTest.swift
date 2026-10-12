@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct ModeCommandTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            testParseSingleCommandSucc("mode main", ModeCmdArgs(rawArgs: []).copy(\.targetMode, .initialized("main")))
            assertEquals(parseCommand("mode").errorOrNil, "ERROR: Argument '<binding-mode>' is mandatory")
        }

        @Test func testParseDashDash() {
            testParseSingleCommandSucc(
                "mode -- main",
                ModeCmdArgs(rawArgs: []).copy(\.targetMode, .initialized("main")),
            )
            testParseSingleCommandSucc(
                "mode -- --foo",
                ModeCmdArgs(rawArgs: []).copy(\.targetMode, .initialized("--foo")),
            )
            assertEquals(parseCommand("mode --").errorOrNil, "ERROR: Argument '<binding-mode>' is mandatory")
        }
    }
}

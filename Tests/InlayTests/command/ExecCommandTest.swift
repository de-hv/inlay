@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct ExecCommandTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParseExecCommand() {
            testParseSingleCommandSucc("exec-and-forget echo 'foo'", ExecAndForgetCmdArgs(bashScript: " echo 'foo'"))
        }
    }
}

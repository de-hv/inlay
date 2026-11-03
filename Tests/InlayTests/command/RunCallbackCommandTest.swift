@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct RunCallbackCommandTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            testParseSingleCommandSucc(
                "run-callback onWindowDetected",
                RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onWindowDetected)),
            )
            testParseSingleCommandSucc(
                "run-callback --for-every-window onWindowDetected",
                RunCallbackCmdArgs(rawArgs: [])
                    .copy(\.callback, .initialized(.onWindowDetected))
                    .copy(\.forEveryWindow, true),
            )
            testParseSingleCommandSucc(
                "run-callback --window-id 42 onWindowDetected",
                RunCallbackCmdArgs(rawArgs: [])
                    .copy(\.callback, .initialized(.onWindowDetected))
                    .copy(\.windowId, 42),
            )
            testParseSingleCommandSucc(
                "run-callback onFocusChanged",
                RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onFocusChanged)),
            )
            testParseSingleCommandSucc(
                "run-callback onFocusedMonitorChanged",
                RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onFocusedMonitorChanged)),
            )
        }

        @Test func testParseFailure() {
            testParseCommandFail("run-callback", msg: "ERROR: Argument '<callback>' is mandatory", exitCode: 2)
            testParseCommandFail(
                "run-callback bogus",
                msg: "ERROR: Can't parse 'bogus'.\n       Possible values: (onWindowDetected|onFocusChanged|onFocusedMonitorChanged)",
                exitCode: 2,
            )
            testParseCommandFail(
                "run-callback --for-every-window --window-id 1 onWindowDetected",
                msg: "ERROR: Conflicting options: --for-every-window, --window-id",
                exitCode: 2,
            )
            testParseCommandFail(
                "run-callback --for-every-window onFocusChanged",
                msg: "--for-every-window is only allowed with 'onWindowDetected'",
                exitCode: 2,
            )
            testParseCommandFail(
                "run-callback --window-id 1 onFocusedMonitorChanged",
                msg: "--window-id is only allowed with 'onWindowDetected'",
                exitCode: 2,
            )
        }
    }
}

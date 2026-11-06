@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct RunCallbackCommandTest {
        init() { setUpWorkspacesForTests() }

        @Test func testParse() {
            testParseSingleCommandSucc(
                "run-callback on_window_detected",
                RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onWindowDetected)),
            )
            testParseSingleCommandSucc(
                "run-callback --for-every-window on_window_detected",
                RunCallbackCmdArgs(rawArgs: [])
                    .copy(\.callback, .initialized(.onWindowDetected))
                    .copy(\.forEveryWindow, true),
            )
            testParseSingleCommandSucc(
                "run-callback --window-id 42 on_window_detected",
                RunCallbackCmdArgs(rawArgs: [])
                    .copy(\.callback, .initialized(.onWindowDetected))
                    .copy(\.windowId, 42),
            )
            testParseSingleCommandSucc(
                "run-callback on_focus_changed",
                RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onFocusChanged)),
            )
            testParseSingleCommandSucc(
                "run-callback on_focused_monitor_changed",
                RunCallbackCmdArgs(rawArgs: []).copy(\.callback, .initialized(.onFocusedMonitorChanged)),
            )
        }

        @Test func testParseFailure() {
            testParseCommandFail("run-callback", msg: "ERROR: Argument '<callback>' is mandatory", exitCode: 2)
            testParseCommandFail(
                "run-callback bogus",
                msg: "ERROR: Can't parse 'bogus'.\n       Possible values: (on_window_detected|on_focus_changed|on_focused_monitor_changed)",
                exitCode: 2,
            )
            testParseCommandFail(
                "run-callback --for-every-window --window-id 1 on_window_detected",
                msg: "ERROR: Conflicting options: --for-every-window, --window-id",
                exitCode: 2,
            )
            testParseCommandFail(
                "run-callback --for-every-window on_focus_changed",
                msg: "--for-every-window is only allowed with 'on_window_detected'",
                exitCode: 2,
            )
            testParseCommandFail(
                "run-callback --window-id 1 on_focused_monitor_changed",
                msg: "--window-id is only allowed with 'on_window_detected'",
                exitCode: 2,
            )
        }
    }
}

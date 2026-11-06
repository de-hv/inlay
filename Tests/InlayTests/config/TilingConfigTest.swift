@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct TilingConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig(lua: "inlay.config({})")
            assertEquals(result.errors, [])
            assertEquals(
                result.config.tiling,
                TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5, startupLayout: .grid, splitTarget: .focused, minWindowSize: 100),
            )
        }

        @Test func testParse() {
            let result = parseConfig(lua: """
                inlay.config({
                  tiling = {
                    new_window_placement = 'after-focused',
                    split_ratio = 0.6,
                    startup_layout = 'row',
                    split_target = 'cursor',
                    min_window_size = 240,
                  },
                })
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            assertEquals(
                result.config.tiling,
                TilingConfig(newWindowPlacement: .afterFocused, splitRatio: 0.6, startupLayout: .row, splitTarget: .cursor, minWindowSize: 240),
            )
            for target in SplitTarget.allCases {
                let parsed = parseConfig(lua: "inlay.config({ tiling = { split_target = '\(target.rawValue)' } })")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.tiling.splitTarget, target)
            }
            for layout in StartupLayout.allCases {
                let parsed = parseConfig(lua: "inlay.config({ tiling = { startup_layout = '\(layout.rawValue)' } })")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.tiling.startupLayout, layout)
            }

            let dwindle = parseConfig(lua: "inlay.config({ tiling = { new_window_placement = 'dwindle' } })")
            assertEquals(dwindle.errors, [])
            assertEquals(dwindle.config.tiling, TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5))
        }

        @Test func testSplitRatioBounds() {
            for (raw, expected) in [("0.1", 0.1), ("0.9", 0.9), ("0.25", 0.25)] {
                let result = parseConfig(lua: "inlay.config({ tiling = { split_ratio = \(raw) } })")
                assertEquals(result.errors, [])
                assertEquals(result.config.tiling.splitRatio, expected)
            }
            for raw in ["0.09", "0.91", "0.0", "1.0", "-0.5", "1", "0"] {
                assertEquals(
                    parseConfig(lua: "inlay.config({ tiling = { split_ratio = \(raw) } })").strErrors,
                    ["[ERROR] tiling.split_ratio: split_ratio must be in [0.1, 0.9] range"],
                    additionalMsg: raw,
                )
            }
            // The value with an error is ignored
            assertEquals(parseConfig(lua: "inlay.config({ tiling = { split_ratio = 2.0 } })").config.tiling.splitRatio, 0.5)
        }

        @Test func testMinWindowSizeBounds() {
            for (raw, expected) in [("20", 20), ("100", 100), ("500", 500)] as [(String, CGFloat)] {
                let result = parseConfig(lua: "inlay.config({ tiling = { min_window_size = \(raw) } })")
                assertEquals(result.errors, [])
                assertEquals(result.config.tiling.minWindowSize, expected)
            }
            for raw in ["19", "501", "0", "-100"] {
                assertEquals(
                    parseConfig(lua: "inlay.config({ tiling = { min_window_size = \(raw) } })").strErrors,
                    ["[ERROR] tiling.min_window_size: min_window_size must be in [20, 500] range"],
                    additionalMsg: raw,
                )
            }
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { min_window_size = 100.5 } })").strErrors,
                ["[ERROR] tiling.min_window_size: Expected type is 'Int'. But actual type is 'Float'"],
            )
            // The value with an error is ignored
            assertEquals(parseConfig(lua: "inlay.config({ tiling = { min_window_size = 5 } })").config.tiling.minWindowSize, 100)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { new_window_placement = 'spiral' } })").strErrors,
                ["[ERROR] tiling.new_window_placement: Can't parse new window placement 'spiral'. Possible values: (dwindle|after-focused)"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { new_window_placement = 1 } })").strErrors,
                ["[ERROR] tiling.new_window_placement: Expected type is 'String'. But actual type is 'Int'"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { split_ratio = 'half' } })").strErrors,
                ["[ERROR] tiling.split_ratio: Expected type is 'Float'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { startup_layout = 'spiral' } })").strErrors,
                ["[ERROR] tiling.startup_layout: Can't parse startup layout 'spiral'. Possible values: (grid|row|dwindle)"],
            )
            assertEquals(parseConfig(lua: "inlay.config({ tiling = { startup_layout = 'spiral' } })").config.tiling.startupLayout, .grid)
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { startup_layout = true } })").strErrors,
                ["[ERROR] tiling.startup_layout: Expected type is 'String'. But actual type is 'Bool'"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { split_target = 'mouse' } })").strErrors,
                ["[ERROR] tiling.split_target: Can't parse split target 'mouse'. Possible values: (focused|cursor)"],
            )
            assertEquals(parseConfig(lua: "inlay.config({ tiling = { split_target = 'mouse' } })").config.tiling.splitTarget, .focused)
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { ['split-ratio'] = 0.5 } })").strErrors,
                ["[ERROR] tiling.split-ratio: Unknown key. The keys are snake_case since Inlay 0.6.2: 'split_ratio'"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = { splitRatio = 0.5 } })").strErrors,
                ["[ERROR] tiling.splitRatio: Unknown key. The keys are snake_case since Inlay 0.6.2: 'split_ratio'"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ menuBar = { enabled = false } })").strErrors,
                ["[ERROR] menuBar: Unknown top-level key. The keys are snake_case since Inlay 0.6.2: 'menu_bar'"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ tiling = 'dwindle' })").strErrors,
                ["[ERROR] tiling: Expected type is 'Table'. But actual type is 'String'"],
            )
        }
    }
}

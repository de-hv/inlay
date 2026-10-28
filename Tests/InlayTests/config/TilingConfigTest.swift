@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct TilingConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig("config-version = 2")
            assertEquals(result.errors, [])
            assertEquals(
                result.config.tiling,
                TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5, startupLayout: .grid, splitTarget: .focused, minWindowSize: 100),
            )
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                config-version = 2
                [tiling]
                    new-window-placement = 'after-focused'
                    split-ratio = 0.6
                    startup-layout = 'row'
                    split-target = 'cursor'
                    min-window-size = 240
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            assertEquals(
                result.config.tiling,
                TilingConfig(newWindowPlacement: .afterFocused, splitRatio: 0.6, startupLayout: .row, splitTarget: .cursor, minWindowSize: 240),
            )
            for target in SplitTarget.allCases {
                let parsed = parseConfig("tiling.split-target = '\(target.rawValue)'")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.tiling.splitTarget, target)
            }
            for layout in StartupLayout.allCases {
                let parsed = parseConfig("tiling.startup-layout = '\(layout.rawValue)'")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.tiling.startupLayout, layout)
            }

            let dwindle = parseConfig("tiling.new-window-placement = 'dwindle'")
            assertEquals(dwindle.errors, [])
            assertEquals(dwindle.config.tiling, TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5))
        }

        @Test func testSplitRatioBounds() {
            for (raw, expected) in [("0.1", 0.1), ("0.9", 0.9), ("0.25", 0.25)] {
                let result = parseConfig("tiling.split-ratio = \(raw)")
                assertEquals(result.errors, [])
                assertEquals(result.config.tiling.splitRatio, expected)
            }
            for raw in ["0.09", "0.91", "0.0", "1.0", "-0.5", "1", "0"] {
                assertEquals(
                    parseConfig("tiling.split-ratio = \(raw)").strErrors,
                    ["[ERROR] tiling.split-ratio: split-ratio must be in [0.1, 0.9] range"],
                    additionalMsg: raw,
                )
            }
            // The value with an error is ignored
            assertEquals(parseConfig("tiling.split-ratio = 2.0").config.tiling.splitRatio, 0.5)
        }

        @Test func testMinWindowSizeBounds() {
            for (raw, expected) in [("20", 20), ("100", 100), ("500", 500)] as [(String, CGFloat)] {
                let result = parseConfig("tiling.min-window-size = \(raw)")
                assertEquals(result.errors, [])
                assertEquals(result.config.tiling.minWindowSize, expected)
            }
            for raw in ["19", "501", "0", "-100"] {
                assertEquals(
                    parseConfig("tiling.min-window-size = \(raw)").strErrors,
                    ["[ERROR] tiling.min-window-size: min-window-size must be in [20, 500] range"],
                    additionalMsg: raw,
                )
            }
            assertEquals(
                parseConfig("tiling.min-window-size = 100.5").strErrors,
                ["[ERROR] tiling.min-window-size: Expected type is 'Int'. But actual type is 'Float'"],
            )
            // The value with an error is ignored
            assertEquals(parseConfig("tiling.min-window-size = 5").config.tiling.minWindowSize, 100)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig("tiling.new-window-placement = 'spiral'").strErrors,
                ["[ERROR] tiling.new-window-placement: Can't parse new window placement 'spiral'. Possible values: (dwindle|after-focused)"],
            )
            assertEquals(
                parseConfig("tiling.new-window-placement = 1").strErrors,
                ["[ERROR] tiling.new-window-placement: Expected type is 'String'. But actual type is 'Int'"],
            )
            assertEquals(
                parseConfig("tiling.split-ratio = 'half'").strErrors,
                ["[ERROR] tiling.split-ratio: Expected type is 'Float'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig("tiling.startup-layout = 'spiral'").strErrors,
                ["[ERROR] tiling.startup-layout: Can't parse startup layout 'spiral'. Possible values: (grid|row|dwindle)"],
            )
            assertEquals(parseConfig("tiling.startup-layout = 'spiral'").config.tiling.startupLayout, .grid)
            assertEquals(
                parseConfig("tiling.startup-layout = true").strErrors,
                ["[ERROR] tiling.startup-layout: Expected type is 'String'. But actual type is 'Bool'"],
            )
            assertEquals(
                parseConfig("tiling.split-target = 'mouse'").strErrors,
                ["[ERROR] tiling.split-target: Can't parse split target 'mouse'. Possible values: (focused|cursor)"],
            )
            assertEquals(parseConfig("tiling.split-target = 'mouse'").config.tiling.splitTarget, .focused)
            assertEquals(
                parseConfig("tiling.split-ration = 0.5").strErrors,
                ["[ERROR] tiling.split-ration: Unknown key"],
            )
            assertEquals(
                parseConfig("tiling = 'dwindle'").strErrors,
                ["[ERROR] tiling: Expected type is 'Table'. But actual type is 'String'"],
            )
        }
    }
}

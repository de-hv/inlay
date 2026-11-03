@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct TilingConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig("configVersion = 2")
            assertEquals(result.errors, [])
            assertEquals(
                result.config.tiling,
                TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5, startupLayout: .grid, splitTarget: .focused, minWindowSize: 100),
            )
        }

        @Test func testParse() {
            let result = parseConfig(
                """
                configVersion = 2
                [tiling]
                    newWindowPlacement = 'after-focused'
                    splitRatio = 0.6
                    startupLayout = 'row'
                    splitTarget = 'cursor'
                    minWindowSize = 240
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            assertEquals(
                result.config.tiling,
                TilingConfig(newWindowPlacement: .afterFocused, splitRatio: 0.6, startupLayout: .row, splitTarget: .cursor, minWindowSize: 240),
            )
            for target in SplitTarget.allCases {
                let parsed = parseConfig("tiling.splitTarget = '\(target.rawValue)'")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.tiling.splitTarget, target)
            }
            for layout in StartupLayout.allCases {
                let parsed = parseConfig("tiling.startupLayout = '\(layout.rawValue)'")
                assertEquals(parsed.errors, [])
                assertEquals(parsed.config.tiling.startupLayout, layout)
            }

            let dwindle = parseConfig("tiling.newWindowPlacement = 'dwindle'")
            assertEquals(dwindle.errors, [])
            assertEquals(dwindle.config.tiling, TilingConfig(newWindowPlacement: .dwindle, splitRatio: 0.5))
        }

        @Test func testSplitRatioBounds() {
            for (raw, expected) in [("0.1", 0.1), ("0.9", 0.9), ("0.25", 0.25)] {
                let result = parseConfig("tiling.splitRatio = \(raw)")
                assertEquals(result.errors, [])
                assertEquals(result.config.tiling.splitRatio, expected)
            }
            for raw in ["0.09", "0.91", "0.0", "1.0", "-0.5", "1", "0"] {
                assertEquals(
                    parseConfig("tiling.splitRatio = \(raw)").strErrors,
                    ["[ERROR] tiling.splitRatio: splitRatio must be in [0.1, 0.9] range"],
                    additionalMsg: raw,
                )
            }
            // The value with an error is ignored
            assertEquals(parseConfig("tiling.splitRatio = 2.0").config.tiling.splitRatio, 0.5)
        }

        @Test func testMinWindowSizeBounds() {
            for (raw, expected) in [("20", 20), ("100", 100), ("500", 500)] as [(String, CGFloat)] {
                let result = parseConfig("tiling.minWindowSize = \(raw)")
                assertEquals(result.errors, [])
                assertEquals(result.config.tiling.minWindowSize, expected)
            }
            for raw in ["19", "501", "0", "-100"] {
                assertEquals(
                    parseConfig("tiling.minWindowSize = \(raw)").strErrors,
                    ["[ERROR] tiling.minWindowSize: minWindowSize must be in [20, 500] range"],
                    additionalMsg: raw,
                )
            }
            assertEquals(
                parseConfig("tiling.minWindowSize = 100.5").strErrors,
                ["[ERROR] tiling.minWindowSize: Expected type is 'Int'. But actual type is 'Float'"],
            )
            // The value with an error is ignored
            assertEquals(parseConfig("tiling.minWindowSize = 5").config.tiling.minWindowSize, 100)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig("tiling.newWindowPlacement = 'spiral'").strErrors,
                ["[ERROR] tiling.newWindowPlacement: Can't parse new window placement 'spiral'. Possible values: (dwindle|after-focused)"],
            )
            assertEquals(
                parseConfig("tiling.newWindowPlacement = 1").strErrors,
                ["[ERROR] tiling.newWindowPlacement: Expected type is 'String'. But actual type is 'Int'"],
            )
            assertEquals(
                parseConfig("tiling.splitRatio = 'half'").strErrors,
                ["[ERROR] tiling.splitRatio: Expected type is 'Float'. But actual type is 'String'"],
            )
            assertEquals(
                parseConfig("tiling.startupLayout = 'spiral'").strErrors,
                ["[ERROR] tiling.startupLayout: Can't parse startup layout 'spiral'. Possible values: (grid|row|dwindle)"],
            )
            assertEquals(parseConfig("tiling.startupLayout = 'spiral'").config.tiling.startupLayout, .grid)
            assertEquals(
                parseConfig("tiling.startupLayout = true").strErrors,
                ["[ERROR] tiling.startupLayout: Expected type is 'String'. But actual type is 'Bool'"],
            )
            assertEquals(
                parseConfig("tiling.splitTarget = 'mouse'").strErrors,
                ["[ERROR] tiling.splitTarget: Can't parse split target 'mouse'. Possible values: (focused|cursor)"],
            )
            assertEquals(parseConfig("tiling.splitTarget = 'mouse'").config.tiling.splitTarget, .focused)
            assertEquals(
                parseConfig("tiling.split-ration = 0.5").strErrors,
                ["[ERROR] tiling.split-ration: Unknown key. The keys are camelCase since Inlay 0.3.0: 'splitRation'"],
            )
            assertEquals(
                parseConfig("tiling = 'dwindle'").strErrors,
                ["[ERROR] tiling: Expected type is 'Table'. But actual type is 'String'"],
            )
        }
    }
}

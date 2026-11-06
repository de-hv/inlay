@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct BordersConfigTest {
        init() { setUpWorkspacesForTests() }

        @Test func testDefaults() {
            let result = parseConfig(lua: "inlay.config({ theme = {} })")
            assertEquals(result.errors, [])
            let borders = result.config.borders
            assertEquals(borders.enabled, true)
            assertEquals(borders.width, 4)
            assertEquals(borders.cornerRadius, 16)
            assertEquals(borders.squareCorners, true)
            assertEquals(borders.activeColor, .systemAccent)
            assertEquals(borders.inactiveColor.description, "#8E8E9373")
            assertEquals(borders.floatingColor.description, "#BF5AF2")
            assertEquals(borders.modeColors, [:])
            assertEquals(borders.glow, false)
            assertEquals(borders.glowRadius, 12)
            assertEquals(borders.singleWindow, SingleWindowBorder(enabled: true, width: 1, gap: 2))
        }

        @Test func testParse() {
            let result = parseConfig(lua: """
                inlay.config({
                  borders = {
                    enabled = false,
                    width = 6,
                    corner_radius = 10,
                    square_corners = false,
                    active_color = '#D19A66',
                    inactive_color = '#00000000',
                    floating_color = 'system-accent',
                    glow = true,
                    glow_radius = 20,
                    mode_colors = { resize = '#30D158', service = '#FF453A80' },
                  },
                })
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.borders, BordersConfig(
                enabled: false,
                width: 6,
                cornerRadius: 10,
                squareCorners: false,
                activeColor: .rgba(Rgba(hex: "#D19A66").orDie()),
                inactiveColor: .rgba(Rgba(red: 0, green: 0, blue: 0, alpha: 0)),
                floatingColor: .systemAccent,
                modeColors: [
                    "resize": .rgba(Rgba(hex: "#30D158").orDie()),
                    "service": .rgba(Rgba(hex: "#FF453A80").orDie()),
                ],
                glow: true,
                glowRadius: 20,
            ))
        }

        @Test func testRanges() {
            for (key, good, bad) in [("width", [1, 20], [0, 21, -1]), ("corner_radius", [0, 40], [-1, 41]), ("glow_radius", [1, 12, 40], [0, 41, -1])] {
                for value in good {
                    assertEquals(parseConfig(lua: "inlay.config({ borders = { ['\(key)'] = \(value) } })").errors, [])
                }
                for value in bad {
                    assertEquals(parseConfig(lua: "inlay.config({ borders = { ['\(key)'] = \(value) } })").errors.count, 1)
                }
            }
            assertEquals(
                parseConfig(lua: "inlay.config({ borders = { width = 21 } })").strErrors,
                ["[ERROR] borders.width: width must be in [1, 20] range"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ borders = { corner_radius = 41 } })").strErrors,
                ["[ERROR] borders.corner_radius: corner_radius must be in [0, 40] range"],
            )
            assertEquals(
                parseConfig(lua: "inlay.config({ borders = { glow_radius = 0 } })").strErrors,
                ["[ERROR] borders.glow_radius: glow_radius must be in [1, 40] range"],
            )
            // The value with an error is ignored
            assertEquals(parseConfig(lua: "inlay.config({ borders = { glow_radius = 0 } })").config.borders.glowRadius, 12)
        }

        @Test func testErrors() {
            assertEquals(
                parseConfig(lua: """
                    inlay.config({
                      borders = {
                        glow = 'soft',
                        glow_radius = 1.5,
                        shadow = true,
                        width = '4',
                        enabled = 1,
                        active_color = 'auto',
                        inactive_color = 'red',
                        mode_colors = { resize = 'auto', service = 5 },
                      },
                    })
                    """,
                ).strErrors,
                [
                    // 'auto' has no meaning for a border
                    "[ERROR] borders.active_color: Can't parse color 'auto'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'",
                    "[ERROR] borders.enabled: Expected type is 'Bool'. But actual type is 'Int'",
                    "[ERROR] borders.glow: Expected type is 'Bool'. But actual type is 'String'",
                    "[ERROR] borders.glow_radius: Expected type is 'Int'. But actual type is 'Float'",
                    "[ERROR] borders.inactive_color: Can't parse color 'red'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'",
                    "[ERROR] borders.mode_colors.resize: Can't parse color 'auto'. Expected: '#RRGGBB', '#RRGGBBAA', 'system-accent'",
                    "[ERROR] borders.mode_colors.service: Expected type is 'String'. But actual type is 'Int'",
                    "[ERROR] borders.shadow: Unknown key",
                    "[ERROR] borders.width: Expected type is 'Int'. But actual type is 'String'",
                ],
            )
            assertEquals(parseConfig(lua: "inlay.config({ borders = 1 })").strErrors, ["[ERROR] borders: Expected type is 'Table'. But actual type is 'Int'"])
            assertEquals(parseConfig(lua: "inlay.config({ borders = { mode_colors = 1 } })").strErrors, ["[ERROR] borders.mode_colors: Expected type is 'Table'. But actual type is 'Int'"])
        }
    }
}

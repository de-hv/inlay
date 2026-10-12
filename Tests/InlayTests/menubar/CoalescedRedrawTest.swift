@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// The menu bar item once kept the main thread busy forever: every new image made AppKit report a change of
    /// the appearance of the button, and every report drew a new image. See: CoalescedRedraw
    @Suite @MainActor struct CoalescedRedrawTest {
        /// What a redraw draws from, and what it has drawn
        @MainActor private final class Sink {
            var key: Int? = 1
            var keyReads = 0
            var drawn: [Int] = []
            var onDraw: (() -> Void)? = nil
            private(set) lazy var redraw = CoalescedRedraw<Int>(
                name: "test.draw",
                key: { [unowned self] in
                    keyReads += 1
                    return key
                },
                draw: { [unowned self] in
                    drawn.append($0)
                    onDraw?()
                },
            )
        }

        /// Lets the pending requests run
        private func settle() async {
            for _ in 0 ..< 20 { await Task.yield() }
        }

        @Test func testSameKeyIsDrawnOnce() {
            let sink = Sink()
            sink.redraw.drawIfChanged()
            sink.redraw.drawIfChanged()
            sink.redraw.drawIfChanged()
            assertEquals(sink.drawn, [1])

            sink.key = 2
            sink.redraw.drawIfChanged()
            sink.redraw.drawIfChanged()
            assertEquals(sink.drawn, [1, 2])

            // Back to a key that was drawn before: it isn't what is drawn now
            sink.key = 1
            sink.redraw.drawIfChanged()
            assertEquals(sink.drawn, [1, 2, 1])
        }

        @Test func testNothingToDraw() {
            let sink = Sink()
            sink.key = nil
            sink.redraw.drawIfChanged()
            assertEquals(sink.drawn, [])
            sink.key = 1
            sink.redraw.drawIfChanged()
            assertEquals(sink.drawn, [1])
        }

        @Test func testBurstOfRequestsIsOneDrawing() async {
            let sink = Sink()
            for _ in 0 ..< 1000 { sink.redraw.request("burst") }
            // A request never draws on its own, and it doesn't even look at the key
            assertEquals(sink.drawn, [])
            assertEquals(sink.keyReads, 0)
            await settle()
            assertEquals(sink.drawn, [1])
            assertEquals(sink.keyReads, 1)

            // The same burst again, with nothing new to draw
            for _ in 0 ..< 1000 { sink.redraw.request("burst") }
            await settle()
            assertEquals(sink.drawn, [1])
            assertEquals(sink.keyReads, 2)
        }

        /// The loop of the menu bar item: drawing causes a request to draw
        @Test func testDrawingThatAsksToDrawAgainStops() async {
            let sink = Sink()
            sink.onDraw = { sink.redraw.request("feedback") }
            sink.redraw.request("start")
            await settle()
            assertEquals(sink.drawn, [1])
            // The drawing, and the single look at the key that its own request ended up in
            assertEquals(sink.keyReads, 2)
            await settle()
            assertEquals(sink.keyReads, 2)
        }

        @Test func testRequestsAreCounted() async {
            let before = DebugStats.counters
            func counted(_ name: String) -> Int { DebugStats.counters[name, default: 0] - before[name, default: 0] }
            let sink = Sink()
            for _ in 0 ..< 5 { sink.redraw.request("appearance") }
            sink.redraw.request("screens")
            await settle()
            sink.redraw.request("appearance")
            await settle()
            assertEquals(counted("test.draw.request.appearance"), 6)
            assertEquals(counted("test.draw.request.screens"), 1)
            assertEquals(counted("test.draw.drawn"), 1)
            assertEquals(counted("test.draw.skipped-same"), 1)
        }

        @Test func testMenuBarImageDependsOnNothingButItsKey() throws {
            let state = MenuBarState(snapshot: MenuBarSamples.snapshot, config: MenuBarConfig())
            let key = MenuBarDrawKey(state: state, isDarkBar: true, systemAccent: Rgba(hex: "#0A84FF").orDie(), scale: 2)
            let first = try #require(MenuBarRenderer.image(key)?.tiffRepresentation)
            let second = try #require(MenuBarRenderer.image(key)?.tiffRepresentation)
            assertEquals(first, second)

            var other = key
            other.state.config.theme = .square
            #expect(key != other)
            #expect(try #require(MenuBarRenderer.image(other)?.tiffRepresentation) != first)
        }

        /// The appearance of the button is only a part of the key of an image that isn't a template
        @Test func testTemplateImageDoesNotFollowTheBar() {
            let fixed = MenuBarColors(focused: .rgba(Rgba(hex: "#FF9F0A").orDie()))
            let accent = MenuBarColors(accent: .systemAccent)
            for (colors, needsColor) in [(MenuBarColors(), false), (MenuBarColors(), true), (fixed, false), (accent, false), (accent, true)] {
                let isTemplate = MenuBarPalette.isTemplate(colors, needsColor: needsColor)
                let config = MenuBarConfig(colors: colors)
                func palette(isDarkBar: Bool) -> MenuBarPalette {
                    .resolve(config, style: .chips, isDarkBar: isDarkBar, systemAccent: .black, needsColor: needsColor)
                }
                assertEquals(palette(isDarkBar: true).isTemplate, isTemplate)
                assertEquals(palette(isDarkBar: true) == palette(isDarkBar: false), isTemplate)
            }
        }

        @Test func testFontsAndSizesAreCached() {
            for font in [MenuBarFont.chipName, .squareName, .modeInitial, .chipModeInitial] {
                #expect(font.nsFont === font.nsFont)
                let size = MenuBarFont.size(of: "12", font)
                assertEquals(MenuBarFont.size(of: "12", font), size)
                assertEquals(size, NSAttributedString(string: "12", attributes: [.font: font.nsFont]).size())
            }
            #expect(MenuBarFont.size(of: "1", .chipName) != MenuBarFont.size(of: "10", .chipName))
            #expect(MenuBarFont.size(of: "R", .modeInitial) != MenuBarFont.size(of: "R", .chipModeInitial))
        }
    }
}

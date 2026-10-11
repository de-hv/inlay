@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// The pure part of the borders: colors, diff, stacking, frame correction and geometry
    @Suite struct BordersLogicTest {
        private let accent = Rgba(red: 1, green: 0.6, blue: 0)
        private let frame = CGRect(x: 10, y: 20, width: 300, height: 200)
        private func item(_ id: UInt32, _ frame: CGRect? = nil, _ color: Rgba = .white, width: CGFloat = 4, radius: CGFloat = 16) -> BorderItem {
            BorderItem(windowId: id, frame: frame ?? self.frame, color: color, width: width, cornerRadius: radius)
        }

        // MARK: - Colors

        @Test func testColors() {
            var config = BordersConfig()
            config.modeColors = ["resize": .rgba(Rgba(hex: "#30D158").orDie())]
            let candidates = [
                BorderCandidate(windowId: 1, frame: frame, isFocused: true),
                BorderCandidate(windowId: 2, frame: frame),
                BorderCandidate(windowId: 3, frame: frame, isFloating: true),
            ]
            func colors(_ candidates: [BorderCandidate], mode: String?) -> [String] {
                BordersSnapshot.resolve(candidates, config, mode: mode, systemAccent: accent).items.map(\.color.hex)
            }
            // Active ('system-accent' resolved), inactive, and a floating window that isn't focused is inactive too
            assertEquals(colors(candidates, mode: "main"), [accent.hex, "#8E8E9373", "#8E8E9373"])
            // The mode has a color: only the focused window takes it
            assertEquals(colors(candidates, mode: "resize"), ["#30D158", "#8E8E9373", "#8E8E9373"])
            // A mode without a color, and no mode at all
            assertEquals(colors(candidates, mode: "service"), [accent.hex, "#8E8E9373", "#8E8E9373"])
            assertEquals(colors(candidates, mode: nil), [accent.hex, "#8E8E9373", "#8E8E9373"])

            let floatingFocused = [
                BorderCandidate(windowId: 1, frame: frame),
                BorderCandidate(windowId: 3, frame: frame, isFocused: true, isFloating: true),
            ]
            assertEquals(colors(floatingFocused, mode: "main"), ["#8E8E9373", "#BF5AF2"])
            // The mode wins over the floating color
            assertEquals(colors(floatingFocused, mode: "resize"), ["#8E8E9373", "#30D158"])
        }

        @Test func testWidthAndRadiusComeFromTheConfig() {
            var config = BordersConfig()
            config.width = 7
            config.cornerRadius = 3
            let snapshot = BordersSnapshot.resolve([BorderCandidate(windowId: 1, frame: frame)], config, mode: nil, systemAccent: accent)
            assertEquals(snapshot.items, [item(1, frame, Rgba(hex: "#8E8E9373").orDie(), width: 7, radius: 3)])
        }

        @Test func testTransparentColorMeansNoBorder() {
            var config = BordersConfig()
            config.inactiveColor = .rgba(Rgba(hex: "#00000000").orDie())
            let candidates = [
                BorderCandidate(windowId: 1, frame: frame),
                BorderCandidate(windowId: 2, frame: frame, isFocused: true),
                BorderCandidate(windowId: 3, frame: frame, isFloating: true),
            ]
            // "Only the active window"
            assertEquals(BordersSnapshot.resolve(candidates, config, mode: nil, systemAccent: accent).items.map(\.windowId), [2])
            // A transparent mode color hides the border of the focused window
            config.modeColors = ["service": .rgba(Rgba(hex: "#FF453A00").orDie())]
            assertEquals(BordersSnapshot.resolve(candidates, config, mode: "service", systemAccent: accent).items, [])
            // The color of the RGB part doesn't matter, only the alpha
            config.activeColor = .rgba(Rgba(hex: "#FFFFFF00").orDie())
            assertEquals(BordersSnapshot.resolve(candidates, config, mode: nil, systemAccent: accent).items, [])
        }

        @Test func testDisabledAndDegenerate() {
            var config = BordersConfig()
            let candidates = [
                BorderCandidate(windowId: 1, frame: frame, isFocused: true),
                BorderCandidate(windowId: 1, frame: frame), // The same window twice
                BorderCandidate(windowId: 2, frame: CGRect(x: 0, y: 0, width: 0, height: 100)),
            ]
            assertEquals(BordersSnapshot.resolve(candidates, config, mode: nil, systemAccent: accent).items.map(\.windowId), [1])
            config.enabled = false
            assertEquals(BordersSnapshot.resolve(candidates, config, mode: nil, systemAccent: accent), .empty)
        }

        // MARK: - Diff

        @Test func testDiff() {
            let red = Rgba(red: 1, green: 0, blue: 0)
            let moved = frame.offsetBy(dx: 5, dy: 0)
            assertEquals(BordersDiff.ops(from: [], to: []), [])
            assertEquals(BordersDiff.ops(from: [], to: [item(1), item(2)]), [.add(item(1)), .add(item(2))])
            assertEquals(BordersDiff.ops(from: [item(1), item(2)], to: []), [.remove(windowId: 1), .remove(windowId: 2)])
            // Nothing changed: nothing to do, whatever the order
            assertEquals(BordersDiff.ops(from: [item(1), item(2)], to: [item(1), item(2)]), [])
            assertEquals(BordersDiff.ops(from: [item(1), item(2)], to: [item(2), item(1)]), [])
            // A focus change is two recolors, and nothing else
            assertEquals(
                BordersDiff.ops(from: [item(1, nil, red), item(2)], to: [item(1), item(2, nil, red)]),
                [.recolor(windowId: 1, .white), .recolor(windowId: 2, red)],
            )
            // A move doesn't touch the color
            assertEquals(BordersDiff.ops(from: [item(1), item(2)], to: [item(1, moved), item(2)]), [.reshape(item(1, moved))])
            // The width and the radius rebuild the shape
            assertEquals(BordersDiff.ops(from: [item(1)], to: [item(1, width: 6)]), [.reshape(item(1, width: 6))])
            assertEquals(BordersDiff.ops(from: [item(1)], to: [item(1, radius: 0)]), [.reshape(item(1, radius: 0))])
            // Everything at once: removals first
            assertEquals(
                BordersDiff.ops(from: [item(1), item(2), item(3)], to: [item(4), item(2, moved, red), item(1)]),
                [.remove(windowId: 3), .add(item(4)), .reshape(item(2, moved, red)), .recolor(windowId: 2, red)],
            )
        }

        // MARK: - Stacking

        @Test func testStacking() {
            typealias Panel = BorderStacking.Panel
            // Front to back. 900 and 901 are the panels of the windows 10 and 20
            let glued = [50, 900, 10, 60, 901, 20]
            let panels = [Panel(windowId: 10, panelNumber: 900, isVisible: true), Panel(windowId: 20, panelNumber: 901, isVisible: true)]
            assertEquals(BorderStacking.plan(order: glued, panels: panels), [])
            // The window 20 was raised: its panel stayed behind
            assertEquals(BorderStacking.plan(order: [20, 50, 900, 10, 60, 901], panels: panels), [.orderAbove(windowId: 20)])
            // Another window got between the panel and its window
            assertEquals(BorderStacking.plan(order: [900, 50, 10, 901, 20], panels: panels), [.orderAbove(windowId: 10)])
            // The panel is below its window
            assertEquals(BorderStacking.plan(order: [10, 900, 901, 20], panels: panels), [.orderAbove(windowId: 10)])
            // The window isn't on the screen: another Space, minimized, closed
            assertEquals(BorderStacking.plan(order: [50, 900, 901, 20], panels: panels), [.hide(windowId: 10)])
            // A new panel isn't on the screen yet
            let new = [Panel(windowId: 10, panelNumber: 900, isVisible: false), Panel(windowId: 30, panelNumber: 902, isVisible: false)]
            assertEquals(BorderStacking.plan(order: [50, 10], panels: new), [.orderAbove(windowId: 10)])
            assertEquals(BorderStacking.plan(order: [], panels: new), [])
        }

        // MARK: - Correction

        @Test func testCorrection() {
            let other = CGRect(x: 400, y: 20, width: 300, height: 200)
            let items = [item(1), item(2, other), item(3)]
            // The window 1 refused to shrink, the window 2 is where it was asked to be (within a point), the window 3 is unknown
            let real: [UInt32: CGRect] = [
                1: CGRect(x: 10, y: 20, width: 480, height: 200),
                2: other.offsetBy(dx: 0.5, dy: -0.5),
            ]
            assertEquals(
                BorderCorrection.corrected(items, actual: real),
                [item(1, CGRect(x: 10, y: 20, width: 480, height: 200)), item(2, other), item(3)],
            )
            assertEquals(BorderCorrection.corrected(items, actual: [:]), items)
            // Garbage from the window server is ignored
            assertEquals(BorderCorrection.corrected(items, actual: [1: .zero]), items)
        }

        // MARK: - Geometry

        @Test func testGeometry() {
            let geometry = BorderGeometry(frame: frame, width: 4, cornerRadius: 16, scale: 2)
            // The border is outside of the frame of the window: the panel is bigger by the width on every side
            assertEquals(geometry.panelFrame, CGRect(x: 6, y: 16, width: 308, height: 208))
            assertEquals(geometry.outerRect, CGRect(x: 0, y: 0, width: 308, height: 208))
            // The hole is exactly the window
            assertEquals(geometry.innerRect, CGRect(x: 4, y: 4, width: 300, height: 200))
            assertEquals(geometry.innerRadius, 16)
            assertEquals(geometry.outerRadius, 20)
            // AppKit: Y grows upwards from the bottom of the main screen
            assertEquals(geometry.appKitFrame(mainScreenHeight: 1000), CGRect(x: 6, y: 1000 - 16 - 208, width: 308, height: 208))

            let path = geometry.path()
            assertEquals(path.boundingBoxOfPath, geometry.outerRect)
            func isPainted(_ x: CGFloat, _ y: CGFloat) -> Bool { path.contains(CGPoint(x: x, y: y), using: .evenOdd) }
            assertTrue(isPainted(2, 104)) // The left side of the ring
            assertTrue(isPainted(154, 206)) // The bottom side
            assertTrue(isPainted(3.9, 104))
            assertFalse(isPainted(4.1, 104)) // The window starts here
            assertFalse(isPainted(154, 104)) // The middle of the window
            assertFalse(isPainted(0.5, 0.5)) // Outside of the rounded outer corner
            assertFalse(isPainted(5, 5))
            assertTrue(isPainted(8, 8)) // Between the two rounded corners
            assertFalse(isPainted(10, 10)) // Inside of the rounded corner of the window
        }

        @Test func testGeometrySnapsToPixels() {
            let fractional = CGRect(x: 10.3, y: 20.6, width: 300.4, height: 199.7)
            // @2x: half points are pixels
            assertEquals(BorderGeometry(frame: fractional, width: 4, cornerRadius: 16, scale: 2).panelFrame, CGRect(x: 6.5, y: 16.5, width: 308, height: 208))
            // @1x: whole points only
            assertEquals(BorderGeometry(frame: fractional, width: 4, cornerRadius: 16, scale: 1).panelFrame, CGRect(x: 6, y: 17, width: 309, height: 207))
            // The width never rounds down to nothing
            assertEquals(BorderGeometry(frame: frame, width: 0.2, cornerRadius: 0, scale: 2).width, 0.5)
            assertEquals(BorderGeometry(frame: frame, width: 1, cornerRadius: 0, scale: 1).width, 1)
        }

        @Test func testGeometryLimits() {
            // The radius can't be bigger than half of the window
            let small = BorderGeometry(frame: CGRect(x: 0, y: 0, width: 20, height: 60), width: 4, cornerRadius: 40, scale: 2)
            assertEquals(small.innerRadius, 10)
            assertEquals(small.outerRadius, 14)
            // No radius: square corners inside and outside
            let square = BorderGeometry(frame: frame, width: 4, cornerRadius: 0, scale: 2)
            assertEquals(square.innerRadius, 0)
            assertEquals(square.outerRadius, 0)
            assertTrue(square.path().contains(CGPoint(x: 0.5, y: 0.5), using: .evenOdd))
        }

        @Test func testScreenScale() {
            let retina = BorderScreen(frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2)
            let external = BorderScreen(frame: CGRect(x: 1800, y: 0, width: 1920, height: 1080), scale: 1)
            assertEquals(BorderScreen.scale(for: frame, in: [retina, external]), 2)
            assertEquals(BorderScreen.scale(for: frame.offsetBy(dx: 2000, dy: 0), in: [retina, external]), 1)
            // A window across two screens: the one with the biggest part of it
            assertEquals(BorderScreen.scale(for: CGRect(x: 1700, y: 0, width: 300, height: 200), in: [retina, external]), 1)
            assertEquals(BorderScreen.scale(for: CGRect(x: 1600, y: 0, width: 300, height: 200), in: [retina, external]), 2)
            // Off every screen, and no screens at all
            assertEquals(BorderScreen.scale(for: frame.offsetBy(dx: -5000, dy: 0), in: [retina, external]), 2)
            assertEquals(BorderScreen.scale(for: frame, in: []), 2)
        }
    }
}

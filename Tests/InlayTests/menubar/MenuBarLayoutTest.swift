@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    @Suite final class MenuBarLayoutTest {
        /// Every character is 7 pt wide, so the expected frames are easy to tell
        private static func measure(_ string: String, _ font: MenuBarFont) -> CGSize {
            switch font {
                case .chipName: CGSize(width: 7 * CGFloat(string.count), height: 15)
                case .squareName: CGSize(width: 8 * CGFloat(string.count), height: 16)
                case .modeInitial: CGSize(width: 8, height: 12)
                case .chipModeInitial: CGSize(width: 9, height: 13)
            }
        }

        /// 1, 2 (the focus) and 3 have windows, 4 is empty
        private var snapshot = MenuBarSnapshot(
            workspaces: [
                .init(name: "1", isOccupied: true),
                .init(name: "2", isOccupied: true),
                .init(name: "3", isOccupied: true),
                .init(name: "4", isOccupied: false),
            ],
            focusedWorkspace: "2",
        )

        private func layout(_ config: MenuBarConfig = MenuBarConfig(), _ snapshot: MenuBarSnapshot? = nil, transition: MenuBarFocusTransition? = nil) -> MenuBarLayout {
            MenuBarLayout.make(snapshot ?? self.snapshot, config, transition: transition, measure: Self.measure)
        }

        // MARK: - Chips

        @Test func testChips() {
            let layout = layout()
            assertEquals(layout.style, .chips)
            // 4 chips of 17 pt, 2.5 pt apart, in an item of 22 pt
            assertEquals(layout.size, CGSize(width: 4 * 17 + 3 * 2.5, height: 22))
            assertEquals(layout.cells.map(\.workspace), ["1", "2", "3", "4"])
            assertEquals(layout.cells.map(\.frame), [
                CGRect(x: 0, y: 2.5, width: 17, height: 17),
                CGRect(x: 19.5, y: 2.5, width: 17, height: 17),
                CGRect(x: 39, y: 2.5, width: 17, height: 17),
                CGRect(x: 58.5, y: 2.5, width: 17, height: 17),
            ])
            // The name in the middle of the chip
            assertEquals(layout.cells[0].name, .init(string: "1", font: .chipName, frame: CGRect(x: 5, y: 3.5, width: 7, height: 15)))
            assertEquals(layout.cells.map(\.isOccupied), [true, true, true, false])
            assertEquals(layout.cells.map(\.isDimmed), [false, false, false, true])
            assertEquals(layout.cells.map(\.focus), [0, 1, 0, 0])
            assertEquals(layout.marker, .init(frame: CGRect(x: 19.5, y: 2.5, width: 17, height: 17), cornerRadius: 4.5, isOutlined: false))
            assertEquals(layout.layoutIcon, nil)
            assertEquals(layout.placeholder, nil)
            assertEquals(layout.needsColor, false)
        }

        @Test func testChipsWithTheRealFont() {
            let layout = MenuBarLayout.make(MenuBarSamples.snapshot, MenuBarConfig(), measure: MenuBarFont.size)
            // The size of the Chips style of Aeromenu with six workspaces
            assertEquals(layout.size, CGSize(width: 114.5, height: 22))
            assertEquals(layout.cells.map(\.frame.width), [17, 17, 17, 17, 17, 17])
        }

        @Test func testLongNamesGrowTheChip() {
            snapshot.workspaces[2].name = "web"
            let layout = layout()
            // 3 pt of padding on each side
            assertEquals(layout.cells[2].frame, CGRect(x: 39, y: 2.5, width: 27, height: 17))
            assertEquals(layout.cells[2].name.frame, CGRect(x: 42, y: 3.5, width: 21, height: 15))
            assertEquals(layout.cells[3].frame.minX, 68.5)
            assertEquals(layout.size.width, 85.5)
        }

        @Test func testDimEmptyWorkspaces() {
            assertEquals(layout(MenuBarConfig(dimEmptyWorkspaces: false)).cells.map(\.isDimmed), [false, false, false, false])
        }

        @Test func testFullscreen() {
            snapshot.isFocusedWorkspaceFullscreen = true
            assertEquals(layout().marker?.isOutlined, true)
            assertEquals(layout(MenuBarConfig(theme: .square)).marker?.isOutlined, true)
        }

        /// 'show-mode': the initial of the binding mode in the chip of the focused workspace, like the Chips style
        /// of Aeromenu did. Nothing is added next to the chips
        @Test func testModeInTheFocusedChip() {
            let main = layout(MenuBarConfig(showMode: true))
            assertEquals(main.marker?.initial, nil)
            snapshot.mode = "resize"
            // Off with show-mode = false
            assertEquals(layout(MenuBarConfig(showMode: false)).marker?.initial, nil)
            assertEquals(layout(MenuBarConfig(showMode: false)).needsColor, false)
            let layout = layout(MenuBarConfig(showMode: true))
            // The same chip, with the initial in the middle of it
            assertEquals(layout.marker, .init(
                frame: CGRect(x: 19.5, y: 2.5, width: 17, height: 17),
                cornerRadius: 4.5,
                isOutlined: false,
                initial: .init(string: "R", font: .chipModeInitial, frame: CGRect(x: 23.5, y: 4.5, width: 9, height: 13)),
            ))
            assertEquals(layout.needsColor, true)
            // The item is as wide as in the main mode, and nothing moves
            assertEquals(layout.size, main.size)
            assertEquals(layout.cells, main.cells)
            assertEquals(MenuBarLayout.modeInitial("service"), "S")
            assertEquals(MenuBarLayout.modeInitial("ñu"), "Ñ")
            assertEquals(MenuBarLayout.modeInitial(""), "?")
        }

        @Test func testModeInAWideChip() {
            snapshot.workspaces[1].name = "web"
            snapshot.focusedWorkspace = "web"
            snapshot.mode = "service"
            let layout = layout(MenuBarConfig(showMode: true))
            // 3 characters of 7 pt and 3 pt on each side. The initial is in the middle of the chip
            assertEquals(layout.marker?.frame, CGRect(x: 19.5, y: 2.5, width: 27, height: 17))
            assertEquals(layout.marker?.initial?.frame.midX, 33)
            snapshot.mode = "main"
            assertEquals(self.layout(MenuBarConfig(showMode: true)).size, layout.size)
        }

        @Test func testModeAndFullscreen() {
            snapshot.mode = "resize"
            snapshot.isFocusedWorkspaceFullscreen = true
            for theme in MenuBarTheme.allCases {
                let marker = layout(MenuBarConfig(theme: theme, showMode: true)).marker
                assertEquals(marker?.isOutlined, true, additionalMsg: theme.rawValue)
                assertEquals(marker?.initial?.string, "R", additionalMsg: theme.rawValue)
            }
        }

        /// The initial goes with the marker while it slides to the focused workspace
        @Test func testModeWhileTheMarkerSlides() {
            snapshot.mode = "resize"
            let middle = layout(MenuBarConfig(showMode: true), transition: .init(from: "4", progress: 0.5))
            assertEquals(middle.marker?.frame, CGRect(x: 39, y: 2.5, width: 17, height: 17))
            assertEquals(middle.marker?.initial?.frame, CGRect(x: 43, y: 4.5, width: 9, height: 13))
        }

        // MARK: - Minimal

        @Test func testMinimal() {
            let layout = layout(MenuBarConfig(theme: .minimal))
            // Only the focused workspace
            assertEquals(layout.cells.map(\.workspace), ["2"])
            assertEquals(layout.size, CGSize(width: 17, height: 22))
            assertEquals(layout.marker?.frame, CGRect(x: 0, y: 2.5, width: 17, height: 17))
            // The mode is in that chip, which stays as it is
            snapshot.mode = "resize"
            let mode = self.layout(MenuBarConfig(theme: .minimal, showMode: true))
            assertEquals(mode.size, layout.size)
            assertEquals(mode.marker?.frame, layout.marker?.frame)
            assertEquals(mode.marker?.initial, .init(string: "R", font: .chipModeInitial, frame: CGRect(x: 4, y: 4.5, width: 9, height: 13)))
        }

        // MARK: - Square

        @Test func testSquare() {
            let layout = layout(MenuBarConfig(theme: .square))
            assertEquals(layout.style, .square)
            assertEquals(layout.layoutIcon, .init(frame: CGRect(x: 0, y: 0, width: 16, height: 22), orientation: .h))
            // Slots of 15 pt after the icon, 17 pt for the focused one
            assertEquals(layout.cells.map(\.frame), [
                CGRect(x: 26, y: 0, width: 15, height: 22),
                CGRect(x: 41, y: 0, width: 17, height: 22),
                CGRect(x: 58, y: 0, width: 15, height: 22),
                CGRect(x: 73, y: 0, width: 15, height: 22),
            ])
            assertEquals(layout.size, CGSize(width: 88, height: 22))
            assertEquals(layout.cells[0].name.frame, CGRect(x: 29.5, y: 3, width: 8, height: 16))
            // A square of 8.5 pt in the place of the focused workspace
            assertEquals(layout.marker, .init(frame: CGRect(x: 45.25, y: 6.75, width: 8.5, height: 8.5), cornerRadius: 2, isOutlined: false))
            assertEquals(layout.needsColor, false)

            snapshot.orientation = .v
            assertEquals(self.layout(MenuBarConfig(theme: .square)).layoutIcon?.orientation, .v)
        }

        @Test func testSquareMode() {
            snapshot.mode = "resize"
            // Without 'show-mode' the square is the one of the main mode
            let main = layout(MenuBarConfig(theme: .square, showMode: false))
            assertEquals(main.marker, .init(frame: CGRect(x: 45.25, y: 6.75, width: 8.5, height: 8.5), cornerRadius: 2, isOutlined: false))
            // With it, the square grows to 14 pt and carries the initial, like the Square style of Aeromenu
            let layout = layout(MenuBarConfig(theme: .square, showMode: true))
            assertEquals(layout.marker, .init(
                frame: CGRect(x: 42.5, y: 4, width: 14, height: 14),
                cornerRadius: 3.5,
                isOutlined: false,
                initial: .init(string: "R", font: .modeInitial, frame: CGRect(x: 45.5, y: 5, width: 8, height: 12)),
            ))
            assertEquals(layout.needsColor, true)
            // Nothing shifts when the mode changes: the slot of the focused workspace is always wide enough
            assertEquals(layout.cells, main.cells)
            assertEquals(layout.size, main.size)
        }

        // MARK: - Slide

        @Test func testSlideOfTheChipsMarker() {
            // From 4 to 2
            let start = layout(transition: .init(from: "4", progress: 0))
            assertEquals(start.marker?.frame, CGRect(x: 58.5, y: 2.5, width: 17, height: 17))
            assertEquals(start.cells.map(\.focus), [0, 0, 0, 1])
            let middle = layout(transition: .init(from: "4", progress: 0.5))
            assertEquals(middle.marker?.frame, CGRect(x: 39, y: 2.5, width: 17, height: 17))
            assertEquals(middle.cells.map(\.focus), [0, 0.5, 0, 0.5])
            // The chips don't move while the marker slides
            assertEquals(middle.cells.map(\.frame), layout().cells.map(\.frame))
            assertEquals(layout(transition: .init(from: "4", progress: 1)), layout())
            assertEquals(layout(transition: .init(from: "4", progress: 7)), layout())
            assertEquals(layout(transition: .init(from: "4", progress: -1)), start)
            // The workspace the marker comes from is gone
            assertEquals(layout(transition: .init(from: "9", progress: 0.3)), layout())
        }

        @Test func testSlideBetweenChipsOfDifferentWidths() {
            snapshot.workspaces[3].name = "web"
            let middle = layout(transition: .init(from: "web", progress: 0.5))
            // The width and the center go from one chip to the other
            assertEquals(middle.marker?.frame, CGRect(x: 39, y: 2.5, width: 22, height: 17))
        }

        @Test func testSlideOfTheSquare() {
            let middle = layout(MenuBarConfig(theme: .square), transition: .init(from: "4", progress: 0.5))
            // Both slots are half way between 15 and 17 pt
            assertEquals(middle.cells.map(\.frame.width), [15, 16, 15, 16])
            assertEquals(middle.cells.map(\.focus), [0, 0.5, 0, 0.5])
            assertEquals(middle.marker?.frame.midX, (49 + 80) / 2)
            assertEquals(middle.size.width, 88)
        }

        // MARK: - Placeholders

        @Test func testPlaceholders() {
            snapshot.status = .paused
            let paused = layout(MenuBarConfig(theme: .square, showMode: true))
            assertEquals(paused.cells, [])
            assertEquals(paused.marker, nil)
            assertEquals(paused.layoutIcon, nil)
            assertEquals(paused.placeholder?.symbolName, "pause.fill")
            assertEquals(paused.placeholder?.glyphOpacity, 1)
            // The size of the item of Aeromenu while AeroSpace is disabled
            assertEquals(paused.size, CGSize(width: 33.5, height: 22))

            snapshot.status = .needsAccessibility
            let needsAccessibility = layout()
            assertEquals(needsAccessibility.placeholder?.symbolName, "exclamationmark.triangle.fill")
            assertEquals(needsAccessibility.placeholder?.glyphOpacity, 0.5)
        }

        // MARK: - Pressing the item

        /// The item only informs: the left button does nothing, wherever it clicks
        @Test func testOnlyTheRightButtonAndCtrlClickOpenTheMenu() {
            func opensMenu(_ type: NSEvent.EventType?, control: Bool = false, age: TimeInterval? = 0.01) -> Bool {
                MenuBarController.opensMenu(eventType: type, isControlPressed: control, eventAge: age)
            }
            assertEquals(opensMenu(.leftMouseUp), false)
            assertEquals(opensMenu(.leftMouseDown), false)
            assertEquals(opensMenu(.rightMouseUp), true)
            assertEquals(opensMenu(.rightMouseDown), true)
            assertEquals(opensMenu(.leftMouseUp, control: true), true)
            assertEquals(opensMenu(.rightMouseUp, control: true), true)
            // Pressed through the accessibility API (VoiceOver): there is no event, or the current one is an old one
            assertEquals(opensMenu(nil, age: nil), true)
            assertEquals(opensMenu(.leftMouseUp, age: 30), true)
            assertEquals(opensMenu(.keyDown), true)
        }
    }

    @Suite struct MenuBarPaletteTest {
        private let accent = Rgba(red: 1, green: 0.5, blue: 0)

        private func palette(_ config: MenuBarConfig = MenuBarConfig(), style: MenuBarLayout.Style = .chips, dark: Bool = true, needsColor: Bool = false) -> MenuBarPalette {
            MenuBarPalette.resolve(config, style: style, isDarkBar: dark, systemAccent: accent, needsColor: needsColor)
        }

        @Test func testDefaultIsATemplate() {
            // One color, like Aeromenu: macOS picks black or white for the menu bar
            for dark in [true, false] {
                let palette = palette(dark: dark)
                assertEquals(palette.isTemplate, true)
                assertEquals(palette.base, .black)
                assertEquals(palette.focused, .black)
                assertEquals(palette.focusedName, nil)
                assertEquals(palette.occupiedName, Rgba.black.withAlpha(0.72))
                assertEquals(palette.occupiedBackground, Rgba.black.withAlpha(0.14))
                assertEquals(palette.emptyName, Rgba.black.withAlpha(0.35))
                // The marker of a binding mode is the one of the focused workspace
                assertEquals(palette.modeMarker, .black)
                assertEquals(palette.modeInitial, nil)
            }
            assertEquals(palette(MenuBarConfig(dimEmptyWorkspaces: false)).emptyName, Rgba.black.withAlpha(0.72))
        }

        /// The binding mode in the marker doesn't take the item out of the template, like in Aeromenu.
        /// Only a color in 'accent' does, and only while a mode is shown
        @Test func testTheMarkerOfAModeIsATemplateUnlessAccentHasAColor() {
            for dark in [true, false] {
                let palette = palette(dark: dark, needsColor: true)
                assertEquals(palette.isTemplate, true)
                assertEquals(palette.modeMarker, .black)
                assertEquals(palette.modeInitial, nil)
            }
            let white = MenuBarConfig(colors: MenuBarColors(accent: .rgba(.white)))
            assertEquals(palette(white).isTemplate, true)
            assertEquals(palette(white, needsColor: true).isTemplate, false)
        }

        @Test func testSquareNamesAreNotFaded() {
            let palette = palette(style: .square)
            assertEquals(palette.isTemplate, true)
            assertEquals(palette.occupiedName, .black)
            assertEquals(palette.emptyName, Rgba.black.withAlpha(0.35))
        }

        @Test func testAccentColorsTheMarkerOfAMode() {
            // The rest has the same look, but with the color of the menu bar text baked in
            let config = MenuBarConfig(colors: MenuBarColors(accent: .systemAccent))
            let dark = palette(config, dark: true, needsColor: true)
            assertEquals(dark.isTemplate, false)
            assertEquals(dark.base, .white)
            assertEquals(dark.focused, .white)
            assertEquals(dark.focusedName, nil)
            assertEquals(dark.occupiedName, Rgba.white.withAlpha(0.72))
            assertEquals(dark.occupiedBackground, Rgba.white.withAlpha(0.14))
            assertEquals(dark.emptyName, Rgba.white.withAlpha(0.35))
            assertEquals(dark.modeMarker, accent)
            // White over the accent color, like the system does
            assertEquals(dark.modeInitial, .white)
            let light = palette(config, dark: false, needsColor: true)
            assertEquals(light.isTemplate, false)
            assertEquals(light.base, .black)
            assertEquals(light.occupiedName, Rgba.black.withAlpha(0.72))
            assertEquals(light.modeMarker, accent)
            // Black over a light color
            let yellow = Rgba(hex: "#FFE66D").orDie()
            assertEquals(palette(MenuBarConfig(colors: MenuBarColors(accent: .rgba(yellow))), needsColor: true).modeInitial, .black)
        }

        /// 'accent' is 'auto': the marker of a mode has the fixed color of 'focused', and the initial contrasts with it
        @Test func testTheMarkerOfAModeFollowsFocused() {
            let navy = Rgba(hex: "#1E3A8A").orDie()
            for dark in [true, false] {
                let palette = palette(MenuBarConfig(colors: MenuBarColors(focused: .rgba(navy))), dark: dark, needsColor: true)
                assertEquals(palette.modeMarker, navy)
                assertEquals(palette.modeInitial, .white)
            }
        }

        @Test func testFixedColors() {
            let orange = Rgba(hex: "#D19A66").orDie()
            let gray = Rgba(hex: "#ABB2BF").orDie()
            let translucent = Rgba(hex: "#CDD6F466").orDie()
            let config = MenuBarConfig(colors: MenuBarColors(accent: .rgba(.white), focused: .rgba(orange), occupied: .rgba(gray), empty: .rgba(translucent)))
            for dark in [true, false] {
                // A fixed color doesn't adapt to the menu bar
                let palette = palette(config, dark: dark)
                assertEquals(palette.isTemplate, false)
                assertEquals(palette.base, dark ? .white : .black)
                assertEquals(palette.focused, orange)
                // Black or white, the one with more contrast
                assertEquals(palette.focusedName, .black)
                assertEquals(palette.occupiedName, gray)
                assertEquals(palette.occupiedBackground, gray.withAlpha(0.16))
                assertEquals(palette.emptyName, translucent)
                assertEquals(palette.modeMarker, .white)
                assertEquals(palette.modeInitial, .black)
            }
            // Without dimming, the empty workspaces look like the names of the occupied ones
            var noDim = config
            noDim.dimEmptyWorkspaces = false
            assertEquals(palette(noDim).emptyName, gray)
        }

        @Test func testOneFixedColorIsEnoughToLeaveTheTemplate() {
            let navy = Rgba(hex: "#1E3A8A").orDie()
            let focused = palette(MenuBarConfig(colors: MenuBarColors(focused: .rgba(navy))))
            assertEquals(focused.isTemplate, false)
            assertEquals(focused.focusedName, .white)
            // The colors that stay 'auto' follow the menu bar
            assertEquals(focused.occupiedName, Rgba.white.withAlpha(0.72))
            assertEquals(palette(MenuBarConfig(colors: MenuBarColors(focused: .rgba(navy))), dark: false).occupiedName, Rgba.black.withAlpha(0.72))
            assertEquals(palette(MenuBarConfig(colors: MenuBarColors(occupied: .rgba(navy)))).isTemplate, false)
            assertEquals(palette(MenuBarConfig(colors: MenuBarColors(empty: .rgba(navy)))).isTemplate, false)

            let systemAccent = palette(MenuBarConfig(colors: MenuBarColors(focused: .systemAccent)))
            assertEquals(systemAccent.isTemplate, false)
            assertEquals(systemAccent.focused, accent)
        }
    }

    @Suite @MainActor struct MenuBarRendererTest {
        private func alpha(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Int {
            Int(((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded())
        }

        @Test func testTemplateImage() throws {
            let layout = MenuBarLayout.make(MenuBarSamples.snapshot, MenuBarConfig(), measure: MenuBarFont.size)
            let palette = MenuBarPalette.resolve(MenuBarConfig(), style: .chips, isDarkBar: true, systemAccent: .white)
            let image = try #require(MenuBarRenderer.image(layout, palette, scale: 2))
            assertEquals(image.isTemplate, true)
            assertEquals(image.size, CGSize(width: 114.5, height: 22))
            let bitmap = try #require(MenuBarRenderer.bitmap(layout, palette, scale: 2))
            assertEquals(bitmap.pixelsWide, 229)
            assertEquals(bitmap.pixelsHigh, 44)
            // Above the chips: nothing
            assertEquals(alpha(bitmap, 16, 2), 0)
            // The corner of the first chip (occupied): its faint background, 14%
            assertEquals(alpha(bitmap, 4, 20), 36)
            // The corner of the second chip (focused): solid
            assertEquals(alpha(bitmap, 43, 20), 255)
            // The gap between two chips
            assertEquals(alpha(bitmap, 36, 20), 0)
            // The last chip (empty) has no background
            assertEquals(alpha(bitmap, 199, 20), 0)
            // The name of the focused workspace is cut out of its chip: some pixel in the middle of it is clear
            assertEquals((44 ..< 68).contains { alpha(bitmap, $0, 22) == 0 }, true)
        }

        @Test func testColorImage() throws {
            let config = MenuBarConfig(colors: MenuBarColors(focused: .rgba(Rgba(red: 1, green: 0, blue: 0))))
            let layout = MenuBarLayout.make(MenuBarSamples.snapshot, config, measure: MenuBarFont.size)
            let palette = MenuBarPalette.resolve(config, style: .chips, isDarkBar: true, systemAccent: .white)
            assertEquals(try #require(MenuBarRenderer.image(layout, palette, scale: 2)).isTemplate, false)
            let bitmap = try #require(MenuBarRenderer.bitmap(layout, palette, scale: 2))
            let focused = try #require(bitmap.colorAt(x: 43, y: 20))
            assertEquals([focused.redComponent, focused.greenComponent, focused.blueComponent, focused.alphaComponent], [1, 0, 0, 1])
            // The name isn't cut out: every pixel of the chip is opaque
            assertEquals((44 ..< 68).allSatisfy { alpha(bitmap, $0, 22) == 255 }, true)
        }

        /// The initial of the binding mode is cut out of the chip of the focused workspace, where its name was
        @Test func testModeInTheChip() throws {
            var snapshot = MenuBarSamples.snapshot
            snapshot.mode = "resize"
            let config = MenuBarConfig(showMode: true)
            let layout = MenuBarLayout.make(snapshot, config, measure: MenuBarFont.size)
            let palette = MenuBarPalette.resolve(config, style: .chips, isDarkBar: true, systemAccent: .white, needsColor: layout.needsColor)
            assertEquals(try #require(MenuBarRenderer.image(layout, palette, scale: 2)).isTemplate, true)
            let main = try #require(MenuBarRenderer.bitmap(MenuBarLayout.make(MenuBarSamples.snapshot, config, measure: MenuBarFont.size), palette, scale: 2))
            let bitmap = try #require(MenuBarRenderer.bitmap(layout, palette, scale: 2))
            assertEquals([bitmap.pixelsWide, bitmap.pixelsHigh], [main.pixelsWide, main.pixelsHigh])
            // The chip is still solid, and something is cut out of it
            assertEquals(alpha(bitmap, 43, 20), 255)
            let cutOut = { (bitmap: NSBitmapImageRep) in (40 ..< 72).flatMap { x in (6 ..< 38).map { y in self.alpha(bitmap, x, y) == 0 } } }
            assertEquals(cutOut(bitmap).contains(true), true)
            // And it isn't the name of the workspace: an 'R', not a '2'
            assertEquals(cutOut(bitmap) != cutOut(main), true)
            // The other chips are the ones of the main mode
            for x in Array(stride(from: 0, to: 38, by: 3)) + Array(stride(from: 76, to: bitmap.pixelsWide, by: 3)) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
                    assertEquals(alpha(bitmap, x, y), alpha(main, x, y), additionalMsg: "\(x),\(y)")
                }
            }
            // With a color in 'accent', the chip has that color and the initial is white over it
            let accent = MenuBarConfig(showMode: true, colors: MenuBarColors(accent: .rgba(Rgba(red: 1, green: 0, blue: 0))))
            let colored = MenuBarPalette.resolve(accent, style: .chips, isDarkBar: true, systemAccent: .white, needsColor: true)
            let coloredBitmap = try #require(MenuBarRenderer.bitmap(layout, colored, scale: 2))
            let color = try #require(coloredBitmap.colorAt(x: 43, y: 20))
            assertEquals([color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent], [1, 0, 0, 1])
        }

        @Test func testRenderSamples() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "inlay-render-\(UUID().uuidString)")
            defer { _ = try? FileManager.default.removeItem(at: directory) }
            try renderMenuBarSamples(to: directory)
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            // Every theme, in a dark and in a light menu bar, with the default and with custom colors
            for theme in MenuBarTheme.allCases {
                for variant in ["default", "custom"] {
                    for bar in ["dark", "light"] {
                        let name = "\(theme.rawValue)-\(variant)-\(bar).png"
                        assertEquals(files.contains(name), true, additionalMsg: name)
                        assertEquals(try #require(NSImage(contentsOf: directory.appending(path: name))).size.height, 24, additionalMsg: name)
                    }
                }
            }
            // Only what is one color is a template: no fixed colors. A binding mode in the marker is still one color
            assertEquals(files.filter { $0.hasSuffix("-template.png") }.sorted(), [
                "chips-default-template.png", "chips-fullscreen-template.png", "chips-mode-fullscreen-template.png",
                "chips-mode-template.png", "chips-no-dim-template.png",
                "minimal-default-template.png", "minimal-fullscreen-template.png", "minimal-mode-fullscreen-template.png",
                "minimal-mode-template.png",
                "needs-accessibility-template.png", "paused-template.png",
                "square-default-template.png", "square-fullscreen-template.png", "square-mode-fullscreen-template.png",
                "square-mode-template.png",
            ])
            // The item is as wide in a binding mode as in the main mode, in every theme
            for theme in MenuBarTheme.allCases {
                let main = try #require(NSImage(contentsOf: directory.appending(path: "\(theme.rawValue)-default-dark.png")))
                for variant in ["mode", "mode-accent", "mode-custom", "mode-fullscreen"] {
                    let mode = try #require(NSImage(contentsOf: directory.appending(path: "\(theme.rawValue)-\(variant)-dark.png")))
                    assertEquals(mode.size, main.size, additionalMsg: "\(theme.rawValue)-\(variant)")
                }
            }
        }
    }
}

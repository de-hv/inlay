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
                case .dmsName: CGSize(width: 6 * CGFloat(string.count), height: 12)
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

        private func layout(_ config: MenuBarConfig = MenuBarConfig(theme: .chips), _ snapshot: MenuBarSnapshot? = nil, transition: MenuBarFocusTransition? = nil) -> MenuBarLayout {
            MenuBarLayout.make(snapshot ?? self.snapshot, config, transition: transition, measure: Self.measure)
        }

        // MARK: - Pills

        @Test func testPills() {
            let layout = layout(MenuBarConfig(theme: .pills))
            assertEquals(layout.style, .chips)
            // Round: the radius is half of the height
            assertEquals(layout.cornerRadius, MenuBarMetrics.chipSide / 2)
            // The focused workspace is a wider pill, the others are round
            let widths = layout.cells.map(\.frame.width)
            let focused = try! #require(layout.cells.firstIndex { $0.workspace == snapshot.focusedWorkspace })
            assertEquals(widths[focused], MenuBarMetrics.pillFocusedWidth)
            for (index, width) in widths.enumerated() where index != focused {
                assertEquals(width, MenuBarMetrics.chipSide)
            }
            // The marker is the focused pill
            assertEquals(layout.marker?.frame, layout.cells[focused].frame)
            assertEquals(layout.marker?.cornerRadius, MenuBarMetrics.chipSide / 2)
            // Side by side, with the spacing of the pills
            for (a, b) in zip(layout.cells, layout.cells.dropFirst()) {
                assertEquals(b.frame.minX - a.frame.maxX, MenuBarMetrics.pillSpacing)
            }
        }

        /// While the marker slides, the pill it leaves shrinks and the one it goes to grows: the item keeps its width
        @Test func testPillsStretchWhileTheMarkerSlides() {
            let end = layout(MenuBarConfig(theme: .pills))
            let middle = layout(MenuBarConfig(theme: .pills), transition: .init(from: "4", progress: 0.5))
            let from = try! #require(middle.cells.first { $0.workspace == "4" })
            let to = try! #require(middle.cells.first { $0.workspace == snapshot.focusedWorkspace })
            let half = (MenuBarMetrics.chipSide + MenuBarMetrics.pillFocusedWidth) / 2
            assertEquals(from.frame.width, half)
            assertEquals(to.frame.width, half)
            assertEquals(middle.size.width, end.size.width)
        }

        // MARK: - Dots

        @Test func testDots() {
            typealias M = MenuBarMetrics
            let layout = layout(MenuBarConfig(theme: .dots))
            assertEquals(layout.style, .dots)
            // A dot per workspace, the focused one a pill, side by side
            assertEquals(layout.cells.map(\.frame.width), [M.dotSide, M.dotFocusedWidth, M.dotSide, M.dotSide])
            assertEquals(layout.size, CGSize(width: 3 * M.dotSide + M.dotFocusedWidth + 3 * M.dotSpacing, height: M.height))
            for cell in layout.cells {
                assertEquals(cell.frame.height, M.dotSide)
                assertEquals(cell.frame.midY, M.height / 2)
            }
            assertEquals(layout.marker?.frame, layout.cells[1].frame)
            assertEquals(layout.marker?.cornerRadius, M.dotSide / 2)
            assertNil(layout.marker?.initial)
        }

        /// In a binding mode the pill grows taller to hold the initial, and the item keeps its width
        @Test func testDotsInABindingMode() throws {
            typealias M = MenuBarMetrics
            var snapshot = snapshot
            snapshot.mode = "resize"
            let main = layout(MenuBarConfig(theme: .dots, showMode: true))
            let mode = layout(MenuBarConfig(theme: .dots, showMode: true), snapshot)
            let marker = try #require(mode.marker)
            assertEquals(marker.frame.size, CGSize(width: M.dotFocusedWidth, height: M.modeSquare))
            assertEquals(marker.frame.midY, M.height / 2)
            assertEquals(marker.initial?.string, "R")
            assertEquals(mode.size, main.size)
        }

        // MARK: - Dms

        @Test func testDms() throws {
            typealias M = MenuBarMetrics
            let layout = layout(MenuBarConfig(theme: .dms))
            assertEquals(layout.style, .dms)
            assertEquals(layout.cornerRadius, M.dmsPill / 2)
            // The focused workspace is a wider pill, the others are round
            let focused = try #require(layout.cells.firstIndex { $0.workspace == snapshot.focusedWorkspace })
            for (index, cell) in layout.cells.enumerated() {
                assertEquals(cell.frame.size, CGSize(width: index == focused ? M.dmsFocusedWidth : M.dmsPill, height: M.dmsPill))
                assertEquals(cell.frame.midY, M.height / 2)
                assertEquals(cell.name.font, .dmsName)
            }
            for (a, b) in zip(layout.cells, layout.cells.dropFirst()) {
                assertEquals(b.frame.minX - a.frame.maxX, M.dmsSpacing)
            }
            // The marker is the focused pill
            let marker = try #require(layout.marker)
            assertEquals(marker.frame, layout.cells[focused].frame)
            assertEquals(marker.cornerRadius, M.dmsPill / 2)
            // One track behind all of them, as wide as the item
            assertEquals(layout.tracks, [CGRect(x: 0, y: (M.height - M.dmsTrackHeight) / 2, width: layout.size.width, height: M.dmsTrackHeight)])
            assertEquals(layout.cells.first?.frame.minX, M.dmsTrackPadding)
            assertEquals(layout.cells.last.map { layout.size.width - $0.frame.maxX }, M.dmsTrackPadding)
        }

        @Test func testDmsFitsTheName() {
            var snapshot = snapshot
            snapshot.workspaces[1].name = "code"
            snapshot.focusedWorkspace = "code"
            let pill = layout(MenuBarConfig(theme: .dms), snapshot).cells[1]
            assertEquals(pill.frame.width, 6 * 4 + 2 * MenuBarMetrics.dmsNamePadding)
            assertEquals(pill.name.frame.midX, pill.frame.midX)
        }

        /// The pills make room for each other while the marker slides, and the track follows them
        @Test func testDmsStretchesWhileTheMarkerSlides() throws {
            typealias M = MenuBarMetrics
            let end = layout(MenuBarConfig(theme: .dms))
            let middle = layout(MenuBarConfig(theme: .dms), transition: .init(from: "4", progress: 0.5))
            let from = try #require(middle.cells.first { $0.workspace == "4" })
            let to = try #require(middle.cells.first { $0.workspace == snapshot.focusedWorkspace })
            assertEquals(from.frame.width, (M.dmsPill + M.dmsFocusedWidth) / 2)
            assertEquals(to.frame.width, (M.dmsPill + M.dmsFocusedWidth) / 2)
            assertEquals(middle.size.width, end.size.width)
            assertEquals(middle.tracks, end.tracks)
        }

        /// The initial of the mode in place of the name, and the outline while a window is fullscreen
        @Test func testDmsModeAndFullscreen() throws {
            var snapshot = snapshot
            snapshot.mode = "resize"
            snapshot.isFocusedWorkspaceFullscreen = true
            let main = layout(MenuBarConfig(theme: .dms, showMode: true))
            let mode = layout(MenuBarConfig(theme: .dms, showMode: true), snapshot)
            let marker = try #require(mode.marker)
            assertEquals(marker.isOutlined, true)
            assertEquals(marker.initial?.string, "R")
            assertEquals(marker.initial?.font, .modeInitial)
            assertEquals(marker.initial?.frame.midX, marker.frame.midX)
            assertEquals(mode.size, main.size)
        }

        // MARK: - Underline

        @Test func testUnderline() throws {
            typealias M = MenuBarMetrics
            let layout = layout(MenuBarConfig(theme: .underline))
            assertEquals(layout.style, .underline)
            // The names are 8 pt wide: the slots are as wide as the minimum
            assertEquals(layout.cells.map(\.frame.width), [M.underlineSlot, M.underlineSlot, M.underlineSlot, M.underlineSlot])
            // The names go up to make room for the bar
            for cell in layout.cells {
                assertEquals(cell.name.frame.midY, M.height / 2 - M.underlineLift)
            }
            let marker = try #require(layout.marker)
            let focused = layout.cells[1].frame
            assertEquals(marker.frame, CGRect(x: focused.midX - M.underlineWidth / 2, y: M.underlineTop, width: M.underlineWidth, height: M.underlineHeight))
            assertEquals(marker.frame.maxY < M.height, true)
        }

        /// The bar leaves by the edge on the side of the move: it stretches towards the next workspace, and the
        /// other edge catches up later
        @Test func testUnderlineStretches() throws {
            typealias M = MenuBarMetrics
            let config = MenuBarConfig(theme: .underline)
            let from = layout(config, MenuBarSnapshot(workspaces: snapshot.workspaces, focusedWorkspace: "4")).marker?.frame
            let to = layout(config).marker?.frame
            let (start, end) = try (#require(from), #require(to))
            // From 4 to 2: to the left
            let early = try #require(layout(config, transition: .init(from: "4", progress: 0.3)).marker?.frame)
            assertEquals(early.maxX, start.maxX)
            assertEquals(early.minX < start.minX && early.minX > end.minX, true)
            let late = try #require(layout(config, transition: .init(from: "4", progress: 0.8)).marker?.frame)
            assertEquals(late.minX, end.minX)
            assertEquals(late.maxX < start.maxX && late.maxX > end.maxX, true)
            assertEquals(late.width > M.underlineWidth, true)
        }

        /// In a binding mode its initial takes the place of the name of the focused workspace
        @Test func testUnderlineInABindingMode() throws {
            typealias M = MenuBarMetrics
            var snapshot = snapshot
            snapshot.mode = "service"
            let layout = layout(MenuBarConfig(theme: .underline, showMode: true), snapshot)
            let initial = try #require(layout.marker?.initial)
            assertEquals(initial.string, "S")
            assertEquals(initial.frame.midX, layout.cells[1].frame.midX)
            assertEquals(initial.frame.midY, layout.cells[1].name.frame.midY)
        }

        // MARK: - Liquid

        @Test func testLiquid() throws {
            typealias M = MenuBarMetrics
            let layout = layout(MenuBarConfig(theme: .liquid))
            assertEquals(layout.style, .liquid)
            assertEquals(layout.size, CGSize(width: 4 * M.liquidSlot, height: M.height))
            let marker = try #require(layout.marker)
            assertEquals(marker.frame.size, CGSize(width: M.liquidDrop, height: M.liquidDrop))
            assertEquals(marker.frame.midX, layout.cells[1].frame.midX)
            // At rest there is no trail
            assertNil(marker.trail)
        }

        /// The drop leads and its trail follows it, behind it: they meet again at the end
        @Test func testLiquidLeavesATrail() throws {
            let config = MenuBarConfig(theme: .liquid)
            let start = try #require(layout(config, MenuBarSnapshot(workspaces: snapshot.workspaces, focusedWorkspace: "4")).marker?.frame)
            for progress in [0.25, 0.5, 0.75] {
                let marker = try #require(layout(config, transition: .init(from: "4", progress: progress)).marker)
                let trail = try #require(marker.trail, "\(progress)")
                // From 4 to 2: the drop is on the left of its trail, and the trail hasn't gone past where it started
                assertEquals(marker.frame.midX < trail.midX, true, additionalMsg: "\(progress)")
                assertEquals(trail.midX <= start.midX, true, additionalMsg: "\(progress)")
            }
            assertNil(layout(config, transition: .init(from: "4", progress: 1)).marker?.trail)
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
            assertEquals(layout.placeholder, nil)
            assertEquals(layout.needsColor, false)
        }

        @Test func testChipsWithTheRealFont() {
            let layout = MenuBarLayout.make(MenuBarSamples.snapshot, MenuBarConfig(theme: .chips), measure: MenuBarFont.size)
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
            assertEquals(layout(MenuBarConfig(theme: .chips, dimEmptyWorkspaces: false)).cells.map(\.isDimmed), [false, false, false, false])
        }

        @Test func testFullscreen() {
            snapshot.isFocusedWorkspaceFullscreen = true
            assertEquals(layout().marker?.isOutlined, true)
            assertEquals(layout(MenuBarConfig(theme: .hypr)).marker?.isOutlined, true)
        }

        /// 'show-mode': the initial of the binding mode in the chip of the focused workspace, like the Chips style
        /// of Aeromenu did. Nothing is added next to the chips
        @Test func testModeInTheFocusedChip() {
            let main = layout(MenuBarConfig(theme: .chips, showMode: true))
            assertEquals(main.marker?.initial, nil)
            snapshot.mode = "resize"
            // Off with show-mode = false
            assertEquals(layout(MenuBarConfig(theme: .chips, showMode: false)).marker?.initial, nil)
            assertEquals(layout(MenuBarConfig(theme: .chips, showMode: false)).needsColor, false)
            let layout = layout(MenuBarConfig(theme: .chips, showMode: true))
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
            let layout = layout(MenuBarConfig(theme: .chips, showMode: true))
            // 3 characters of 7 pt and 3 pt on each side. The initial is in the middle of the chip
            assertEquals(layout.marker?.frame, CGRect(x: 19.5, y: 2.5, width: 27, height: 17))
            assertEquals(layout.marker?.initial?.frame.midX, 33)
            snapshot.mode = "main"
            assertEquals(self.layout(MenuBarConfig(theme: .chips, showMode: true)).size, layout.size)
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
            let middle = layout(MenuBarConfig(theme: .chips, showMode: true), transition: .init(from: "4", progress: 0.5))
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

        @Test func testHypr() {
            let layout = layout(MenuBarConfig(theme: .hypr))
            assertEquals(layout.style, .hypr)
            // Slots of 18 pt from the left edge, the focused one as wide as the others
            assertEquals(layout.cells.map(\.frame), [
                CGRect(x: 0, y: 0, width: 18, height: 22),
                CGRect(x: 18, y: 0, width: 18, height: 22),
                CGRect(x: 36, y: 0, width: 18, height: 22),
                CGRect(x: 54, y: 0, width: 18, height: 22),
            ])
            assertEquals(layout.size, CGSize(width: 72, height: 22))
            assertEquals(layout.cells[0].name.frame, CGRect(x: 5, y: 3, width: 8, height: 16))
            // A square of 8.5 pt in the place of the focused workspace
            assertEquals(layout.marker, .init(frame: CGRect(x: 22.75, y: 6.75, width: 8.5, height: 8.5), cornerRadius: 2, isOutlined: false))
            assertEquals(layout.needsColor, false)
        }

        /// A name too wide for the slot makes it wider
        @Test func testHyprFitsTheName() {
            let snapshot = MenuBarSnapshot(workspaces: [.init(name: "web", isOccupied: true)], focusedWorkspace: "web")
            assertEquals(layout(MenuBarConfig(theme: .hypr), snapshot).cells[0].frame.width, 3 * 8 + 4)
        }

        @Test func testHyprMode() {
            snapshot.mode = "resize"
            // Without 'show-mode' the square is the one of the main mode
            let main = layout(MenuBarConfig(theme: .hypr, showMode: false))
            assertEquals(main.marker, .init(frame: CGRect(x: 22.75, y: 6.75, width: 8.5, height: 8.5), cornerRadius: 2, isOutlined: false))
            // With it, the square grows to 14 pt and carries the initial, like the Square style of Aeromenu
            let layout = layout(MenuBarConfig(theme: .hypr, showMode: true))
            assertEquals(layout.marker, .init(
                frame: CGRect(x: 20, y: 4, width: 14, height: 14),
                cornerRadius: 3.5,
                isOutlined: false,
                initial: .init(string: "R", font: .modeInitial, frame: CGRect(x: 23, y: 5, width: 8, height: 12)),
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

        @Test func testSlideOfTheHyprSquare() {
            let middle = layout(MenuBarConfig(theme: .hypr), transition: .init(from: "4", progress: 0.5))
            // The slots don't move: only the square slides
            assertEquals(middle.cells.map(\.frame), layout(MenuBarConfig(theme: .hypr)).cells.map(\.frame))
            assertEquals(middle.cells.map(\.focus), [0, 0.5, 0, 0.5])
            assertEquals(middle.marker?.frame.midX, (27 + 63) / 2)
            assertEquals(middle.size.width, 72)
        }

        // MARK: - Placeholders

        @Test func testPlaceholders() {
            snapshot.status = .paused
            let paused = layout(MenuBarConfig(theme: .hypr, showMode: true))
            assertEquals(paused.cells, [])
            assertEquals(paused.marker, nil)
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

        /// The left button opens the menu, wherever it clicks. The right button and a ctrl-click do nothing
        @Test func testOnlyTheLeftButtonOpensTheMenu() {
            func opensMenu(_ type: NSEvent.EventType?, control: Bool = false, age: TimeInterval? = 0.01) -> Bool {
                MenuBarController.opensMenu(eventType: type, isControlPressed: control, eventAge: age)
            }
            assertEquals(opensMenu(.leftMouseUp), true)
            assertEquals(opensMenu(.leftMouseDown), true)
            assertEquals(opensMenu(.rightMouseUp), false)
            assertEquals(opensMenu(.rightMouseDown), false)
            assertEquals(opensMenu(.leftMouseUp, control: true), false)
            assertEquals(opensMenu(.rightMouseUp, control: true), false)
            // Pressed through the accessibility API (VoiceOver): there is no event, or the current one is an old one
            assertEquals(opensMenu(nil, age: nil), true)
            assertEquals(opensMenu(.leftMouseUp, age: 30), true)
            assertEquals(opensMenu(.keyDown), true)
        }
    }

    @Suite struct MenuBarPaletteTest {
        private let accent = Rgba(red: 1, green: 0.5, blue: 0)

        private func palette(_ config: MenuBarConfig = MenuBarConfig(theme: .chips), style: MenuBarLayout.Style = .chips, dark: Bool = true, needsColor: Bool = false) -> MenuBarPalette {
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
            assertEquals(palette(MenuBarConfig(theme: .chips, dimEmptyWorkspaces: false)).emptyName, Rgba.black.withAlpha(0.72))
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
            let white = MenuBarConfig(theme: .chips, colors: MenuBarColors(accent: .rgba(.white)))
            assertEquals(palette(white).isTemplate, true)
            assertEquals(palette(white, needsColor: true).isTemplate, false)
        }

        @Test func testSquareNamesAreNotFaded() {
            let palette = palette(style: .hypr)
            assertEquals(palette.isTemplate, true)
            assertEquals(palette.occupiedName, .black)
            assertEquals(palette.emptyName, Rgba.black.withAlpha(0.35))
        }

        @Test func testAccentColorsTheMarkerOfAMode() {
            // The rest has the same look, but with the color of the menu bar text baked in
            let config = MenuBarConfig(theme: .chips, colors: MenuBarColors(accent: .systemAccent))
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
            assertEquals(palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(accent: .rgba(yellow))), needsColor: true).modeInitial, .black)
        }

        /// 'accent' is 'auto': the marker of a mode has the fixed color of 'focused', and the initial contrasts with it
        @Test func testTheMarkerOfAModeFollowsFocused() {
            let navy = Rgba(hex: "#1E3A8A").orDie()
            for dark in [true, false] {
                let palette = palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(focused: .rgba(navy))), dark: dark, needsColor: true)
                assertEquals(palette.modeMarker, navy)
                assertEquals(palette.modeInitial, .white)
            }
        }

        @Test func testFixedColors() {
            let orange = Rgba(hex: "#D19A66").orDie()
            let gray = Rgba(hex: "#ABB2BF").orDie()
            let translucent = Rgba(hex: "#CDD6F466").orDie()
            let config = MenuBarConfig(theme: .chips, colors: MenuBarColors(accent: .rgba(.white), focused: .rgba(orange), occupied: .rgba(gray), empty: .rgba(translucent)))
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
            let focused = palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(focused: .rgba(navy))))
            assertEquals(focused.isTemplate, false)
            assertEquals(focused.focusedName, .white)
            // The colors that stay 'auto' follow the menu bar
            assertEquals(focused.occupiedName, Rgba.white.withAlpha(0.72))
            assertEquals(palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(focused: .rgba(navy))), dark: false).occupiedName, Rgba.black.withAlpha(0.72))
            assertEquals(palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(occupied: .rgba(navy)))).isTemplate, false)
            assertEquals(palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(empty: .rgba(navy)))).isTemplate, false)

            let systemAccent = palette(MenuBarConfig(theme: .chips, colors: MenuBarColors(focused: .systemAccent)))
            assertEquals(systemAccent.isTemplate, false)
            assertEquals(systemAccent.focused, accent)
        }
    }

    @Suite @MainActor struct MenuBarRendererTest {
        private func alpha(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) -> Int {
            Int(((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded())
        }

        @Test func testTemplateImage() throws {
            let layout = MenuBarLayout.make(MenuBarSamples.snapshot, MenuBarConfig(theme: .chips), measure: MenuBarFont.size)
            let palette = MenuBarPalette.resolve(MenuBarConfig(theme: .chips), style: .chips, isDarkBar: true, systemAccent: .white)
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
            let config = MenuBarConfig(theme: .chips, colors: MenuBarColors(focused: .rgba(Rgba(red: 1, green: 0, blue: 0))))
            let layout = MenuBarLayout.make(MenuBarSamples.snapshot, config, measure: MenuBarFont.size)
            let palette = MenuBarPalette.resolve(config, style: .chips, isDarkBar: true, systemAccent: .white)
            assertEquals(try #require(MenuBarRenderer.image(layout, palette, scale: 2)).isTemplate, false)
            let bitmap = try #require(MenuBarRenderer.bitmap(layout, palette, scale: 2))
            let focused = try #require(bitmap.colorAt(x: 43, y: 20))
            assertEquals([focused.redComponent, focused.greenComponent, focused.blueComponent, focused.alphaComponent], [1, 0, 0, 1])
            // The name isn't cut out: every pixel of the chip is opaque
            assertEquals((44 ..< 68).allSatisfy { alpha(bitmap, $0, 22) == 255 }, true)
        }

        /// 'system-colors': the colors of [menu-bar.colors] are kept, but the item is a template image, like the other
        /// icons of the menu bar, also while it shows a binding mode
        @Test func testSystemColors() throws {
            let colors = MenuBarColors(
                accent: .rgba(Rgba(red: 0, green: 1, blue: 0)),
                focused: .rgba(Rgba(red: 1, green: 0, blue: 0)),
                occupied: .systemAccent,
                empty: .rgba(Rgba(red: 0, green: 0, blue: 1)),
            )
            let config = MenuBarConfig(theme: .liquid, showMode: true, colors: colors, systemColors: true)
            assertEquals(config.colors, colors)
            assertEquals(config.effectiveColors, MenuBarColors())
            assertEquals(MenuBarConfig(colors: colors).effectiveColors, colors)
            for needsColor in [false, true] {
                let palette = MenuBarPalette.resolve(config, style: .liquid, isDarkBar: true, systemAccent: .white, needsColor: needsColor)
                assertEquals(palette.isTemplate, true)
                assertEquals(palette, MenuBarPalette.resolve(MenuBarConfig(theme: .liquid, showMode: true), style: .liquid, isDarkBar: true, systemAccent: .white, needsColor: needsColor))
            }
        }

        /// The initial of the binding mode is cut out of the chip of the focused workspace, where its name was
        @Test func testModeInTheChip() throws {
            var snapshot = MenuBarSamples.snapshot
            snapshot.mode = "resize"
            let config = MenuBarConfig(theme: .chips, showMode: true)
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
            let accent = MenuBarConfig(theme: .chips, showMode: true, colors: MenuBarColors(accent: .rgba(Rgba(red: 1, green: 0, blue: 0))))
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
            let oneColor = MenuBarTheme.allCases.flatMap { theme in
                ["default", "fullscreen", "mode-fullscreen", "mode"].map { "\(theme.rawValue)-\($0)" }
            }
            let slides = ["pills", "dots", "underline", "liquid", "dms"].flatMap { theme in [20, 40, 60, 80].map { "\(theme)-slide-\($0)" } }
            let templates = (oneColor + slides + MenuBarTheme.allCases.flatMap { ["\($0.rawValue)-per-monitor", "\($0.rawValue)-two-monitors"] } + ["chips-no-dim", "needs-accessibility", "paused"]).map { "\($0)-template.png" }
            assertEquals(files.filter { $0.hasSuffix("-template.png") }.sorted(), templates.sorted())
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

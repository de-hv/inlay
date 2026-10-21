import Common
import Foundation

/// The metrics of the menu bar item, in points. The ones of the chips and of the square are the ones of Aeromenu
enum MenuBarMetrics {
    static let height: CGFloat = 22

    static let chipSide: CGFloat = 17
    /// The pills theme: round workspaces as tall as the chips, and the focused one this wide
    static let pillFocusedWidth: CGFloat = 32
    static let pillSpacing: CGFloat = 3
    static let chipCornerRadius: CGFloat = 4.5
    static let chipSpacing: CGFloat = 2.5
    static let chipPadding: CGFloat = 3
    static let chipFontSize: CGFloat = 12
    static let chipOpacity: Double = 0.14
    /// The background of an occupied chip that has a fixed color
    static let chipColorOpacity: Double = 0.16
    static let chipNameOpacity: Double = 0.72
    static let emptyWorkspaceOpacity: Double = 0.35
    static let outlineWidth: CGFloat = 1.5

    static let workspaceWidth: CGFloat = 15
    static let focusedWorkspaceWidth: CGFloat = 17
    static let workspaceFontSize: CGFloat = 13.5
    static let focusSquare: CGFloat = 8.5
    static let focusSquareCornerRadius: CGFloat = 2
    static let markerClearance: CGFloat = 1.5

    /// The square of the square style while it shows the initial of the binding mode
    static let modeSquare: CGFloat = 14
    static let modeSquareCornerRadius: CGFloat = 3.5
    static let modeSquareFontSize: CGFloat = 10.5
    /// The initial of the binding mode in a chip. The size it had in the Chips style of Aeromenu
    static let chipModeFontSize: CGFloat = 11

    /// The dots theme: a dot per workspace, and the focused one stretched into a pill this wide
    static let dotSide: CGFloat = 7
    static let dotFocusedWidth: CGFloat = 20
    static let dotSpacing: CGFloat = 5
    static let dotLineWidth: CGFloat = 1.3

    /// The underline theme: the names in slots at least this wide, and a bar under the focused one
    static let underlineSlot: CGFloat = 16
    static let underlineWidth: CGFloat = 9
    static let underlineHeight: CGFloat = 2
    /// The top of the bar, from the top of the item
    static let underlineTop: CGFloat = 18.5
    /// The names go up this much, to make room for the bar
    static let underlineLift: CGFloat = 1.5

    /// The glyphs theme: the target of the focused workspace, the ring of an empty one and the disc of one with windows
    static let ringSide: CGFloat = 12
    static let ringEmptySide: CGFloat = 8.5
    static let ringDiscSide: CGFloat = 7
    static let ringCenterSide: CGFloat = 5
    static let ringSpacing: CGFloat = 4.5
    static let ringLineWidth: CGFloat = 1.4

    /// The liquid theme: the dots in slots this wide, the drop over the focused one and its trail
    static let liquidSlot: CGFloat = 17
    static let liquidDrop: CGFloat = 17
    static let liquidTrail: CGFloat = 11
    static let liquidEmptyDot: CGFloat = 3.6
    static let liquidOccupiedDot: CGFloat = 5

    static let glyphSide: CGFloat = 6
    static let glyphGap: CGFloat = 1.5
    static let glyphLineWidth: CGFloat = 1.1
    static let glyphCornerRadius: CGFloat = 1.4
    static let idleOpacity: Double = 0.5
    static let statusSymbolSize: CGFloat = 9
    /// The widths of the 'pause.fill' and 'exclamationmark.triangle.fill' symbols at that size
    static let pauseSymbolWidth: CGFloat = 7.5
    static let warningSymbolWidth: CGFloat = 11.5
    static let statusSymbolToGlyph: CGFloat = 5
}

/// The texts of the item. The layout only needs their sizes
enum MenuBarFont: Equatable, Sendable {
    /// SF 12 pt semibold, monospaced digits
    case chipName
    /// SF 13.5 pt medium, monospaced digits
    case squareName
    /// SF 10.5 pt heavy: the initial of the binding mode in the square
    case modeInitial
    /// SF 11 pt heavy: the initial of the binding mode in a chip
    case chipModeInitial
}

/// The focus marker on its way from the previously focused workspace to the focused one: one frame of the slide
struct MenuBarFocusTransition: Equatable, Sendable {
    var from: String
    /// 0 at the previous workspace, 1 at the focused one
    var progress: Double
}

/// Where everything of the menu bar item is. Pure geometry: no colors, no AppKit.
///
/// The origin is the top left corner, and y grows down
struct MenuBarLayout: Equatable, Sendable {
    enum Style: Equatable, Sendable {
        /// 'chips', 'pills' and 'minimal' themes
        case chips
        case square
        case dots
        case underline
        case glyphs
        case liquid
    }

    struct Text: Equatable, Sendable {
        var string: String
        var font: MenuBarFont
        var frame: CGRect
    }

    /// One workspace
    struct Cell: Equatable, Sendable {
        var workspace: String
        /// The chip, or the slot of the name in the square style
        var frame: CGRect
        var name: Text
        var isOccupied: Bool
        /// The workspace is empty and 'dim-empty-workspaces' is on
        var isDimmed: Bool
        /// 1 under the focus marker, 0 away from it, in between while the marker slides
        var focus: Double
    }

    /// Marks the focused workspace
    struct Marker: Equatable, Sendable {
        var frame: CGRect
        var cornerRadius: CGFloat
        /// Outlined instead of filled: one of the windows of the workspace is fullscreen
        var isOutlined: Bool
        /// With 'show-mode', outside of the main mode: the initial of the binding mode inside of the marker.
        /// A chip shows it instead of the name of the workspace, and the square grows to make room for it.
        /// Either way the item is as wide as in the main mode, like in Aeromenu
        var initial: Text? = nil
        /// The liquid theme: the end of the trail that the drop leaves behind while it flows. nil at rest
        var trail: CGRect? = nil
    }

    /// Shown instead of the workspaces when Inlay doesn't manage windows
    struct Placeholder: Equatable, Sendable {
        var status: MenuBarSnapshot.Status
        /// The 3x2 grid of the app glyph
        var glyphFrame: CGRect
        var glyphOpacity: Double
        /// SF Symbol next to the glyph
        var symbolName: String
        var symbolFrame: CGRect
    }

    var style: Style
    /// The radius of the corners of the workspaces and of the marker, in the chips style
    var cornerRadius: CGFloat = MenuBarMetrics.chipCornerRadius
    var size: CGSize
    var cells: [Cell] = []
    var marker: Marker? = nil
    var placeholder: Placeholder? = nil
}

extension MenuBarLayout {
    typealias Measure = (String, MenuBarFont) -> CGSize

    /// - Parameter measure: the size of a text in a font. The real one is `MenuBarFont.size(of:)`
    static func make(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        transition: MenuBarFocusTransition? = nil,
        measure: Measure,
    ) -> MenuBarLayout {
        if snapshot.status != .running { return placeholder(snapshot.status) }
        let progress = transition.map { min(max($0.progress, 0), 1) } ?? 1
        // Without the workspace the marker comes from, there is nothing to slide from
        let from = transition?.from.takeIf { from in progress < 1 && snapshot.workspaces.contains { $0.name == from } }
        func focusAmount(_ workspace: String) -> Double {
            switch workspace {
                case snapshot.focusedWorkspace: from == nil ? 1 : progress
                case from: 1 - progress
                default: 0
            }
        }
        var layout = switch config.theme {
            case .pills: pills(snapshot, config, focusAmount, measure)
            case .chips: chips(snapshot, config, snapshot.workspaces, focusAmount, measure)
            case .minimal: chips(snapshot, config, snapshot.workspaces.filter { $0.name == snapshot.focusedWorkspace }, focusAmount, measure)
            case .square: square(snapshot, config, focusAmount, measure)
            case .dots: dots(snapshot, config, focusAmount, measure)
            case .underline: underline(snapshot, config, focusAmount, measure)
            case .glyphs: glyphs(snapshot, config, focusAmount, measure)
            case .liquid: liquid(snapshot, config, focusAmount, measure)
        }
        layout.placeMarker(snapshot, mode: config.showMode ? snapshot.nonMainMode : nil, from: from, progress: from == nil ? 1 : progress, measure)
        return layout
    }

    // MARK: - Chips

    private static func chips(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ workspaces: [MenuBarSnapshot.Workspace],
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let top = (M.height - M.chipSide) / 2
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in workspaces {
            // The chip of Aeromenu: the name in the middle
            let nameSize = measure(workspace.name, .chipName)
            let frame = CGRect(x: x, y: top, width: max(M.chipSide, nameSize.width + 2 * M.chipPadding), height: M.chipSide)
            cells.append(Cell(
                workspace: workspace.name,
                frame: frame,
                name: Text(string: workspace.name, font: .chipName, frame: nameSize.centered(in: frame)),
                isOccupied: workspace.isOccupied,
                isDimmed: !workspace.isOccupied && config.dimEmptyWorkspaces,
                focus: focusAmount(workspace.name),
            ))
            x = frame.maxX + M.chipSpacing
        }
        return MenuBarLayout(style: .chips, size: CGSize(width: max(0, x - M.chipSpacing), height: M.height), cells: cells)
    }

    // MARK: - Pills

    /// The chips, round, and the focused one wider. The width follows the focus while the marker slides, so the pills make
    /// room for each other as it goes
    private static func pills(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let top = (M.height - M.chipSide) / 2
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let nameSize = measure(workspace.name, .chipName)
            let focus = focusAmount(workspace.name)
            let narrow = max(M.chipSide, nameSize.width + 2 * M.chipPadding)
            let wide = max(M.pillFocusedWidth, nameSize.width + 2 * M.chipSide / 2)
            let frame = CGRect(x: x, y: top, width: narrow + (wide - narrow) * focus, height: M.chipSide)
            cells.append(Cell(
                workspace: workspace.name,
                frame: frame,
                name: Text(string: workspace.name, font: .chipName, frame: nameSize.centered(in: frame)),
                isOccupied: workspace.isOccupied,
                isDimmed: !workspace.isOccupied && config.dimEmptyWorkspaces,
                focus: focus,
            ))
            x = frame.maxX + M.pillSpacing
        }
        return MenuBarLayout(style: .chips, cornerRadius: M.chipSide / 2, size: CGSize(width: max(0, x - M.pillSpacing), height: M.height), cells: cells)
    }

    // MARK: - Square

    private static func square(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let focus = focusAmount(workspace.name)
            let nameSize = measure(workspace.name, .squareName)
            // The slot is wide enough for the square of a binding mode while focused, in every mode, so nothing shifts
            // when the mode changes
            let slot = CGRect(
                x: x,
                y: 0,
                width: max(nameSize.width, M.workspaceWidth + (M.focusedWorkspaceWidth - M.workspaceWidth) * focus),
                height: M.height,
            )
            cells.append(Cell(
                workspace: workspace.name,
                frame: slot,
                name: Text(string: workspace.name, font: .squareName, frame: nameSize.centered(in: slot)),
                isOccupied: workspace.isOccupied,
                isDimmed: !workspace.isOccupied && config.dimEmptyWorkspaces,
                focus: focus,
            ))
            x = slot.maxX
        }
        return MenuBarLayout(style: .square, size: CGSize(width: x, height: M.height), cells: cells)
    }

    // MARK: - Dots

    /// The pills without names, smaller: a dot per workspace, and the focused one stretched into a pill. The width
    /// follows the focus while the marker slides, like in the pills
    private static func dots(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let top = (M.height - M.dotSide) / 2
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let focus = focusAmount(workspace.name)
            let frame = CGRect(x: x, y: top, width: M.dotSide + (M.dotFocusedWidth - M.dotSide) * focus, height: M.dotSide)
            cells.append(cell(workspace, config, frame: frame, font: .chipName, focus: focus, measure))
            x = frame.maxX + M.dotSpacing
        }
        return MenuBarLayout(style: .dots, cornerRadius: M.dotSide / 2, size: CGSize(width: max(0, x - M.dotSpacing), height: M.height), cells: cells)
    }

    // MARK: - Underline

    /// The names, like in the square style, a bit higher to leave room for the bar under the focused one
    private static func underline(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let nameSize = measure(workspace.name, .squareName)
            let slot = CGRect(x: x, y: 0, width: max(M.underlineSlot, nameSize.width + 6), height: M.height)
            var cell = cell(workspace, config, frame: slot, font: .squareName, focus: focusAmount(workspace.name), measure)
            cell.name.frame = cell.name.frame.offsetBy(dx: 0, dy: -M.underlineLift)
            cells.append(cell)
            x = slot.maxX
        }
        return MenuBarLayout(style: .underline, size: CGSize(width: x, height: M.height), cells: cells)
    }

    // MARK: - Glyphs

    /// A glyph per workspace. The focus fades from one glyph to the other instead of sliding
    private static func glyphs(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let top = (M.height - M.ringSide) / 2
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let frame = CGRect(x: x, y: top, width: M.ringSide, height: M.ringSide)
            cells.append(cell(workspace, config, frame: frame, font: .chipName, focus: focusAmount(workspace.name), measure))
            x = frame.maxX + M.ringSpacing
        }
        return MenuBarLayout(style: .glyphs, cornerRadius: M.ringSide / 2, size: CGSize(width: max(0, x - M.ringSpacing), height: M.height), cells: cells)
    }

    // MARK: - Liquid

    /// A dot in the middle of every slot. The drop is the marker, with the name of the workspace in it
    private static func liquid(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let top = (M.height - M.liquidDrop) / 2
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let frame = CGRect(x: x, y: top, width: M.liquidSlot, height: M.liquidDrop)
            cells.append(cell(workspace, config, frame: frame, font: .chipName, focus: focusAmount(workspace.name), measure))
            x = frame.maxX
        }
        return MenuBarLayout(style: .liquid, cornerRadius: M.liquidDrop / 2, size: CGSize(width: x, height: M.height), cells: cells)
    }

    private static func cell(
        _ workspace: MenuBarSnapshot.Workspace,
        _ config: MenuBarConfig,
        frame: CGRect,
        font: MenuBarFont,
        focus: Double,
        _ measure: Measure,
    ) -> Cell {
        Cell(
            workspace: workspace.name,
            frame: frame,
            name: Text(string: workspace.name, font: font, frame: measure(workspace.name, font).centered(in: frame)),
            isOccupied: workspace.isOccupied,
            isDimmed: !workspace.isOccupied && config.dimEmptyWorkspaces,
            focus: focus,
        )
    }

    // MARK: - Shared

    /// - Parameter mode: the binding mode to show in the marker, if any
    private mutating func placeMarker(_ snapshot: MenuBarSnapshot, mode: String?, from: String?, progress: Double, _ measure: Measure) {
        typealias M = MenuBarMetrics
        guard let end = cells.first(where: { $0.workspace == snapshot.focusedWorkspace })?.frame else { return }
        let start = from.flatMap { from in cells.first { $0.workspace == from } }?.frame ?? end
        let midX = start.midX + (end.midX - start.midX) * progress
        switch style {
            case .chips:
                let width = start.width + (end.width - start.width) * progress
                let frame = CGRect(x: midX - width / 2, y: end.minY, width: width, height: end.height)
                marker = Marker(
                    frame: frame,
                    cornerRadius: cornerRadius,
                    isOutlined: snapshot.isFocusedWorkspaceFullscreen,
                    // The chip is at least as wide as it is tall, so one character always fits
                    initial: mode.map { MenuBarLayout.initial(of: $0, .chipModeInitial, in: frame, measure) },
                )
            case .square:
                let side = mode == nil ? M.focusSquare : M.modeSquare
                let frame = CGRect(x: midX - side / 2, y: end.midY - side / 2, width: side, height: side)
                marker = Marker(
                    frame: frame,
                    cornerRadius: mode == nil ? M.focusSquareCornerRadius : M.modeSquareCornerRadius,
                    isOutlined: snapshot.isFocusedWorkspaceFullscreen,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .modeInitial, in: frame, measure) },
                )
            case .dots:
                // The pill slides and stretches like the one of the pills. In a binding mode it grows taller, like
                // the square, to hold the initial
                let width = start.width + (end.width - start.width) * progress
                let height = mode == nil ? end.height : M.modeSquare
                let frame = CGRect(x: midX - width / 2, y: end.midY - height / 2, width: width, height: height)
                marker = Marker(
                    frame: frame,
                    cornerRadius: height / 2,
                    isOutlined: snapshot.isFocusedWorkspaceFullscreen,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .modeInitial, in: frame, measure) },
                )
            case .underline:
                // The edge on the side of the move leaves first and the other one catches up: the bar stretches
                // towards the next workspace, then shrinks into it
                func bar(_ slot: CGRect) -> CGRect {
                    CGRect(x: slot.midX - M.underlineWidth / 2, y: M.underlineTop, width: M.underlineWidth, height: M.underlineHeight)
                }
                let (from, to) = (bar(start), bar(end))
                let lead = min(1, progress * 1.7)
                let trail = max(0, (progress - 0.4) / 0.6)
                let isRight = to.minX >= from.minX
                let minX = from.minX + (to.minX - from.minX) * (isRight ? trail : lead)
                let maxX = from.maxX + (to.maxX - from.maxX) * (isRight ? lead : trail)
                // The initial of the binding mode takes the place of the name of the workspace, like in the chips
                let nameArea = end.offsetBy(dx: 0, dy: -M.underlineLift)
                marker = Marker(
                    frame: CGRect(x: minX, y: to.minY, width: maxX - minX, height: to.height),
                    cornerRadius: M.underlineHeight / 2,
                    isOutlined: snapshot.isFocusedWorkspaceFullscreen,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .chipModeInitial, in: nameArea, measure) },
                )
            case .glyphs:
                // The glyphs fade into each other (see Cell.focus): the marker only matters in a binding mode, where
                // the target becomes a disc that holds the initial
                let side = mode == nil ? M.ringSide : M.modeSquare
                let frame = CGRect(x: end.midX - side / 2, y: end.midY - side / 2, width: side, height: side)
                marker = Marker(
                    frame: frame,
                    cornerRadius: side / 2,
                    isOutlined: snapshot.isFocusedWorkspaceFullscreen,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .modeInitial, in: frame, measure) },
                )
            case .liquid:
                // The drop leads, and its trail follows it later: stretched in between, one round drop again at the end
                let trailProgress = pow(progress, 2.4)
                let trailMidX = start.midX + (end.midX - start.midX) * trailProgress
                let frame = CGRect(x: midX - M.liquidDrop / 2, y: end.midY - M.liquidDrop / 2, width: M.liquidDrop, height: M.liquidDrop)
                marker = Marker(
                    frame: frame,
                    cornerRadius: M.liquidDrop / 2,
                    isOutlined: snapshot.isFocusedWorkspaceFullscreen,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .chipModeInitial, in: frame, measure) },
                    trail: abs(trailMidX - midX) < 0.5 ? nil : CGRect(
                        x: trailMidX - M.liquidTrail / 2,
                        y: end.midY - M.liquidTrail / 2,
                        width: M.liquidTrail,
                        height: M.liquidTrail,
                    ),
                )
        }
    }

    private static func initial(of mode: String, _ font: MenuBarFont, in frame: CGRect, _ measure: Measure) -> Text {
        let string = modeInitial(mode)
        return Text(string: string, font: font, frame: measure(string, font).centered(in: frame))
    }

    /// 'resize' -> 'R'. A mode named in another script keeps its own first character
    static func modeInitial(_ mode: String) -> String {
        mode.first.map { String($0).uppercased() } ?? "?"
    }

    private static func placeholder(_ status: MenuBarSnapshot.Status) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let glyphSize = CGSize(width: 3 * M.glyphSide + 2 * M.glyphGap, height: 2 * M.glyphSide + M.glyphGap)
        let symbol = CGRect(x: 0, y: 0, width: status == .paused ? M.pauseSymbolWidth : M.warningSymbolWidth, height: M.height)
        let glyph = CGRect(x: symbol.maxX + M.statusSymbolToGlyph, y: (M.height - glyphSize.height) / 2, width: glyphSize.width, height: glyphSize.height)
        return MenuBarLayout(
            style: .chips,
            size: CGSize(width: glyph.maxX, height: M.height),
            placeholder: Placeholder(
                status: status,
                glyphFrame: glyph,
                glyphOpacity: status == .paused ? 1 : M.idleOpacity,
                symbolName: status == .paused ? "pause.fill" : "exclamationmark.triangle.fill",
                symbolFrame: symbol,
            ),
        )
    }
}

extension CGSize {
    fileprivate func centered(in rect: CGRect) -> CGRect {
        CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }
}

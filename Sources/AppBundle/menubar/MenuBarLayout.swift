import Common
import Foundation

/// The metrics of the menu bar item, in points. The ones of the chips and of the square of hypr are the ones of Aeromenu
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
    /// The ring around the focus marker while one of the windows of the workspace is fullscreen: this far from it
    static let haloGap: CGFloat = 2
    static let haloWidth: CGFloat = 1
    static let haloOpacity: Double = 0.7

    static let workspaceFontSize: CGFloat = 13.5
    /// The hypr theme: every workspace in a slot this wide, and its name a bit smaller than in the underline theme,
    /// like in the Omarchy bar
    static let hyprSlot: CGFloat = 20
    static let hyprFontSize: CGFloat = 13
    /// The hypr theme: the frame around the name of a workspace that another monitor shows ('perMonitor')
    static let hyprFrame: CGFloat = 15
    static let hyprFrameCornerRadius: CGFloat = 3.5
    static let focusSquare: CGFloat = 11
    static let focusSquareCornerRadius: CGFloat = 1.5
    static let markerClearance: CGFloat = 1.5

    /// The square of the hypr theme while it shows the initial of the binding mode
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

    /// The liquid theme: the dots in slots this wide, the drop over the focused one and its trail
    static let liquidSlot: CGFloat = 17
    static let liquidDrop: CGFloat = 17
    static let liquidTrail: CGFloat = 11
    static let liquidEmptyDot: CGFloat = 3.6
    static let liquidOccupiedDot: CGFloat = 5

    /// The dms theme: the workspaces on a track, round, and the focused one stretched into a pill with its name
    static let dmsTrackHeight: CGFloat = 20
    static let dmsTrackPadding: CGFloat = 4
    static let dmsPill: CGFloat = 12
    static let dmsFocusedWidth: CGFloat = 26
    /// The room on each side of the name in the focused pill
    static let dmsNamePadding: CGFloat = 6
    static let dmsSpacing: CGFloat = 4
    static let dmsFontSize: CGFloat = 9.5
    /// 'perMonitor': the room between the tracks of two monitors, which is the divider: no line
    static let dmsTrackGap: CGFloat = 6

    /// 'perMonitor': the room between the workspaces of two monitors, with a line in the middle
    static let monitorSeparatorSpace: CGFloat = 9
    static let monitorSeparatorWidth: CGFloat = 1
    static let monitorSeparatorHeight: CGFloat = 11
    /// The divider of the hypr theme: bolder, like the one of the Monitor Workspaces plugin
    static let hyprSeparatorSpace: CGFloat = 10
    static let hyprSeparatorWidth: CGFloat = 2
    static let hyprSeparatorHeight: CGFloat = 12
    static let hyprSeparatorOpacity: Double = 0.65

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
    /// SF 13 pt medium, monospaced digits: the names of the hypr theme
    case hyprName
    /// SF 10.5 pt heavy: the initial of the binding mode in the square
    case modeInitial
    /// SF 11 pt heavy: the initial of the binding mode in a chip
    case chipModeInitial
    /// SF 9.5 pt semibold, monospaced digits: the name in the focused pill of the dms theme
    case dmsName
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
        case hypr
        case dots
        case underline
        case liquid
        case dms
    }

    struct Text: Equatable, Sendable {
        var string: String
        var font: MenuBarFont
        var frame: CGRect
    }

    /// One workspace
    struct Cell: Equatable, Sendable {
        var workspace: String
        /// The chip, or the slot of the name in the hypr style
        var frame: CGRect
        var name: Text
        var isOccupied: Bool
        /// The workspace is empty and 'dimEmptyWorkspaces' is on
        var isDimmed: Bool
        /// 1 under the focus marker, 0 away from it, in between while the marker slides
        var focus: Double
        /// 'perMonitor': another monitor shows the workspace
        var isVisibleElsewhere: Bool = false

        func offsetBy(dx: CGFloat) -> Cell {
            var cell = self
            cell.frame = frame.offsetBy(dx: dx, dy: 0)
            cell.name.frame = name.frame.offsetBy(dx: dx, dy: 0)
            return cell
        }
    }

    /// Marks the focused workspace
    struct Marker: Equatable, Sendable {
        var frame: CGRect
        var cornerRadius: CGFloat
        /// Outlined instead of filled: the hollow marker of a workspace that another monitor shows ('perMonitor')
        var isOutlined: Bool
        /// With 'showMode', outside of the main mode: the initial of the binding mode inside of the marker.
        /// A chip shows it instead of the name of the workspace, and the square grows to make room for it.
        /// Either way the item is as wide as in the main mode, like in Aeromenu
        var initial: Text? = nil
        /// The liquid theme: the end of the trail that the drop leaves behind while it flows. nil at rest
        var trail: CGRect? = nil
        /// A ring around the marker: one of the windows of the workspace is fullscreen
        var halo: Halo? = nil
    }

    struct Halo: Equatable, Sendable {
        var frame: CGRect
        var cornerRadius: CGFloat
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
    /// 'perMonitor': the lines between the workspaces of two monitors
    var separators: [CGRect] = []
    /// 'perMonitor': the hollow markers of the workspaces that another monitor shows
    var visibleElsewhere: [Marker] = []
    var placeholder: Placeholder? = nil
    /// The dms theme: the capsules behind the workspaces, one per monitor with 'perMonitor'
    var tracks: [CGRect] = []
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
        var snapshot = snapshot
        if config.perMonitor {
            // Monitor by monitor, from left to right, each one in the order of the item
            snapshot.workspaces = snapshot.workspaces.enumerated()
                .sorted { ($0.element.monitor, $0.offset) < ($1.element.monitor, $1.offset) }
                .map(\.element)
        }
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
            case .hypr: hypr(snapshot, config, focusAmount, measure)
            case .dots: dots(snapshot, config, focusAmount, measure)
            case .underline: underline(snapshot, config, focusAmount, measure)
            case .liquid: liquid(snapshot, config, focusAmount, measure)
            case .dms: dms(snapshot, config, focusAmount, measure)
        }
        if config.perMonitor { layout.separateMonitors(snapshot) }
        if layout.style == .dms { layout.placeTracks(snapshot, perMonitor: config.perMonitor) }
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

    // MARK: - Hypr

    /// The names in slots of the same width, like the Monitor Workspaces plugin of the Omarchy bar. The slot of a name too
    /// wide for it grows to hold it
    private static func hypr(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        var cells: [Cell] = []
        var x: CGFloat = 0
        for workspace in snapshot.workspaces {
            let nameSize = measure(workspace.name, .hyprName)
            let slot = CGRect(x: x, y: 0, width: max(M.hyprSlot, nameSize.width + 4), height: M.height)
            cells.append(cell(workspace, config, frame: slot, font: .hyprName, focus: focusAmount(workspace.name), measure))
            x = slot.maxX
        }
        return MenuBarLayout(style: .hypr, size: CGSize(width: x, height: M.height), cells: cells)
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

    /// The names, like in the hypr style, a bit higher to leave room for the bar under the focused one
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

    // MARK: - Dms

    /// The pills of Dank Material Shell: round workspaces without names, on a track, and the focused one wider, with its
    /// name. The width follows the focus while the marker slides, like in the pills
    private static func dms(
        _ snapshot: MenuBarSnapshot,
        _ config: MenuBarConfig,
        _ focusAmount: (String) -> Double,
        _ measure: Measure,
    ) -> MenuBarLayout {
        typealias M = MenuBarMetrics
        let top = (M.height - M.dmsPill) / 2
        var cells: [Cell] = []
        var x = M.dmsTrackPadding
        for workspace in snapshot.workspaces {
            let focus = focusAmount(workspace.name)
            let wide = max(M.dmsFocusedWidth, measure(workspace.name, .dmsName).width + 2 * M.dmsNamePadding)
            let frame = CGRect(x: x, y: top, width: M.dmsPill + (wide - M.dmsPill) * focus, height: M.dmsPill)
            cells.append(cell(workspace, config, frame: frame, font: .dmsName, focus: focus, measure))
            x = frame.maxX + M.dmsSpacing
        }
        let width = cells.isEmpty ? 0 : x - M.dmsSpacing + M.dmsTrackPadding
        return MenuBarLayout(style: .dms, cornerRadius: M.dmsPill / 2, size: CGSize(width: width, height: M.height), cells: cells)
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
            case .chips, .dms:
                let width = start.width + (end.width - start.width) * progress
                let frame = CGRect(x: midX - width / 2, y: end.minY, width: width, height: end.height)
                marker = Marker(
                    frame: frame,
                    cornerRadius: cornerRadius,
                    isOutlined: false,
                    // The chip is at least as wide as it is tall, so one character always fits. The pill of dms is
                    // shorter: the smaller initial of the square
                    initial: mode.map { MenuBarLayout.initial(of: $0, style == .dms ? .modeInitial : .chipModeInitial, in: frame, measure) },
                )
            case .hypr:
                let side = mode == nil ? M.focusSquare : M.modeSquare
                let frame = CGRect(x: midX - side / 2, y: end.midY - side / 2, width: side, height: side)
                marker = Marker(
                    frame: frame,
                    cornerRadius: mode == nil ? M.focusSquareCornerRadius : M.modeSquareCornerRadius,
                    isOutlined: false,
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
                    isOutlined: false,
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
                    isOutlined: false,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .chipModeInitial, in: nameArea, measure) },
                )
            case .liquid:
                // The drop leads, and its trail follows it later: stretched in between, one round drop again at the end
                let trailProgress = pow(progress, 2.4)
                let trailMidX = start.midX + (end.midX - start.midX) * trailProgress
                let frame = CGRect(x: midX - M.liquidDrop / 2, y: end.midY - M.liquidDrop / 2, width: M.liquidDrop, height: M.liquidDrop)
                marker = Marker(
                    frame: frame,
                    cornerRadius: M.liquidDrop / 2,
                    isOutlined: false,
                    initial: mode.map { MenuBarLayout.initial(of: $0, .chipModeInitial, in: frame, measure) },
                    trail: abs(trailMidX - midX) < 0.5 ? nil : CGRect(
                        x: trailMidX - M.liquidTrail / 2,
                        y: end.midY - M.liquidTrail / 2,
                        width: M.liquidTrail,
                        height: M.liquidTrail,
                    ),
                )
        }
        if snapshot.isFocusedWorkspaceFullscreen, let frame = marker?.frame, let radius = marker?.cornerRadius {
            let halo = halo(around: frame, radius, slot: CGRect(x: midX - end.width / 2, y: end.minY, width: end.width, height: end.height))
            marker?.halo = halo
        }
    }

    /// The ring of a fullscreen window, a bit away from the marker and always inside of the item. In the underline
    /// theme the bar is too thin to go around: the ring goes around the name and its bar
    private func halo(around frame: CGRect, _ radius: CGFloat, slot: CGRect) -> Halo {
        typealias M = MenuBarMetrics
        if style == .underline {
            let ring = CGRect(x: slot.minX + 1, y: M.haloWidth, width: slot.width - 2, height: M.height - 2 * M.haloWidth)
            return Halo(frame: ring, cornerRadius: 4)
        }
        let outer = frame.insetBy(dx: -M.haloGap, dy: -M.haloGap)
        let minY = max(0, outer.minY)
        let maxY = min(M.height, outer.maxY)
        return Halo(frame: CGRect(x: outer.minX, y: minY, width: outer.width, height: maxY - minY), cornerRadius: radius + M.haloGap)
    }

    /// 'perMonitor': room and a line between the workspaces of two monitors (they are already in the order of the
    /// monitors), and a hollow marker on the workspaces that another monitor shows. The divider of hypr is bolder, and
    /// dms has none: the gap between its tracks is the divider
    private mutating func separateMonitors(_ snapshot: MenuBarSnapshot) {
        typealias M = MenuBarMetrics
        let (space, width, height) = switch style {
            case .hypr: (M.hyprSeparatorSpace, M.hyprSeparatorWidth, M.hyprSeparatorHeight)
            case .dms: (M.dmsTrackGap + 2 * M.dmsTrackPadding - M.dmsSpacing, 0, 0)
            default: (M.monitorSeparatorSpace, M.monitorSeparatorWidth, M.monitorSeparatorHeight)
        }
        let workspaces = Dictionary(snapshot.workspaces.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var shift: CGFloat = 0
        for index in cells.indices {
            let monitor = workspaces[cells[index].workspace]?.monitor
            if index > 0, monitor != workspaces[cells[index - 1].workspace]?.monitor {
                let previous = cells[index - 1].frame.maxX
                shift += space
                let next = cells[index].frame.minX + shift
                if style != .dms {
                    separators.append(CGRect(x: ((previous + next) / 2).rounded() - (width / 2).rounded(.down), y: (M.height - height) / 2, width: width, height: height))
                }
            }
            if shift > 0 { cells[index] = cells[index].offsetBy(dx: shift) }
        }
        size.width += shift
        for index in cells.indices {
            let cell = cells[index]
            cells[index].isVisibleElsewhere = cell.workspace != snapshot.focusedWorkspace && workspaces[cell.workspace]?.isVisible == true
        }
        visibleElsewhere = cells.filter(\.isVisibleElsewhere).map { restMarker($0.frame) }
    }

    /// The dms theme: a track behind the workspaces of each monitor ('perMonitor'), or behind all of them. It follows
    /// the pills while they make room for the marker
    private mutating func placeTracks(_ snapshot: MenuBarSnapshot, perMonitor: Bool) {
        typealias M = MenuBarMetrics
        let monitors = Dictionary(snapshot.workspaces.map { ($0.name, $0.monitor) }, uniquingKeysWith: { first, _ in first })
        var runs: [[CGRect]] = []
        for (index, cell) in cells.enumerated() {
            if index > 0, !perMonitor || monitors[cell.workspace] == monitors[cells[index - 1].workspace] {
                runs[runs.count - 1].append(cell.frame)
            } else {
                runs.append([cell.frame])
            }
        }
        tracks = runs.map { run in
            let minX = run.map(\.minX).min() ?? 0
            let maxX = run.map(\.maxX).max() ?? 0
            return CGRect(
                x: minX - M.dmsTrackPadding,
                y: (M.height - M.dmsTrackHeight) / 2,
                width: maxX - minX + 2 * M.dmsTrackPadding,
                height: M.dmsTrackHeight,
            )
        }
    }

    /// The shape of the marker of a theme around a workspace at rest, hollow: where another monitor shows it
    private func restMarker(_ slot: CGRect) -> Marker {
        typealias M = MenuBarMetrics
        func centered(_ side: CGFloat) -> CGRect { CGRect(x: slot.midX - side / 2, y: slot.midY - side / 2, width: side, height: side) }
        let (frame, radius): (CGRect, CGFloat) = switch style {
            case .chips: (slot, cornerRadius)
            case .dots, .dms: (slot.insetBy(dx: -2, dy: -2), slot.height / 2 + 2)
            // Around the name, which stays in sight
            case .hypr: (centered(M.hyprFrame), M.hyprFrameCornerRadius)
            case .underline:
                (CGRect(x: slot.midX - M.underlineWidth / 2, y: M.underlineTop - 0.75, width: M.underlineWidth, height: M.underlineHeight + 1.5), (M.underlineHeight + 1.5) / 2)
            case .liquid: (centered(M.liquidDrop), M.liquidDrop / 2)
        }
        return Marker(frame: frame, cornerRadius: radius, isOutlined: true)
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

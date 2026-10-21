import Common

/// The colors of the menu bar item, resolved for one menu bar. Pure: no AppKit
struct MenuBarPalette: Equatable, Sendable {
    /// The item is one color with different opacities, so it can be drawn as a template image:
    /// macOS picks black or white for the menu bar behind it, dims it on an inactive display, etc. That's what Aeromenu does
    var isTemplate: Bool
    /// The color of the menu bar text. The placeholders are drawn with it
    var base: Rgba
    var focused: Rgba
    /// nil: the name of the focused workspace is cut out of its background ('focused' is 'auto').
    /// Otherwise black or white, the one that has more contrast over the fixed 'focused' color
    var focusedName: Rgba?
    var occupiedName: Rgba
    var occupiedBackground: Rgba
    var emptyName: Rgba
    /// The focus marker while it shows the initial of the binding mode: 'accent', or the same as 'focused' if it is 'auto'
    var modeMarker: Rgba
    /// The initial of the binding mode. nil: it is cut out of the marker
    var modeInitial: Rgba?

    /// - Parameter needsColor: the marker shows the initial of the binding mode. See: MenuBarLayout.needsColor
    /// - Parameter allowsTemplate: false to get the colors of the menu bar text baked in, for an image that isn't
    ///   going to a menu bar
    static func resolve(
        _ config: MenuBarConfig,
        style: MenuBarLayout.Style,
        isDarkBar: Bool,
        systemAccent: Rgba,
        needsColor: Bool = false,
        allowsTemplate: Bool = true,
    ) -> MenuBarPalette {
        typealias M = MenuBarMetrics
        // The palette of [theme] gives the colors that are 'auto', in the variant of the menu bar
        let colors = config.colors.applying(config.palette, isDark: isDarkBar)
        // The marker of a binding mode only has a color of its own if 'accent' gives it one
        let isTemplate = allowsTemplate && Self.isTemplate(colors, needsColor: needsColor)
        // A template image is drawn in black: only its alpha channel matters
        let base: Rgba = isTemplate || !isDarkBar ? .black : .white
        func fixed(_ color: ConfigColor) -> Rgba? { color == .auto ? nil : color.resolve(auto: base, systemAccent: systemAccent) }

        // The names of the square style have no background to stand out from, so they aren't faded
        let nameOpacity = style == .square ? 1 : M.chipNameOpacity
        let occupiedName = fixed(colors.occupied) ?? base.opacity(nameOpacity)
        let accent = fixed(colors.accent)
        let focused = fixed(colors.focused) ?? base
        let focusedName = fixed(colors.focused)?.contrastingBlackOrWhite
        return MenuBarPalette(
            isTemplate: isTemplate,
            base: base,
            focused: focused,
            focusedName: focusedName,
            occupiedName: occupiedName,
            occupiedBackground: fixed(colors.occupied)?.opacity(M.chipColorOpacity) ?? base.opacity(M.chipOpacity),
            // Without dimming, an empty workspace only differs from an occupied one in its missing background
            emptyName: config.dimEmptyWorkspaces ? fixed(colors.empty) ?? base.opacity(M.emptyWorkspaceOpacity) : occupiedName,
            modeMarker: accent ?? focused,
            // White, like the system does over the accent color, unless the accent is too light for it
            modeInitial: accent.map { $0.luminance > 0.6 ? .black : .white } ?? focusedName,
        )
    }

    /// A template image doesn't depend on the menu bar behind it: macOS colors it
    static func isTemplate(_ colors: MenuBarColors, needsColor: Bool) -> Bool {
        !(needsColor && colors.accent != .auto) && colors.focused == .auto && colors.occupied == .auto && colors.empty == .auto
    }

    func nameColor(of cell: MenuBarLayout.Cell) -> Rgba { cell.isOccupied ? occupiedName : emptyName }
}

extension MenuBarLayout {
    /// The marker shows the initial of the binding mode, so it is drawn in the 'accent' color. See: MenuBarPalette.isTemplate
    var needsColor: Bool { marker?.initial != nil }
}

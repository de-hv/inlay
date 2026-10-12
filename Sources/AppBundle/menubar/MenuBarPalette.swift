import Common

/// The colors of the menu bar item, resolved for one menu bar. Pure: no AppKit
struct MenuBarPalette: Equatable, Sendable {
    /// The item is one color with different opacities, so it can be drawn as a template image:
    /// macOS picks black or white for the menu bar behind it, dims it on an inactive display, etc. That's what Aeromenu does
    var isTemplate: Bool
    /// The color of the menu bar text. The layout icon and the placeholders are drawn with it
    var base: Rgba
    var focused: Rgba
    /// nil: the name of the focused workspace is cut out of its background ('focused' is 'auto').
    /// Otherwise black or white, the one that has more contrast over the fixed 'focused' color
    var focusedName: Rgba?
    var occupiedName: Rgba
    var occupiedBackground: Rgba
    var emptyName: Rgba
    var accent: Rgba
    var accentName: Rgba

    /// - Parameter needsColor: something in the item can't be a template: the mode badge
    static func resolve(
        _ config: MenuBarConfig,
        style: MenuBarLayout.Style,
        isDarkBar: Bool,
        systemAccent: Rgba,
        needsColor: Bool = false,
    ) -> MenuBarPalette {
        typealias M = MenuBarMetrics
        let colors = config.colors
        let isTemplate = !needsColor && colors.focused == .auto && colors.occupied == .auto && colors.empty == .auto
        // A template image is drawn in black: only its alpha channel matters
        let base: Rgba = isTemplate || !isDarkBar ? .black : .white
        func fixed(_ color: ConfigColor) -> Rgba? { color == .auto ? nil : color.resolve(auto: base, systemAccent: systemAccent) }

        // The names of the square style have no background to stand out from, so they aren't faded
        let nameOpacity = style == .square ? 1 : M.chipNameOpacity
        let occupiedName = fixed(colors.occupied) ?? base.opacity(nameOpacity)
        let accent = colors.accent.resolve(auto: systemAccent, systemAccent: systemAccent)
        return MenuBarPalette(
            isTemplate: isTemplate,
            base: base,
            focused: fixed(colors.focused) ?? base,
            focusedName: fixed(colors.focused)?.contrastingBlackOrWhite,
            occupiedName: occupiedName,
            occupiedBackground: fixed(colors.occupied)?.opacity(M.chipColorOpacity) ?? base.opacity(M.chipOpacity),
            // Without dimming, an empty workspace only differs from an occupied one in its missing background
            emptyName: config.dimEmptyWorkspaces ? fixed(colors.empty) ?? base.opacity(M.emptyWorkspaceOpacity) : occupiedName,
            accent: accent,
            // White, like the system does over the accent color, unless the accent is too light for it
            accentName: accent.luminance > 0.6 ? .black : .white,
        )
    }

    func nameColor(of cell: MenuBarLayout.Cell) -> Rgba { cell.isOccupied ? occupiedName : emptyName }
}

extension MenuBarLayout {
    /// The mode badge has a color of its own. See: MenuBarPalette.isTemplate
    var needsColor: Bool { modeBadge != nil }
}

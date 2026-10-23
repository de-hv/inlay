import Common

/// The colors that the user wrote in the config, which win over the ones of the palette. See: ThemeColorSource
enum ManualColors {
    /// The keys of the colors that a palette gives, in the order of the settings window
    static let keys: [SettingsKey] = [
        .menuBarFocused, .menuBarOccupied, .menuBarEmpty, .menuBarAccent,
        .bordersActiveColor, .bordersInactiveColor, .bordersFloatingColor,
    ]

    /// The keys of the config whose color isn't the one of the palette
    static func keys(in config: Config) -> [SettingsKey] {
        let bar = config.menuBar.colors
        let borders = config.borders
        let defaults = BordersConfig()
        var result: [SettingsKey] = []
        if bar.focused != .auto { result.append(.menuBarFocused) }
        if bar.occupied != .auto { result.append(.menuBarOccupied) }
        if bar.empty != .auto { result.append(.menuBarEmpty) }
        if bar.accent != .auto { result.append(.menuBarAccent) }
        if borders.activeColor != defaults.activeColor { result.append(.bordersActiveColor) }
        if borders.inactiveColor != defaults.inactiveColor { result.append(.bordersInactiveColor) }
        if borders.floatingColor != defaults.floatingColor { result.append(.bordersFloatingColor) }
        return result
    }
}

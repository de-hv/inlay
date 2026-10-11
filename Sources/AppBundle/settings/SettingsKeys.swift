import Common

/// A key of the config that the settings window edits, and the value that applies when the key is omitted
struct SettingsKey: Hashable, Sendable {
    var path: TomlKeyPath
    var defaultValue: TomlValue

    init(_ table: [String], _ key: String, default defaultValue: TomlValue) {
        path = TomlKeyPath(table, key)
        self.defaultValue = defaultValue
    }

    /// The key as the window shows it next to its control: "[menu-bar] theme"
    var label: String {
        path.table.isEmpty ? path.key : "[\(path.table.joined(separator: "."))] \(path.key)"
    }

    static func == (lhs: SettingsKey, rhs: SettingsKey) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}

extension SettingsKey {
    // General
    static let startAtLogin = SettingsKey([], "start-at-login", default: .bool(false))
    static let autoReloadConfig = SettingsKey([], "auto-reload-config", default: .bool(false))
    static let newWindowPlacement = SettingsKey(["tiling"], "new-window-placement", default: .string(NewWindowPlacement.dwindle.rawValue))

    // Menu bar
    static let menuBarEnabled = SettingsKey(["menu-bar"], "enabled", default: .bool(true))
    static let menuBarTheme = SettingsKey(["menu-bar"], "theme", default: .string(MenuBarTheme.chips.rawValue))
    /// The real default depends on the theme. See: MenuBarConfig.effectiveShowAppIcons
    static let menuBarShowAppIcons = SettingsKey(["menu-bar"], "show-app-icons", default: .bool(false))
    static let menuBarDimEmpty = SettingsKey(["menu-bar"], "dim-empty-workspaces", default: .bool(true))
    static let menuBarShowMode = SettingsKey(["menu-bar"], "show-mode", default: .bool(false))
    static let menuBarAccent = SettingsKey(["menu-bar", "colors"], "accent", default: .string(ConfigColor.systemAccentLiteral))
    static let menuBarFocused = SettingsKey(["menu-bar", "colors"], "focused", default: .string(ConfigColor.autoLiteral))
    static let menuBarOccupied = SettingsKey(["menu-bar", "colors"], "occupied", default: .string(ConfigColor.autoLiteral))
    static let menuBarEmpty = SettingsKey(["menu-bar", "colors"], "empty", default: .string(ConfigColor.autoLiteral))

    // Borders. The defaults are the ones of BordersConfig
    static let bordersEnabled = SettingsKey(["borders"], "enabled", default: .bool(true))
    static let bordersWidth = SettingsKey(["borders"], "width", default: .int(4))
    static let bordersCornerRadius = SettingsKey(["borders"], "corner-radius", default: .int(16))
    static let bordersActiveColor = SettingsKey(["borders"], "active-color", default: .string(ConfigColor.systemAccentLiteral))
    static let bordersInactiveColor = SettingsKey(["borders"], "inactive-color", default: .string("#8E8E9373"))
    static let bordersFloatingColor = SettingsKey(["borders"], "floating-color", default: .string("#BF5AF2"))
}

/// What the settings window can show
enum SettingsFeatures {
    /// The Borders tab edits the [borders] table of the config. See: BordersConfig
    static let borders = true
}

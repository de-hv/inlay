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
    static let autoReloadConfig = SettingsKey([], "auto-reload-config", default: .bool(true))
    static let newWindowPlacement = SettingsKey(["tiling"], "new-window-placement", default: .string(NewWindowPlacement.dwindle.rawValue))
    static let startupLayout = SettingsKey(["tiling"], "startup-layout", default: .string(StartupLayout.grid.rawValue))
    static let splitTarget = SettingsKey(["tiling"], "split-target", default: .string(SplitTarget.focused.rawValue))
    static let minWindowSize = SettingsKey(["tiling"], "min-window-size", default: .int(100))
    /// A float: the window shows it in percent
    static let splitRatio = SettingsKey(["tiling"], "split-ratio", default: .float(0.5))
    static let persistentWorkspaces = SettingsKey([], persistentWorkspacesKey, default: .strings([]))
    static let settingsShowKeys = SettingsKey(["settings"], "show-keys", default: .bool(false))

    // Animations. The defaults are the ones of AnimationsConfig
    static let animationsEnabled = SettingsKey(["animations"], "enabled", default: .bool(true))
    static let animationsDuration = SettingsKey(["animations"], "duration", default: .int(160))
    static let animationsWorkspaceSwitch = SettingsKey(["animations"], "workspace-switch", default: .string(WorkspaceSwitch.horizontal.rawValue))

    // Menu bar
    static let menuBarEnabled = SettingsKey(["menu-bar"], "enabled", default: .bool(true))
    static let menuBarTheme = SettingsKey(["menu-bar"], "theme", default: .string(MenuBarTheme.liquid.rawValue))
    static let menuBarDimEmpty = SettingsKey(["menu-bar"], "dim-empty-workspaces", default: .bool(true))
    static let menuBarShowMode = SettingsKey(["menu-bar"], "show-mode", default: .bool(true))
    static let menuBarPerMonitor = SettingsKey(["menu-bar"], "per-monitor", default: .bool(false))
    static let menuBarAccent = SettingsKey(["menu-bar", "colors"], "accent", default: .string(ConfigColor.autoLiteral))
    static let menuBarFocused = SettingsKey(["menu-bar", "colors"], "focused", default: .string(ConfigColor.autoLiteral))
    static let menuBarOccupied = SettingsKey(["menu-bar", "colors"], "occupied", default: .string(ConfigColor.autoLiteral))
    static let menuBarEmpty = SettingsKey(["menu-bar", "colors"], "empty", default: .string(ConfigColor.autoLiteral))

    // Borders. The defaults are the ones of BordersConfig
    static let bordersEnabled = SettingsKey(["borders"], "enabled", default: .bool(true))
    static let bordersWidth = SettingsKey(["borders"], "width", default: .int(4))
    static let bordersCornerRadius = SettingsKey(["borders"], "corner-radius", default: .int(16))
    static let bordersSquareCorners = SettingsKey(["borders"], "square-corners", default: .bool(true))
    static let bordersActiveColor = SettingsKey(["borders"], "active-color", default: .string(ConfigColor.systemAccentLiteral))
    static let bordersInactiveColor = SettingsKey(["borders"], "inactive-color", default: .string("#8E8E9373"))
    static let bordersFloatingColor = SettingsKey(["borders"], "floating-color", default: .string("#BF5AF2"))
    static let bordersGlow = SettingsKey(["borders"], "glow", default: .bool(false))
    static let bordersGlowRadius = SettingsKey(["borders"], "glow-radius", default: .int(12))
    static let bordersSingleEnabled = SettingsKey(["borders", "single-window"], "enabled", default: .bool(true))
    static let bordersSingleWidth = SettingsKey(["borders", "single-window"], "width", default: .int(1))
    static let bordersSingleGap = SettingsKey(["borders", "single-window"], "gap", default: .int(2))

    // Gaps. The fallback of an omitted gap is 0. A gap per monitor (`[{ monitor.main = 16 }, 8]`) is defined by hand
    static let gapsInnerHorizontal = SettingsKey(["gaps", "inner"], "horizontal", default: .int(0))
    static let gapsInnerVertical = SettingsKey(["gaps", "inner"], "vertical", default: .int(0))
    static let gapsOuterTop = SettingsKey(["gaps", "outer"], "top", default: .int(0))
    static let gapsOuterBottom = SettingsKey(["gaps", "outer"], "bottom", default: .int(0))
    static let gapsOuterLeft = SettingsKey(["gaps", "outer"], "left", default: .int(0))
    static let gapsOuterRight = SettingsKey(["gaps", "outer"], "right", default: .int(0))

    /// [menu-bar.labels]: the name of the workspace in the 'labels' theme. No default: the name of the workspace
    static func menuBarLabel(_ workspace: String) -> SettingsKey {
        SettingsKey(["menu-bar", "labels"], workspace, default: .string(""))
    }

    /// [menu-bar.symbols]: the SF Symbol of the workspace in the 'labels' theme. No default: the name of the workspace
    static func menuBarSymbol(_ workspace: String) -> SettingsKey {
        SettingsKey(["menu-bar", "symbols"], workspace, default: .string(""))
    }

    /// Every key with a fixed name, for the export of a complete config. See: ConfigEditor.exportText
    static let all: [SettingsKey] = [
        startAtLogin, autoReloadConfig, persistentWorkspaces,
        newWindowPlacement, splitRatio, startupLayout, splitTarget, minWindowSize,
        menuBarEnabled, menuBarTheme, menuBarDimEmpty, menuBarShowMode, menuBarPerMonitor,
        menuBarAccent, menuBarFocused, menuBarOccupied, menuBarEmpty,
        animationsEnabled, animationsDuration, animationsWorkspaceSwitch,
        bordersEnabled, bordersWidth, bordersCornerRadius, bordersSquareCorners, bordersActiveColor, bordersInactiveColor,
        bordersFloatingColor, bordersGlow, bordersGlowRadius,
        bordersSingleEnabled, bordersSingleWidth, bordersSingleGap,
        gapsInnerHorizontal, gapsInnerVertical, gapsOuterTop, gapsOuterBottom, gapsOuterLeft, gapsOuterRight,
        settingsShowKeys,
    ]

    /// [borders.mode-colors]: the color of the border of the focused window while the binding mode is active.
    /// No default: a mode without a color keeps the normal colors
    static func bordersModeColor(_ mode: String) -> SettingsKey {
        SettingsKey(["borders", "mode-colors"], mode, default: .string(""))
    }
}

/// What the settings window can show
enum SettingsFeatures {
    /// The Borders tab edits the [borders] table of the config. See: BordersConfig
    static let borders = true
}

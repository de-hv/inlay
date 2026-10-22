import Common

/// [menu-bar] table of the config
struct MenuBarConfig: ConvenienceMutable, Equatable, Sendable {
    var enabled: Bool = true
    var theme: MenuBarTheme = .liquid
    var dimEmptyWorkspaces: Bool = true
    var showMode: Bool = true
    var colors: MenuBarColors = MenuBarColors()
    /// The workspaces grouped by the monitor they are on, and a hollow marker on the one that another monitor shows
    var perMonitor: Bool = false
    /// [menu-bar.labels]. Workspace -> the name that the 'labels' theme shows in the focused workspace. Only that theme uses it
    var labels: [String: String] = [:]
    /// [menu-bar.symbols]. Workspace -> the SF Symbol that the 'labels' theme draws for it. Only that theme uses it
    var symbols: [String: String] = [:]
    /// [theme] palette: it gives the colors that are 'auto'. Not a key of [menu-bar]: copied from the config. See: MenuBarStore
    var palette: ThemePalette = .system
    /// [theme] seed, as a color: the one that the 'material' palette is made from. Copied from the config too
    var paletteSeed: Rgba = MaterialPalette.baselineSeed

    /// 'show-app-icons' is a key of the past: it is accepted and ignored. See: parseObsoleteShowAppIcons
    var _showAppIcons: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value
}

enum MenuBarTheme: String, CaseIterable, Equatable, Sendable {
    /// Round workspaces, and the focused one stretched into a wider pill, like the workspace indicator of GNOME and of
    /// many Hyprland setups
    case pills
    /// The workspaces alone. The Chips style of Aeromenu
    case chips
    /// The Square style of Aeromenu without its layout icon: the names, and a square in place of the focused workspace
    case square
    /// Only the focused workspace
    case minimal
    /// A dot per workspace, without names, and the focused one stretched into a pill: the page indicator of iOS,
    /// that many waybar setups copy
    case dots
    /// The names, and a bar under the focused one that stretches towards the next one and catches up with it:
    /// the border-bottom of the workspaces of waybar
    case underline
    /// A ring for an empty workspace, a disc for one with windows and a target for the focused one: the Nerd Font
    /// icons of many waybar setups, drawn by Inlay
    case glyphs
    /// A dot per workspace, and a drop over the focused one that flows to the next one leaving a trail behind:
    /// the "gooey" effect of the bars made with eww, AGS or Quickshell
    case liquid
    /// An SF Symbol per workspace ([menu-bar.symbols]), and the focused one stretched into a pill with its symbol
    /// and its name ([menu-bar.labels]). A workspace without a symbol shows its name
    case labels
}

/// The theme that showed the icons of the apps in the item. Inlay doesn't have it anymore
private let obsoleteChipsIconsTheme = "chips-icons"

/// [menu-bar.colors] table of the config
struct MenuBarColors: ConvenienceMutable, Equatable, Sendable {
    /// The focus marker while it shows the initial of the binding mode ('show-mode'). 'auto': the same as 'focused'
    var accent: ConfigColor = .auto
    /// The background of the focused workspace
    var focused: ConfigColor = .auto
    /// The workspaces with windows
    var occupied: ConfigColor = .auto
    /// The workspaces without windows
    var empty: ConfigColor = .auto
}

let menuBarParserTable: [String: any ParserProtocol<MenuBarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "theme": Parser(\.theme, parseMenuBarTheme),
    "show-app-icons": Parser(\._showAppIcons, parseObsoleteShowAppIcons),
    "dim-empty-workspaces": Parser(\.dimEmptyWorkspaces, parseBool),
    "show-mode": Parser(\.showMode, parseBool),
    "colors": Parser(\.colors, parseMenuBarColors),
    "per-monitor": Parser(\.perMonitor, parseBool),
    "labels": Parser(\.labels, parseWorkspaceStrings),
    "symbols": Parser(\.symbols, parseWorkspaceStrings),
]

let menuBarColorsParserTable: [String: any ParserProtocol<MenuBarColors>] = [
    "accent": Parser(\.accent, parseConfigColor(allowAuto: true)),
    "focused": Parser(\.focused, parseConfigColor(allowAuto: true)),
    "occupied": Parser(\.occupied, parseConfigColor(allowAuto: true)),
    "empty": Parser(\.empty, parseConfigColor(allowAuto: true)),
]

func parseMenuBar(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> MenuBarConfig {
    parseTable(raw, MenuBarConfig(), menuBarParserTable, backtrace, &c)
}

private func parseMenuBarColors(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> MenuBarColors {
    parseTable(raw, MenuBarColors(), menuBarColorsParserTable, backtrace, &c)
}

/// [menu-bar.labels] and [menu-bar.symbols]: a string per workspace
private func parseWorkspaceStrings(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: String] {
    guard case .dict(let table) = raw else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return [:]
    }
    var result: [String: String] = [:]
    for (workspace, value) in table {
        if let string = parseString(value, backtrace + .key(workspace)).getOrNil(appendErrorTo: &c.errors), !string.isEmpty {
            result[workspace] = string
        }
    }
    return result
}

private func parseMenuBarTheme(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> MenuBarTheme {
    let theme = parseString(raw, backtrace)
        .flatMap { (raw: String) -> ResOrConfigParseDiagnostic<MenuBarTheme> in
            // Accepted so that a config written for a previous version of Inlay still loads. The settings window wrote it too
            if raw == obsoleteChipsIconsTheme {
                c.warnings.append(.init(backtrace, "The menu bar item doesn't show app icons anymore: '\(raw)' is treated as 'chips'. Please change it in the config"))
                return .success(.chips)
            }
            return MenuBarTheme(rawValue: raw)
                .toResult(.init(backtrace, "Can't parse menu bar theme '\(raw)'. Possible values: \(MenuBarTheme.unionLiteral)"))
        }
        .getOrNil(appendErrorTo: &c.errors)
    return theme ?? MenuBarConfig().theme
}

// Accepted so that a config written for a previous version of Inlay still loads. The settings window wrote the key too
private func parseObsoleteShowAppIcons(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) {
    if parseBool(raw, backtrace).getOrNil(appendErrorTo: &c.errors) != nil {
        c.warnings.append(.init(backtrace, "The menu bar item doesn't show app icons anymore: 'show-app-icons' is ignored. Please drop it from the config"))
    }
}

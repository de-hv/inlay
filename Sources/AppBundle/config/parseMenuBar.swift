import Common

/// [menu-bar] table of the config
struct MenuBarConfig: ConvenienceMutable, Equatable, Sendable {
    var enabled: Bool = true
    var theme: MenuBarTheme = .chips
    /// nil means that the theme decides. See: effectiveShowAppIcons
    var showAppIcons: Bool? = nil
    var dimEmptyWorkspaces: Bool = true
    var showMode: Bool = false
    var colors: MenuBarColors = MenuBarColors()

    var effectiveShowAppIcons: Bool { showAppIcons ?? theme.showsAppIconsByDefault }
}

enum MenuBarTheme: String, CaseIterable, Equatable, Sendable {
    /// The workspaces alone. The Chips style of Aeromenu
    case chips
    /// chips + the icons of the apps of every workspace
    case chipsIcons = "chips-icons"
    /// The Square style of Aeromenu: the layout icon, the names, and a square in place of the focused workspace
    case square
    /// Only the focused workspace
    case minimal

    var showsAppIconsByDefault: Bool { self == .chipsIcons }
}

/// [menu-bar.colors] table of the config
struct MenuBarColors: ConvenienceMutable, Equatable, Sendable {
    /// The mode badge
    var accent: ConfigColor = .systemAccent
    /// The background of the focused workspace
    var focused: ConfigColor = .auto
    /// The workspaces with windows
    var occupied: ConfigColor = .auto
    /// The workspaces without windows
    var empty: ConfigColor = .auto
}

private let menuBarParserTable: [String: any ParserProtocol<MenuBarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "theme": Parser(\.theme, parseMenuBarTheme),
    "show-app-icons": Parser(\.showAppIcons) { raw, backtrace in parseBool(raw, backtrace).map { $0 } },
    "dim-empty-workspaces": Parser(\.dimEmptyWorkspaces, parseBool),
    "show-mode": Parser(\.showMode, parseBool),
    "colors": Parser(\.colors, parseMenuBarColors),
]

private let menuBarColorsParserTable: [String: any ParserProtocol<MenuBarColors>] = [
    "accent": Parser(\.accent, parseConfigColor(allowAuto: false)),
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

private func parseMenuBarTheme(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<MenuBarTheme> {
    parseString(raw, backtrace).flatMap {
        MenuBarTheme(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse menu bar theme '\($0)'. Possible values: \(MenuBarTheme.unionLiteral)"))
    }
}

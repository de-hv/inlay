import Common
import Foundation

/// [theme] table of the config
struct ThemeConfig: ConvenienceMutable, Equatable, Sendable {
    /// The colors of the menu bar item and of the borders, from a palette of the Hyprland world
    var palette: ThemePalette = .oneDark
    /// The color that the 'material' palette is made from. The other palettes ignore it
    var seed: ThemeSeed = .color(.rgba(MaterialPalette.baselineSeed))
    /// The wallpaper of every palette that has none of its own in `wallpapers`. nil: switching palettes leaves the
    /// wallpaper alone. See: ThemeController
    var wallpaper: String? = nil
    /// [theme.wallpapers]: the name of a palette -> its wallpaper
    var wallpapers: [String: String] = [:]
    /// Shell commands that run when the colors change: another palette, the other variant (light or dark), or a new
    /// seed. They get the colors in INLAY_THEME_* variables. See: ThemeController
    var onChange: [String] = []

    /// The wallpaper of the palette: its own, or the one of every palette
    func wallpaper(of palette: ThemePalette) -> String? { wallpapers[palette.rawValue] ?? wallpaper }
}

/// The color that 'material' is made from
enum ThemeSeed: Equatable, Sendable, CustomStringConvertible {
    case color(ConfigColor)
    /// The main color of the wallpaper of the main screen. See: WallpaperSeed
    case wallpaper

    static let wallpaperLiteral = "wallpaper"

    var description: String {
        switch self {
            case .color(let color): color.description
            case .wallpaper: Self.wallpaperLiteral
        }
    }
}

/// A set of colors for the menu bar item and the borders, with a light and a dark variant: the one of the appearance of
/// the system applies. A palette only gives the colors that the config leaves at their default: a color written in
/// [menu-bar.colors] or in [borders] wins. See: MenuBarColors.applying, BordersConfig.applying
enum ThemePalette: String, CaseIterable, Equatable, Sendable {
    /// No palette: the colors of [menu-bar.colors] and [borders], or their defaults (the menu bar text, the accent color)
    case system
    case catppuccin
    case tokyoNight = "tokyo-night"
    case gruvbox
    case nord
    case rosePine = "rose-pine"
    case dracula
    case everforest
    case kanagawa
    case oxocarbon
    case ayu
    case oneDark = "one-dark"
    case mono
    /// Material You: made from a color, the seed. See: ThemeConfig.seed
    case material
    case flexoki

    var title: String {
        switch self {
            case .system: "System"
            case .catppuccin: "Catppuccin"
            case .tokyoNight: "Tokyo Night"
            case .gruvbox: "Gruvbox"
            case .nord: "Nord"
            case .rosePine: "Rosé Pine"
            case .dracula: "Dracula"
            case .everforest: "Everforest"
            case .kanagawa: "Kanagawa"
            case .oxocarbon: "Oxocarbon"
            case .ayu: "Ayu"
            case .oneDark: "One Dark"
            case .mono: "Mono"
            case .material: "Material You"
            case .flexoki: "Flexoki"
        }
    }

    /// The colors of the variant. nil for 'system'
    /// - Parameter seed: the color that 'material' is made from. See: ThemeConfig.seed
    func colors(isDark: Bool, seed: Rgba = MaterialPalette.baselineSeed) -> PaletteColors? {
        func c(_ hex: String) -> Rgba { Rgba(hex: hex).orDie("Bad color \(hex) of the palette \(rawValue)") }
        func p(_ f: String, _ o: String, _ e: String, _ a: String, _ inactive: String) -> PaletteColors {
            // The focused workspace and the border of the active window share the main color of the palette,
            // and the accent is also the border of the focused floating window
            PaletteColors(focused: c(f), occupied: c(o), empty: c(e), accent: c(a), activeBorder: c(f), inactiveBorder: c(inactive), floatingBorder: c(a))
        }
        return switch (self, isDark) {
            case (.system, _): nil
            // Mocha and Latte
            case (.catppuccin, true): p("#CBA6F7", "#CDD6F4", "#6C7086", "#F9E2AF", "#45475A")
            case (.catppuccin, false): p("#8839EF", "#4C4F69", "#9CA0B0", "#DF8E1D", "#BCC0CC")
            // Night and Day
            case (.tokyoNight, true): p("#7AA2F7", "#C0CAF5", "#565F89", "#BB9AF7", "#3B4261")
            case (.tokyoNight, false): p("#2E7DE9", "#3760BF", "#8990B3", "#9854F1", "#A8AECB")
            case (.gruvbox, true): p("#FABD2F", "#EBDBB2", "#7C6F64", "#83A598", "#504945")
            case (.gruvbox, false): p("#B57614", "#3C3836", "#A89984", "#076678", "#D5C4A1")
            case (.nord, true): p("#88C0D0", "#ECEFF4", "#616E88", "#B48EAD", "#4C566A")
            case (.nord, false): p("#5E81AC", "#2E3440", "#7B88A1", "#B48EAD", "#D8DEE9")
            // Main and Dawn
            case (.rosePine, true): p("#EBBCBA", "#E0DEF4", "#6E6A86", "#C4A7E7", "#403D52")
            case (.rosePine, false): p("#D7827E", "#575279", "#9893A5", "#907AA9", "#DFDAD9")
            // Dracula and Alucard
            case (.dracula, true): p("#BD93F9", "#F8F8F2", "#6272A4", "#FF79C6", "#44475A")
            case (.dracula, false): p("#644AC9", "#1F1F1F", "#6C6F93", "#A3144D", "#CFCFDE")
            case (.everforest, true): p("#A7C080", "#D3C6AA", "#7A8478", "#DBBC7F", "#475258")
            case (.everforest, false): p("#8DA101", "#5C6A72", "#939F91", "#DFA000", "#E6E2CC")
            // Wave and Lotus
            case (.kanagawa, true): p("#7E9CD8", "#DCD7BA", "#727169", "#FFA066", "#363646")
            case (.kanagawa, false): p("#4D699B", "#545464", "#A09CAC", "#CC6D00", "#D5CEA3")
            case (.oxocarbon, true): p("#EE5396", "#DDE1E6", "#6F6F6F", "#08BDBA", "#393939")
            case (.oxocarbon, false): p("#D02670", "#393939", "#A8A8A8", "#007D79", "#DDE1E6")
            // Mirage and Light
            case (.ayu, true): p("#FFCC66", "#CCCAC2", "#707A8C", "#73D0FF", "#3A4252")
            case (.ayu, false): p("#FA8D3E", "#5C6166", "#ADAEB1", "#399EE6", "#D8D8D7")
            // One Dark and One Light
            case (.oneDark, true): p("#61AFEF", "#ABB2BF", "#5C6370", "#E06C75", "#3E4451")
            case (.oneDark, false): p("#4078F2", "#383A42", "#A0A1A7", "#E45649", "#D3D3D5")
            // No hue at all: the binding mode stands out by its initial, not by its color
            case (.mono, true): p("#FFFFFF", "#A3A3A3", "#6B6B6B", "#BDBDBD", "#3A3A3A")
            case (.mono, false): p("#0A0A0A", "#525252", "#A3A3A3", "#6B6B6B", "#D4D4D4")
            case (.material, _): MaterialPalette.colors(seed: seed, isDark: isDark)
            case (.flexoki, true): p("#DA702C", "#CECDC3", "#6F6E69", "#4385BE", "#403E3C")
            case (.flexoki, false): p("#BC5215", "#403E3C", "#B7B5AC", "#205EA6", "#DAD8CE")
        }
    }
}

/// The colors of a variant of a palette
struct PaletteColors: Equatable, Sendable {
    /// [menu-bar.colors]
    var focused: Rgba
    var occupied: Rgba
    var empty: Rgba
    var accent: Rgba
    /// [borders]
    var activeBorder: Rgba
    var inactiveBorder: Rgba
    var floatingBorder: Rgba
}

extension ThemeConfig {
    /// The seed as a color: 'system-accent' is the accent color of the system, and 'wallpaper' the main color of the
    /// wallpaper (the baseline seed while it isn't known)
    func seedColor(systemAccent: Rgba, wallpaper: Rgba? = nil) -> Rgba {
        switch seed {
            case .color(let color): color.resolve(auto: MaterialPalette.baselineSeed, systemAccent: systemAccent).withAlpha(1)
            case .wallpaper: (wallpaper ?? MaterialPalette.baselineSeed).withAlpha(1)
        }
    }
}

let themeParserTable: [String: any ParserProtocol<ThemeConfig>] = [
    "palette": Parser(\.palette, parseThemePalette),
    "seed": Parser(\.seed, parseThemeSeed),
    "wallpaper": Parser(\.wallpaper, { raw, backtrace in parseString(raw, backtrace).map(Optional.some) }),
    "wallpapers": Parser(\.wallpapers, parseThemeWallpapers),
    "on-change": Parser(\.onChange, parseArrayOfStrings),
]

private func parseThemeSeed(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<ThemeSeed> {
    if raw.asStringOrNil == ThemeSeed.wallpaperLiteral { return .success(.wallpaper) }
    return parseConfigColor(allowAuto: false)(raw, backtrace)
        .map { .color($0) }
        .mapError { error in .init(backtrace, error.message + ", '\(ThemeSeed.wallpaperLiteral)'") }
}

/// The keys are the names of the palettes
private func parseThemeWallpapers(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: String] {
    guard case .dict(let table) = raw else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return [:]
    }
    var result: [String: String] = [:]
    for (palette, value) in table {
        guard ThemePalette(rawValue: palette) != nil else {
            c.errors.append(.init(backtrace + .key(palette), "Unknown palette '\(palette)'. Possible values: \(ThemePalette.unionLiteral)"))
            continue
        }
        if let path = parseString(value, backtrace + .key(palette)).getOrNil(appendErrorTo: &c.errors) { result[palette] = path }
    }
    return result
}

func parseTheme(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> ThemeConfig {
    parseTable(raw, ThemeConfig(), themeParserTable, backtrace, &c)
}

private func parseThemePalette(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<ThemePalette> {
    parseString(raw, backtrace).flatMap {
        ThemePalette(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse palette '\($0)'. Possible values: \(ThemePalette.unionLiteral)"))
    }
}

extension MenuBarColors {
    /// The colors that are 'auto' take the ones of the palette
    /// - Parameter seed: the color that 'material' is made from. See: ThemeConfig.seed
    func applying(_ palette: ThemePalette, seed: Rgba = MaterialPalette.baselineSeed, isDark: Bool) -> MenuBarColors {
        guard let colors = palette.colors(isDark: isDark, seed: seed) else { return self }
        func pick(_ color: ConfigColor, _ fallback: Rgba) -> ConfigColor { color == .auto ? .rgba(fallback) : color }
        return MenuBarColors(
            accent: pick(accent, colors.accent),
            focused: pick(focused, colors.focused),
            occupied: pick(occupied, colors.occupied),
            empty: pick(empty, colors.empty),
        )
    }
}

extension BordersConfig {
    /// The colors that are at their default take the ones of the palette
    /// - Parameter seed: the color that 'material' is made from. See: ThemeConfig.seed
    func applying(_ palette: ThemePalette, seed: Rgba = MaterialPalette.baselineSeed, isDark: Bool) -> BordersConfig {
        guard let colors = palette.colors(isDark: isDark, seed: seed) else { return self }
        let defaults = BordersConfig()
        var result = self
        if activeColor == defaults.activeColor { result.activeColor = .rgba(colors.activeBorder) }
        if inactiveColor == defaults.inactiveColor { result.inactiveColor = .rgba(colors.inactiveBorder) }
        if floatingColor == defaults.floatingColor { result.floatingColor = .rgba(colors.floatingBorder) }
        return result
    }
}

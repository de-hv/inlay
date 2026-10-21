import Common
import Foundation

/// [theme] table of the config
struct ThemeConfig: ConvenienceMutable, Equatable, Sendable {
    /// The colors of the menu bar item and of the borders, from a palette of the Hyprland world
    var palette: ThemePalette = .catppuccin
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
        }
    }

    /// The colors of the variant. nil for 'system'
    func colors(isDark: Bool) -> PaletteColors? {
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

let themeParserTable: [String: any ParserProtocol<ThemeConfig>] = [
    "palette": Parser(\.palette, parseThemePalette),
]

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
    func applying(_ palette: ThemePalette, isDark: Bool) -> MenuBarColors {
        guard let colors = palette.colors(isDark: isDark) else { return self }
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
    func applying(_ palette: ThemePalette, isDark: Bool) -> BordersConfig {
        guard let colors = palette.colors(isDark: isDark) else { return self }
        let defaults = BordersConfig()
        var result = self
        if activeColor == defaults.activeColor { result.activeColor = .rgba(colors.activeBorder) }
        if inactiveColor == defaults.inactiveColor { result.inactiveColor = .rgba(colors.inactiveBorder) }
        if floatingColor == defaults.floatingColor { result.floatingColor = .rgba(colors.floatingBorder) }
        return result
    }
}

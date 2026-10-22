import Common

/// [settings] table of the config: how the Settings window looks. It changes nothing else
struct SettingsWindowConfig: ConvenienceMutable, Equatable, Sendable {
    /// Every row shows the key of the config it writes. Without it, a key shows while the mouse is over its row,
    /// or while ⌥ is held
    var showKeys: Bool = false
}

let settingsWindowParserTable: [String: any ParserProtocol<SettingsWindowConfig>] = [
    "show-keys": Parser(\.showKeys, parseBool),
]

func parseSettingsWindow(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> SettingsWindowConfig {
    parseTable(raw, SettingsWindowConfig(), settingsWindowParserTable, backtrace, &c)
}

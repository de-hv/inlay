import Common

/// [notifications] table of the config
struct NotificationsConfig: ConvenienceMutable, Equatable, Sendable {
    /// The notice that tells that the config was reloaded. See: ReloadNoticePanel
    var onReload: ReloadNoticeStyle = .diff
}

/// What the notice says when the config is reloaded
enum ReloadNoticeStyle: String, CaseIterable, Equatable, Sendable {
    /// The name of the file, and the keys that changed with their old and new values
    case diff
    /// Only the name of the file
    case simple
    /// No notice
    case off
}

let notificationsParserTable: [String: any ParserProtocol<NotificationsConfig>] = [
    "on-reload": Parser(\.onReload, parseReloadNoticeStyle),
]

func parseNotifications(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> NotificationsConfig {
    parseTable(raw, NotificationsConfig(), notificationsParserTable, backtrace, &c)
}

private func parseReloadNoticeStyle(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<ReloadNoticeStyle> {
    parseString(raw, backtrace).flatMap {
        ReloadNoticeStyle(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse on-reload '\($0)'. Possible values: \(ReloadNoticeStyle.unionLiteral)"))
    }
}

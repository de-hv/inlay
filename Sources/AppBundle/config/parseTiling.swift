import Common
import Foundation

private let tilingParserTable: [String: any ParserProtocol<TilingConfig>] = [
    "new-window-placement": Parser(\.newWindowPlacement, parseNewWindowPlacement),
    "split-ratio": Parser(\.splitRatio, parseSplitRatio),
    "startup-layout": Parser(\.startupLayout, parseStartupLayout),
    "split-target": Parser(\.splitTarget, parseSplitTarget),
    "min-window-size": Parser(\.minWindowSize, parseMinWindowSize),
]

func parseTiling(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> TilingConfig {
    parseTable(raw, TilingConfig(), tilingParserTable, backtrace, &c)
}

private func parseNewWindowPlacement(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<NewWindowPlacement> {
    parseString(raw, backtrace).flatMap {
        NewWindowPlacement(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse new window placement '\($0)'. Possible values: \(NewWindowPlacement.unionLiteral)"))
    }
}

private func parseStartupLayout(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<StartupLayout> {
    parseString(raw, backtrace).flatMap {
        StartupLayout(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse startup layout '\($0)'. Possible values: \(StartupLayout.unionLiteral)"))
    }
}

private func parseSplitTarget(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<SplitTarget> {
    parseString(raw, backtrace).flatMap {
        SplitTarget(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse split target '\($0)'. Possible values: \(SplitTarget.unionLiteral)"))
    }
}

private func parseMinWindowSize(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<CGFloat> {
    let range = TilingConfig.minWindowSizeRange
    return parseInt(raw, backtrace)
        .filter(.init(backtrace, "min-window-size must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
        .map { CGFloat($0) }
}

private func parseSplitRatio(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<CGFloat> {
    let range = TilingConfig.splitRatioRange
    return raw.asDoubleOrNil
        .toResult(expectedActualTypeDiagnostic(expected: .float, actual: raw.tomlType, backtrace))
        .map { CGFloat($0) }
        .filter(.init(backtrace, "split-ratio must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
}

import Common
import Foundation

private let tilingParserTable: [String: any ParserProtocol<TilingConfig>] = [
    "new-window-placement": Parser(\.newWindowPlacement, parseNewWindowPlacement),
    "split-ratio": Parser(\.splitRatio, parseSplitRatio),
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

private func parseSplitRatio(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<CGFloat> {
    let range = TilingConfig.splitRatioRange
    return raw.asDoubleOrNil
        .toResult(expectedActualTypeDiagnostic(expected: .float, actual: raw.tomlType, backtrace))
        .map { CGFloat($0) }
        .filter(.init(backtrace, "split-ratio must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
}

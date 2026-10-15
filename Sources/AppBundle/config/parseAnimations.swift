import Common
import Foundation

/// [animations] table of the config. See: WindowAnimator
struct AnimationsConfig: ConvenienceMutable, Equatable, Sendable {
    /// The tiling windows slide to their new frames when a window opens or closes, and when a window is moved
    /// with 'swap' or 'move'. Nothing else is animated: resizing, switching workspaces, the mouse
    var enabled: Bool = true
    /// How long a window takes to get to its new frame, in milliseconds. 0: no animation
    var duration: Int = 180

    static let durationRange = 0 ... 500

    /// The duration in effect: 0 if the animations are off
    var effectiveDuration: Duration { enabled ? .milliseconds(duration) : .zero }
}

let animationsParserTable: [String: any ParserProtocol<AnimationsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "duration": Parser(\.duration, parseDuration),
]

func parseAnimations(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> AnimationsConfig {
    parseTable(raw, AnimationsConfig(), animationsParserTable, backtrace, &c)
}

private func parseDuration(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    let range = AnimationsConfig.durationRange
    return parseInt(raw, backtrace)
        .filter(.init(backtrace, "duration must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
}

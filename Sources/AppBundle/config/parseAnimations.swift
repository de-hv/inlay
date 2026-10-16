import Common
import Foundation

/// [animations] table of the config. See: WindowAnimator
struct AnimationsConfig: ConvenienceMutable, Equatable, Sendable {
    /// The tiling windows slide to their new frames when a window opens or closes, and when a window is moved
    /// with 'swap' or 'move'. Nothing else is animated: resizing, switching workspaces, the mouse
    var enabled: Bool = true
    /// How long a window takes to get to its new frame, in milliseconds. 0: no animation
    var duration: Int = 180
    /// How switching workspaces slides the windows. See: WorkspaceSlide
    var workspaceSwitch: WorkspaceSwitch = .horizontal

    static let durationRange = 0 ... 500

    /// The duration in effect: 0 if the animations are off
    var effectiveDuration: Duration { enabled ? .milliseconds(duration) : .zero }
}

let animationsParserTable: [String: any ParserProtocol<AnimationsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "duration": Parser(\.duration, parseDuration),
    "workspace-switch": Parser(\.workspaceSwitch, parseWorkspaceSwitch),
]

/// How switching workspaces slides the windows of the screen. They never cross another screen. See: WorkspaceSlide
enum WorkspaceSwitch: String, CaseIterable, Equatable, Sendable {
    /// Sideways on every screen: toward a later workspace to the left, toward an earlier one to the right.
    /// With a screen on one side, in and out by the other side
    case horizontal
    /// Through the bottom of every screen: out downwards, and in from below
    case vertical
    /// Sideways, or through the bottom on a screen with another screen on its left or on its right
    case auto
    /// No slide
    case off
}

/// A value of WorkspaceSwitch. `true` and `false`, what an earlier version wrote, are `horizontal` and `off`
private func parseWorkspaceSwitch(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<WorkspaceSwitch> {
    if let bool = raw.asBoolOrNil { return .success(bool ? .horizontal : .off) }
    return parseString(raw, backtrace).flatMap {
        WorkspaceSwitch(rawValue: $0)
            .toResult(.init(backtrace, "Can't parse workspace-switch '\($0)'. Possible values: \(WorkspaceSwitch.unionLiteral)"))
    }
}

func parseAnimations(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> AnimationsConfig {
    parseTable(raw, AnimationsConfig(), animationsParserTable, backtrace, &c)
}

private func parseDuration(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    let range = AnimationsConfig.durationRange
    return parseInt(raw, backtrace)
        .filter(.init(backtrace, "duration must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
}

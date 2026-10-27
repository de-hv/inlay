import Common
import Foundation

/// [animations] table of the config. See: WindowAnimator
struct AnimationsConfig: ConvenienceMutable, Equatable, Sendable {
    /// The tiling windows slide to their new frames when a window opens or closes, when a window is moved
    /// with 'swap' or 'move', and in and out of fullscreen. Switching workspaces has its own slide (workspaceSwitch).
    /// Nothing else is animated: resizing, the mouse
    var enabled: Bool = true
    /// How long a window takes to get to its new frame, in milliseconds. 0: no animation
    var duration: Int = 160
    /// How switching workspaces slides the windows. See: WorkspaceSlide
    var workspaceSwitch: WorkspaceSwitch = .horizontal
    /// The name of the timing curve of every animation: one of AnimationCurve.presets or of `curves`
    var curve: String = "quint"
    /// [animations.curves]: name -> curve. The curves of the user, by name, on top of the presets
    var curves: [String: AnimationCurve] = [:]
    /// The curve and the duration of each kind of animation, when they aren't the ones of `curve` and `duration`.
    /// The defaults only hold while the config sets neither `curve` nor `duration`: see parseAnimations
    var open: AnimationStep = AnimationStep(curve: "quint", duration: 200)
    var move: AnimationStep = AnimationStep(curve: "quint", duration: 160)
    var fullscreen: AnimationStep = AnimationStep(curve: "expo", duration: 220)
    var workspace: AnimationStep = AnimationStep(curve: "expo", duration: 140)

    static let durationRange = 0 ... 500

    /// The duration in effect: 0 if the animations are off
    var effectiveDuration: Duration { enabled ? .milliseconds(duration) : .zero }

    func step(_ kind: AnimationKind) -> AnimationStep {
        switch kind {
            case .open: open
            case .move: move
            case .fullscreen: fullscreen
            case .workspace: workspace
        }
    }

    mutating func setStep(_ kind: AnimationKind, _ step: AnimationStep) {
        switch kind {
            case .open: open = step
            case .move: move = step
            case .fullscreen: fullscreen = step
            case .workspace: workspace = step
        }
    }

    /// The duration of that kind of animation: its own, or `duration`. 0 if the animations are off
    func effectiveDuration(_ kind: AnimationKind) -> Duration {
        enabled ? .milliseconds(step(kind).duration ?? duration) : .zero
    }

    /// The curve of that kind of animation: its own, or `curve`. A name that isn't a curve is an error of the config,
    /// so it doesn't get here; ease-out just in case
    func effectiveCurve(_ kind: AnimationKind) -> AnimationCurve {
        let name = step(kind).curve ?? curve
        return curves[name] ?? AnimationCurve.presets[name] ?? .easeOut
    }
}

/// What makes the windows move. See: WindowAnimator.setFrame
enum AnimationKind: String, CaseIterable, Sendable {
    /// A new window grows from the center of its tile
    case open
    /// The windows make room for a new one, take the space of one that closed, or are moved with 'swap' or 'move'
    case move
    /// The 'fullscreen' command, in and out
    case fullscreen
    /// Switching workspaces: the windows slide out and in
    case workspace
}

/// The curve and the duration of a kind of animation. nil: the ones of the [animations] table
struct AnimationStep: ConvenienceMutable, Equatable, Sendable {
    var curve: String? = nil
    var duration: Int? = nil
}

let animationsParserTable: [String: any ParserProtocol<AnimationsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "duration": Parser(\.duration, parseDuration),
    "workspace-switch": Parser(\.workspaceSwitch, parseWorkspaceSwitch),
    "curve": Parser(\.curve, parseString),
    "curves": Parser(\.curves, parseCurves),
    "open": Parser(\.open, parseStep),
    "move": Parser(\.move, parseStep),
    "fullscreen": Parser(\.fullscreen, parseStep),
    "workspace": Parser(\.workspace, parseStep),
]

let animationStepParserTable: [String: any ParserProtocol<AnimationStep>] = [
    "curve": Parser(\.curve, { raw, backtrace in parseString(raw, backtrace).map(Optional.some) }),
    "duration": Parser(\.duration, { raw, backtrace in parseDuration(raw, backtrace).map(Optional.some) }),
]

private func parseStep(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> AnimationStep {
    parseTable(raw, AnimationStep(), animationStepParserTable, backtrace, &c)
}

/// name = [x1, y1, x2, y2]. X1 and X2 must be in 0 ... 1, so that the time only goes forward. Y1 and Y2 can overshoot
private func parseCurves(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: AnimationCurve] {
    guard case .dict(let table) = raw else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return [:]
    }
    var result: [String: AnimationCurve] = [:]
    for (name, value) in table {
        let numbers = value.asArrayOrNil?.compactMap(\.asDoubleOrNil) ?? []
        guard value.asArrayOrNil?.count == 4, numbers.count == 4 else {
            c.errors.append(.init(backtrace + .key(name), "A curve is four numbers: [x1, y1, x2, y2]"))
            continue
        }
        guard (0 ... 1).contains(numbers[0]), (0 ... 1).contains(numbers[2]) else {
            c.errors.append(.init(backtrace + .key(name), "x1 and x2 of a curve must be in [0, 1] range"))
            continue
        }
        result[name] = AnimationCurve(x1: numbers[0], y1: numbers[1], x2: numbers[2], y2: numbers[3])
    }
    return result
}

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
    var result = parseTable(raw, AnimationsConfig(), animationsParserTable, backtrace, &c)
    // A config that sets `curve` or `duration` gets them for every kind of animation it doesn't set on its own:
    // `duration = 0` turns them all off, whatever the defaults of each kind
    if case .dict(let table) = raw {
        for kind in AnimationKind.allCases where table[kind.rawValue] == nil {
            var step = result.step(kind)
            if table["curve"] != nil { step.curve = nil }
            if table["duration"] != nil { step.duration = nil }
            result.setStep(kind, step)
        }
    }
    // The names are checked once the whole table is read: [animations.curves] can come after the keys that use it
    let names = Set(AnimationCurve.presets.keys).union(result.curves.keys)
    let possible = names.sorted().joined(separator: ", ")
    var uses: [(ConfigBacktrace, String)] = [(backtrace + .key("curve"), result.curve)]
    for kind in AnimationKind.allCases {
        if let name = result.step(kind).curve { uses.append((backtrace + .key(kind.rawValue) + .key("curve"), name)) }
    }
    for (place, name) in uses where !names.contains(name) {
        c.errors.append(.init(place, "Unknown curve '\(name)'. Possible values: \(possible), or a curve of [animations.curves]"))
    }
    return result
}

private func parseDuration(_ raw: OrderedJson, _ backtrace: ConfigBacktrace) -> ResOrConfigParseDiagnostic<Int> {
    let range = AnimationsConfig.durationRange
    return parseInt(raw, backtrace)
        .filter(.init(backtrace, "duration must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
}

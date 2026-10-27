import Common
import Foundation

/// [borders] table of the config
struct BordersConfig: ConvenienceMutable, Equatable, Sendable {
    var enabled: Bool = true
    /// The thickness of the border, in points. The border is drawn outside of the frame of the window
    var width: CGFloat = 4
    /// The radius of the inner edge of the border, in points. It's meant to match the corners of the windows
    var cornerRadius: CGFloat = 16
    /// The border fills the rounded corners of the windows, which then look square. false: the border follows the corners
    var squareCorners: Bool = true
    /// The focused tiling window
    var activeColor: ConfigColor = .systemAccent
    /// Every window that isn't focused
    var inactiveColor: ConfigColor = .rgba(Rgba(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255, alpha: 0x73 / 255))
    /// The focused floating window
    var floatingColor: ConfigColor = .rgba(Rgba(red: 0xBF / 255, green: 0x5A / 255, blue: 0xF2 / 255))
    /// [borders.mode-colors]. Binding mode -> the color of the focused window while the mode is active
    var modeColors: [String: ConfigColor] = [:]
    /// A soft halo of the color of the border around the focused window, outside of the border
    var glow: Bool = false
    /// The blur radius of the glow, in points: about how far from the border the glow reaches
    var glowRadius: CGFloat = 12
    /// [borders.single-window]. The tiling window alone in its workspace, and the fullscreen window
    var singleWindow: SingleWindowBorder = SingleWindowBorder()
    /// 'hide-when-single' is a key of the past: see [borders.single-window]
    var _hideWhenSingle: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value

    static let widthRange = 1 ... 20
    static let cornerRadiusRange = 0 ... 40
    static let glowRadiusRange = 1 ... 40
}

let bordersParserTable: [String: any ParserProtocol<BordersConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width, parsePoints("width", BordersConfig.widthRange)),
    "corner-radius": Parser(\.cornerRadius, parsePoints("corner-radius", BordersConfig.cornerRadiusRange)),
    "square-corners": Parser(\.squareCorners, parseBool),
    "active-color": Parser(\.activeColor, parseConfigColor(allowAuto: false)),
    "inactive-color": Parser(\.inactiveColor, parseConfigColor(allowAuto: false)),
    "floating-color": Parser(\.floatingColor, parseConfigColor(allowAuto: false)),
    "mode-colors": Parser(\.modeColors, parseModeColors),
    "glow": Parser(\.glow, parseBool),
    "glow-radius": Parser(\.glowRadius, parsePoints("glow-radius", BordersConfig.glowRadiusRange)),
    "single-window": Parser(\.singleWindow, parseSingleWindowBorder),
    "hide-when-single": Parser(\._hideWhenSingle, parseObsolete("'hide-when-single' is gone: [borders.single-window] enabled = false leaves a window alone in its workspace without a border")),
]

/// [borders.single-window] table of the config: the tiling window alone in its workspace, and the window in fullscreen
/// (the 'fullscreen' command), look the same. With a border, they keep a gap around them, from the edges of the screen;
/// without it, they fill the screen
struct SingleWindowBorder: ConvenienceMutable, Equatable, Sendable {
    var enabled: Bool = true
    /// The width of the border, in points
    var width: CGFloat = 1
    /// The room around the window, in points: between the window and the edges of the visible part of the screen
    var gap: CGFloat = 2

    /// The gap is never narrower than the border: the edge of the screen would cut it
    var effectiveGap: CGFloat { max(gap, width) }

    static let gapRange = 0 ... 40
}

let singleWindowBorderParserTable: [String: any ParserProtocol<SingleWindowBorder>] = [
    "enabled": Parser(\.enabled, parseBool),
    "width": Parser(\.width, parsePoints("width", BordersConfig.widthRange)),
    "gap": Parser(\.gap, parsePoints("gap", SingleWindowBorder.gapRange)),
]

private func parseSingleWindowBorder(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> SingleWindowBorder {
    parseTable(raw, SingleWindowBorder(), singleWindowBorderParserTable, backtrace, &c)
}

func parseBorders(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> BordersConfig {
    parseTable(raw, BordersConfig(), bordersParserTable, backtrace, &c)
}

private func parsePoints(_ key: String, _ range: ClosedRange<Int>) -> @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<CGFloat> {
    { raw, backtrace in
        parseInt(raw, backtrace)
            .filter(.init(backtrace, "\(key) must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
            .map { CGFloat($0) }
    }
}

/// The keys are the names of the binding modes. A mode that doesn't exist is harmless: its color is never used
private func parseModeColors(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> [String: ConfigColor] {
    guard case .dict(let table) = raw else {
        c.errors.append(expectedActualTypeDiagnostic(expected: .table, actual: raw.tomlType, backtrace))
        return [:]
    }
    var result: [String: ConfigColor] = [:]
    for (mode, value) in table {
        if let color = parseConfigColor(allowAuto: false)(value, backtrace + .key(mode)).getOrNil(appendErrorTo: &c.errors) {
            result[mode] = color
        }
    }
    return result
}

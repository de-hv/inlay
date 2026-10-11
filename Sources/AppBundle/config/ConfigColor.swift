import AppKit
import Common

/// A color of the config file: '#RRGGBB', '#RRGGBBAA', 'system-accent' and, in the keys that allow it, 'auto'.
///
/// Used by [menu-bar.colors]. Meant to be reused by every other table that has colors
enum ConfigColor: Equatable, Sendable, CustomStringConvertible {
    /// The color is picked by the place it is used in. In the menu bar: the color of the menu bar text
    case auto
    /// System Settings -> Appearance -> Accent color
    case systemAccent
    case rgba(Rgba)

    static let autoLiteral = "auto"
    static let systemAccentLiteral = "system-accent"

    static func parse(_ raw: String, allowAuto: Bool) -> ResOrStr<ConfigColor> {
        switch raw {
            case systemAccentLiteral: return .success(.systemAccent)
            case autoLiteral where allowAuto: return .success(.auto)
            default:
                if let rgba = Rgba(hex: raw) { return .success(.rgba(rgba)) }
                let expected = ["'#RRGGBB'", "'#RRGGBBAA'", "'\(systemAccentLiteral)'"] + (allowAuto ? ["'\(autoLiteral)'"] : [])
                return .failure("Can't parse color '\(raw)'. Expected: \(expected.joined(separator: ", "))")
        }
    }

    /// The value as it is written in the config. `parse` of it gives the same color back
    var description: String {
        switch self {
            case .auto: ConfigColor.autoLiteral
            case .systemAccent: ConfigColor.systemAccentLiteral
            case .rgba(let rgba): rgba.hex
        }
    }

    /// - Parameter auto: what 'auto' means in the place the color is used in
    func resolve(auto: Rgba, systemAccent: Rgba) -> Rgba {
        switch self {
            case .auto: auto
            case .systemAccent: systemAccent
            case .rgba(let rgba): rgba
        }
    }
}

/// sRGB color. The components are in 0...1 range
struct Rgba: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    static let black = Rgba(red: 0, green: 0, blue: 0)
    static let white = Rgba(red: 1, green: 1, blue: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// '#RRGGBB' or '#RRGGBBAA'. The case of the digits doesn't matter
    init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(digits, radix: 16) else { return nil }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(
            red: Double(rgba >> 24 & 0xFF) / 255,
            green: Double(rgba >> 16 & 0xFF) / 255,
            blue: Double(rgba >> 8 & 0xFF) / 255,
            alpha: Double(rgba & 0xFF) / 255,
        )
    }

    /// '#RRGGBB', or '#RRGGBBAA' if the color isn't opaque
    var hex: String {
        func byte(_ component: Double) -> String {
            let hex = String(Int((min(max(component, 0), 1) * 255).rounded()), radix: 16, uppercase: true)
            return hex.count == 1 ? "0" + hex : hex
        }
        return "#" + byte(red) + byte(green) + byte(blue) + (byte(alpha) == "FF" ? "" : byte(alpha))
    }

    func withAlpha(_ alpha: Double) -> Rgba { Rgba(red: red, green: green, blue: blue, alpha: alpha) }

    /// The alpha of the color is multiplied by `opacity`
    func opacity(_ opacity: Double) -> Rgba { withAlpha(alpha * opacity) }

    /// WCAG relative luminance, ignoring the alpha
    var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Black or white, the one with more contrast (WCAG contrast ratio) over this color
    var contrastingBlackOrWhite: Rgba {
        let withWhite = 1.05 / (luminance + 0.05)
        let withBlack = (luminance + 0.05) / 0.05
        return withBlack >= withWhite ? .black : .white
    }

    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
    var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? .black
        self.init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent)
    }

    @MainActor static var systemAccent: Rgba { Rgba(NSColor.controlAccentColor) }
}

func parseConfigColor(allowAuto: Bool) -> @Sendable (OrderedJson, ConfigBacktrace) -> ResOrConfigParseDiagnostic<ConfigColor> {
    { raw, backtrace in
        parseString(raw, backtrace).flatMap { ConfigColor.parse($0, allowAuto: allowAuto).toParsedConfig(backtrace) }
    }
}

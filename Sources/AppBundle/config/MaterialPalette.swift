import Common
import Foundation

/// The 'material' palette: Material You made from a seed color, the way matugen makes it from a wallpaper.
///
/// Material picks its colors by tone, which is the lightness L* of CIELAB, keeping the hue of the seed. This is
/// an approximation of its tonal spot scheme in CIELAB (Material works in CAM16): the hues and the chromas are
/// close to the ones of Material, not equal. The baseline seed gives the exact colors of the Material 3 baseline
enum MaterialPalette {
    /// The seed of the Material 3 baseline (the purple of its documentation)
    static let baselineSeed = Rgba(hex: "#6750A4").orDie()

    static func colors(seed: Rgba, isDark: Bool) -> PaletteColors {
        func c(_ hex: String) -> Rgba { Rgba(hex: hex).orDie() }
        if seed.hex == baselineSeed.hex {
            return isDark
                ? palette(primary: c("#D0BCFF"), occupied: c("#CAC4D0"), empty: c("#938F99"), tertiary: c("#EFB8C8"), inactive: c("#49454F"))
                : palette(primary: c("#6750A4"), occupied: c("#49454F"), empty: c("#79747E"), tertiary: c("#7D5260"), inactive: c("#CAC4D0"))
        }
        let hue = Lch(seed).hue
        func primary(_ tone: Double) -> Rgba { Lch(lightness: tone, chroma: primaryChroma, hue: hue).rgba }
        func tertiary(_ tone: Double) -> Rgba { Lch(lightness: tone, chroma: tertiaryChroma, hue: hue + 60).rgba }
        func neutral(_ tone: Double) -> Rgba { Lch(lightness: tone, chroma: neutralChroma, hue: hue).rgba }
        // The roles of the dark and of the light scheme of Material: primary, on-surface-variant, outline, tertiary,
        // outline-variant
        return isDark
            ? palette(primary: primary(80), occupied: neutral(80), empty: neutral(60), tertiary: tertiary(80), inactive: neutral(30))
            : palette(primary: primary(40), occupied: neutral(30), empty: neutral(50), tertiary: tertiary(40), inactive: neutral(80))
    }

    /// The chromas of the tonal spot scheme, in CIELAB
    private static let primaryChroma: Double = 44
    private static let tertiaryChroma: Double = 28
    private static let neutralChroma: Double = 8

    private static func palette(primary: Rgba, occupied: Rgba, empty: Rgba, tertiary: Rgba, inactive: Rgba) -> PaletteColors {
        PaletteColors(focused: primary, occupied: occupied, empty: empty, accent: tertiary, activeBorder: primary, inactiveBorder: inactive, floatingBorder: tertiary)
    }
}

/// CIELAB in polar coordinates, with the white of D65
struct Lch: Equatable {
    var lightness: Double
    var chroma: Double
    /// In degrees
    var hue: Double

    init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = hue
    }

    init(_ rgba: Rgba) {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (linear(rgba.red), linear(rgba.green), linear(rgba.blue))
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / Self.white.x
        let y = (0.2126 * r + 0.7152 * g + 0.0722 * b) / Self.white.y
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / Self.white.z
        func f(_ t: Double) -> Double { t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116 }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        let a = 500 * (fx - fy)
        let bb = 200 * (fy - fz)
        lightness = 116 * fy - 16
        chroma = (a * a + bb * bb).squareRoot()
        let degrees = atan2(bb, a) * 180 / .pi
        hue = degrees < 0 ? degrees + 360 : degrees
    }

    /// The color in sRGB. A chroma that sRGB can't show is lowered until it can, keeping the lightness and the hue
    var rgba: Rgba {
        if let rgba = srgb(chroma: chroma) { return rgba }
        var low: Double = 0
        var high = chroma
        for _ in 0 ..< 24 {
            let middle = (low + high) / 2
            if srgb(chroma: middle) != nil { low = middle } else { high = middle }
        }
        return srgb(chroma: low) ?? .black
    }

    private static let white = (x: 0.95047, y: 1.0, z: 1.08883)

    private func srgb(chroma: Double) -> Rgba? {
        let radians = hue * .pi / 180
        let fy = (lightness + 16) / 116
        let fx = fy + chroma * cos(radians) / 500
        let fz = fy - chroma * sin(radians) / 200
        func inverse(_ t: Double) -> Double { t * t * t > 216.0 / 24389 ? t * t * t : (116 * t - 16) / (24389.0 / 27) }
        let x = inverse(fx) * Self.white.x
        let y = inverse(fy) * Self.white.y
        let z = inverse(fz) * Self.white.z
        let linear = [
            3.2406 * x - 1.5372 * y - 0.4986 * z,
            -0.9689 * x + 1.8758 * y + 0.0415 * z,
            0.0557 * x - 0.2040 * y + 1.0570 * z,
        ]
        let tolerance = 1e-4
        guard linear.allSatisfy({ $0 >= -tolerance && $0 <= 1 + tolerance }) else { return nil }
        func gamma(_ v: Double) -> Double {
            let v = min(max(v, 0), 1)
            return v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
        }
        return Rgba(red: gamma(linear[0]), green: gamma(linear[1]), blue: gamma(linear[2]))
    }
}

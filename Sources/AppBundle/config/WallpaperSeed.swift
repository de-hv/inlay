import AppKit
import Common
import ImageIO

/// The main color of the wallpaper of the main screen: the seed of 'material' with `[theme] seed = 'wallpaper'`,
/// like matugen does on Linux. See: ThemeConfig.seedColor
///
/// It is worked out only when the wallpaper may have changed, never on a timer: when the config is loaded, when the
/// store of the wallpapers of macOS is written (System Settings, or Inlay itself), when the screens change and on wake.
/// Each time it reads a thumbnail of 64x64 points of the image: a few milliseconds
@MainActor
final class WallpaperSeed {
    static let shared = WallpaperSeed()

    /// nil: not known (not asked for, or a wallpaper that isn't an image, like the Aerial videos)
    private(set) var color: Rgba? = nil
    private var watcher: FileWatcher? = nil
    private var observers: [any NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>? = nil

    /// Where macOS 14 and later keep the wallpaper of every screen and space
    private static var storeUrl: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }

    private init() {}

    /// Called after every load of the config: it only watches the wallpaper while the config asks for it
    func sync() {
        let wanted = config.theme.seed == .wallpaper && !isUnitTest
        if !wanted {
            stop()
            return
        }
        if watcher == nil {
            // macOS writes the store in several steps, and applies the new wallpaper right after: one read once it settles
            watcher = FileWatcher(url: Self.storeUrl) { [weak self] in self?.refreshSoon() }
            let center = NSWorkspace.shared.notificationCenter
            observers = [
                center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                },
                NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.refresh() }
                },
            ]
        }
        refresh()
    }

    private func refreshSoon() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            self?.refresh()
        }
    }

    private func stop() {
        debounceTask?.cancel()
        watcher?.cancel()
        watcher = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        color = nil
    }

    /// Reads the wallpaper again. The menu bar item and the borders follow a new color
    func refresh() {
        DebugStats.count("wallpaper-seed.refresh")
        watcher?.arm() // The store may have been replaced by a new file
        guard let screen = NSScreen.screens.first,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let pixels = Self.thumbnailPixels(url)
        else {
            update(nil)
            return
        }
        update(Self.dominantColor(pixels))
    }

    private func update(_ new: Rgba?) {
        if new == color { return }
        color = new
        DebugStats.count("wallpaper-seed.changed")
        publishUiState()
    }

    /// The pixels of a small version of the image, as (red, green, blue) from 0 to 1. nil if it isn't an image
    nonisolated static func thumbnailPixels(_ url: URL, size: Int = 64) -> [(Double, Double, Double)]? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue,
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return stride(from: 0, to: bytes.count, by: 4).map { (Double(bytes[$0]) / 255, Double(bytes[$0 + 1]) / 255, Double(bytes[$0 + 2]) / 255) }
    }

    /// The main color of an image: the hue that covers the most of it, weighted by how colorful each pixel is, as the
    /// average of its pixels. Grays and near blacks and whites don't count, unless the image is only that. Pure
    nonisolated static func dominantColor(_ pixels: [(Double, Double, Double)]) -> Rgba? {
        if pixels.isEmpty { return nil }
        let bins = 24
        var score = [Double](repeating: 0, count: bins)
        var sums = [(Double, Double, Double, Double)](repeating: (0, 0, 0, 0), count: bins)
        for (r, g, b) in pixels {
            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            let chroma = maxC - minC
            let saturation = maxC == 0 ? 0 : chroma / maxC
            if saturation < 0.2 || maxC < 0.2 { continue }
            var hue: Double = switch maxC {
                case r: (g - b) / chroma
                case g: (b - r) / chroma + 2
                default: (r - g) / chroma + 4
            }
            hue = (hue / 6).truncatingRemainder(dividingBy: 1)
            if hue < 0 { hue += 1 }
            let bin = min(Int(hue * Double(bins)), bins - 1)
            let weight = saturation * maxC
            score[bin] += weight
            sums[bin] = (sums[bin].0 + r * weight, sums[bin].1 + g * weight, sums[bin].2 + b * weight, sums[bin].3 + weight)
        }
        if let best = score.indices.max(by: { score[$0] < score[$1] }), score[best] > 0 {
            let sum = sums[best]
            return Rgba(red: sum.0 / sum.3, green: sum.1 / sum.3, blue: sum.2 / sum.3)
        }
        // Nothing colorful: the average
        let count = Double(pixels.count)
        return Rgba(
            red: pixels.reduce(0) { $0 + $1.0 } / count,
            green: pixels.reduce(0) { $0 + $1.1 } / count,
            blue: pixels.reduce(0) { $0 + $1.2 } / count,
        )
    }
}

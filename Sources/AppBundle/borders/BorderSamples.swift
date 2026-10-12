import AppKit
import Common

let renderBordersFlag = "--render-borders"
let debugBordersFlag = "--debug-borders"

extension BorderPanel {
    /// Draws the layer of the border, the very one that is shown on the screen, into the context.
    /// The origin of the context must be the origin of the panel
    func render(in context: CGContext) {
        contentView?.layer?.render(in: context)
    }
}

// MARK: - Off screen

/// A fixed desktop to draw the borders around, for `--render-borders`
private struct BorderScene {
    struct Window {
        var id: UInt32
        var title: String
        var frame: CGRect
        var isFocused = false
        var isFloating = false
        var isFullscreen = false
    }

    var name: String
    var windows: [Window]
    var mode: String? = mainModeId
    var config = BordersConfig()

    static let size = CGSize(width: 608, height: 360)

    static func tiles(focused: UInt32 = 1) -> [Window] {
        [
            Window(id: 1, title: "Zed", frame: CGRect(x: 14, y: 34, width: 283, height: 312), isFocused: focused == 1),
            Window(id: 2, title: "Zen", frame: CGRect(x: 311, y: 34, width: 283, height: 149), isFocused: focused == 2),
            Window(id: 3, title: "Ghostty", frame: CGRect(x: 311, y: 197, width: 283, height: 149), isFocused: focused == 3),
        ]
    }

    static var all: [BorderScene] {
        var modes = BordersConfig()
        modes.modeColors = ["resize": .rgba(Rgba(hex: "#30D158").orDie()), "service": .rgba(Rgba(hex: "#FF453A").orDie())]
        var onlyActive = BordersConfig()
        onlyActive.activeColor = .rgba(Rgba(hex: "#D19A66").orDie())
        onlyActive.inactiveColor = .rgba(Rgba(hex: "#00000000").orDie())
        var thick = BordersConfig()
        thick.width = 8
        thick.cornerRadius = 0
        var thin = BordersConfig()
        thin.width = 1
        thin.cornerRadius = 10
        var glow = BordersConfig()
        glow.glow = true
        var wideGlow = modes
        wideGlow.glow = true
        wideGlow.glowRadius = 24
        var amberGlow = onlyActive
        amberGlow.glow = true
        amberGlow.width = 2
        amberGlow.glowRadius = 8
        let music = Window(id: 4, title: "Music", frame: CGRect(x: 184, y: 96, width: 268, height: 176), isFocused: true, isFloating: true)
        let fullscreen = Window(id: 2, title: "Zen", frame: CGRect(x: 0, y: 20, width: 608, height: 340), isFocused: true, isFullscreen: true)
        return [
            BorderScene(name: "active-inactive", windows: tiles()),
            BorderScene(name: "floating-focused", windows: tiles(focused: 0) + [music]),
            BorderScene(name: "fullscreen", windows: [fullscreen]),
            BorderScene(name: "mode-resize", windows: tiles(), mode: "resize", config: modes),
            BorderScene(name: "mode-service", windows: tiles(), mode: "service", config: modes),
            BorderScene(name: "only-active", windows: tiles(focused: 2), config: onlyActive),
            BorderScene(name: "width-8-radius-0", windows: tiles(), config: thick),
            BorderScene(name: "width-1-radius-10", windows: tiles(), config: thin),
            BorderScene(name: "disabled", windows: tiles(), config: thick.copy(\.enabled, false)),
            BorderScene(name: "glow", windows: tiles(), config: glow),
            BorderScene(name: "glow-floating", windows: tiles(focused: 0) + [music], config: glow),
            BorderScene(name: "glow-24-mode-resize", windows: tiles(focused: 3), mode: "resize", config: wideGlow),
            BorderScene(name: "glow-8-only-active", windows: tiles(focused: 2), config: amberGlow),
            BorderScene(name: "glow-square-corners", windows: tiles(), config: glow.copy(\.cornerRadius, 0)),
        ]
    }

    /// The borders of the scene, decided by the same code that decides them for the real windows
    func snapshot(systemAccent: Rgba) -> BordersSnapshot {
        let candidates = windows.filter { !$0.isFullscreen }
            .map { BorderCandidate(windowId: $0.id, frame: $0.frame, isFocused: $0.isFocused, isFloating: $0.isFloating) }
        return BordersSnapshot.resolve(candidates, config, mode: mode, systemAccent: systemAccent)
    }
}

/// `Inlay --render-borders <dir>`: draws the borders off screen around the windows of a fake desktop, in every state.
/// The colors, the geometry and the layer are the real ones. A way to look at the borders without running Inlay
@MainActor
func renderBorderSamples(to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let scale: CGFloat = 2
    let size = BorderScene.size
    for scene in BorderScene.all {
        let image = try drawBitmap(size, scale: scale) { context in
            // The context is flipped: Y grows downwards, like in the coordinates of the layout
            let colors = [CGColor(srgbRed: 0.21, green: 0.24, blue: 0.40, alpha: 1), CGColor(srgbRed: 0.36, green: 0.29, blue: 0.52, alpha: 1)] as CFArray
            if let gradient = unsafe CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.1, blue: 0.16, alpha: 0.55)) // The menu bar
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: 20))

            let borders = scene.snapshot(systemAccent: .systemAccent).items
            // Back to front. Every border is right above its window, and below the windows in front of it
            for window in scene.windows {
                let radius: CGFloat = window.isFullscreen ? 0 : min(scene.config.cornerRadius, 16)
                context.setShadow(offset: CGSize(width: 0, height: 4), blur: window.isFloating ? 24 : 10, color: CGColor(gray: 0, alpha: 0.45))
                context.setFillColor(CGColor(srgbRed: 0.115, green: 0.115, blue: 0.135, alpha: 1))
                context.addPath(unsafe CGPath(roundedRect: window.frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
                context.fillPath()
                context.setShadow(offset: .zero, blur: 0, color: nil)
                let lights = window.isFocused
                    ? [CGColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), CGColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1), CGColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
                    : Array(repeating: CGColor(gray: 0.35, alpha: 1), count: 3)
                for (i, light) in lights.enumerated() {
                    context.setFillColor(light)
                    context.fillEllipse(in: CGRect(x: window.frame.minX + 12 + CGFloat(i) * 10, y: window.frame.minY + 11, width: 6, height: 6))
                }
                drawLabel(window.title, center: CGPoint(x: window.frame.midX, y: window.frame.midY), in: context)

                guard let border = borders.first(where: { $0.windowId == window.id }) else { continue }
                let geometry = BorderGeometry(border, scale: scale)
                let panel = BorderPanel()
                panel.apply(geometry, color: border.color, mainScreenHeight: size.height)
                context.saveGState()
                context.translateBy(x: geometry.panelFrame.minX, y: geometry.panelFrame.minY)
                panel.render(in: context)
                context.restoreGState()
                panel.close()
            }
        }
        try image.write(to: directory.appending(component: "borders-\(scene.name).png"))
    }
}

private func drawLabel(_ text: String, center: CGPoint, in context: CGContext) {
    let string = NSAttributedString(string: text, attributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor(white: 0.82, alpha: 1),
    ])
    let size = string.size()
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
    string.draw(at: CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    NSGraphicsContext.current = previous
}

/// A PNG of `size` points. The context that `draw` gets has its origin in the top left corner
private func drawBitmap(_ size: CGSize, scale: CGFloat, _ draw: (CGContext) -> Void) throws -> Data {
    struct RenderError: LocalizedError {
        var errorDescription: String? { "Can't create the bitmap" }
    }
    guard let context = unsafe CGContext(
        data: nil,
        width: Int(size.width * scale),
        height: Int(size.height * scale),
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else { throw RenderError() }
    context.translateBy(x: 0, y: size.height * scale)
    context.scaleBy(x: scale, y: -scale)
    draw(context)
    guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw RenderError()
    }
    return data
}

// MARK: - On screen, without the window manager

/// `Inlay --debug-borders [seconds]`: shows the real borders, with the real controller, around the windows that are
/// on the screen right now, and removes them. The frames come from the public window list, so it needs no permission
/// and nothing is moved: it's the borders without the window manager. Prints how every border ended up stacked
@MainActor
func runBordersDebug(seconds: Double) -> Never {
    struct Info {
        var id: UInt32
        var owner: String
        var pid: pid_t
        var layer: Int
        var frame: CGRect
    }
    func onScreen() -> [Info] { // Front to back
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { window in
            guard let id = window[kCGWindowNumber as String] as? UInt32,
                  let bounds = window[kCGWindowBounds as String],
                  let frame = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { return nil }
            return Info(
                id: id,
                owner: window[kCGWindowOwnerName as String] as? String ?? "?",
                pid: window[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                layer: window[kCGWindowLayer as String] as? Int ?? 0,
                frame: frame,
            )
        }
    }
    func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

    NSApplication.shared.setActivationPolicy(.accessory)
    let controller = BordersController.shared
    let windows = onScreen().filter { $0.layer == 0 && $0.pid != myPid && $0.frame.width >= 100 && $0.frame.height >= 100 }
    func snapshot(focused: Int) -> BordersSnapshot {
        let candidates = windows.enumerated().map { BorderCandidate(windowId: $0.element.id, frame: $0.element.frame, isFocused: $0.offset == focused) }
        return .resolve(candidates, BordersConfig(), mode: nil, systemAccent: .systemAccent)
    }
    func report(_ title: String) {
        print("--- \(title)")
        let all = onScreen()
        let numbers = controller.panelNumbers
        var glued = 0
        for window in windows {
            guard let number = numbers[window.id] else {
                print("  \(window.id) \(window.owner): NO PANEL")
                continue
            }
            let windowZ = all.firstIndex { $0.id == window.id }
            let panel = all.firstIndex { $0.id == UInt32(number) }
            let isGlued = windowZ != nil && panel == windowZ.map { $0 - 1 }
            if isGlued { glued += 1 }
            let frame = panel.map { all[$0].frame }
            let isAround = frame == BorderGeometry(frame: window.frame, width: 4, cornerRadius: 16, scale: 2).panelFrame
            print("  \(window.id) \(window.owner): window z=\(windowZ.map(String.init) ?? "-") panel #\(number) z=\(panel.map(String.init) ?? "-") layer=\(panel.map { all[$0].layer } ?? -1) " +
                "right above its window=\(isGlued) 4pt around its window=\(isAround)")
        }
        print("  glued: \(glued)/\(windows.count), panels: \(controller.panelCount), frontmost app: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"), Inlay active: \(NSApp.isActive)")
    }

    print("Windows of other apps on the screen: \(windows.count)")
    controller.show(snapshot(focused: 0))
    let before = controller.panelNumbers
    wait(max(seconds / 2, 0.3))
    report("the frontmost window is the active one")
    controller.show(snapshot(focused: 1))
    wait(max(seconds / 2, 0.3))
    report("the second window is the active one")
    print("the panels were reused on the color change: \(before == controller.panelNumbers)")
    controller.removeAll()
    wait(0.3)
    let left = onScreen().filter { $0.pid == myPid }
    print("windows of Inlay left on the screen after the cleanup: \(left.count)")
    exit(left.isEmpty ? EXIT_SUCCESS : EXIT_FAILURE)
}

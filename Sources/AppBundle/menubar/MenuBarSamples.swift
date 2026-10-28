import AppKit
import SwiftUI
import Common

/// A fixed state of the menu bar, for the preview of the settings window and for `--render-menu-bar`
enum MenuBarSamples {
    /// Six workspaces: the second one is focused, and the last one is empty
    static let snapshot = MenuBarSnapshot(
        workspaces: [
            .init(name: "1", isOccupied: true),
            .init(name: "2", isOccupied: true),
            .init(name: "3", isOccupied: true),
            .init(name: "4", isOccupied: true),
            .init(name: "5", isOccupied: true),
            .init(name: "6", isOccupied: false),
        ],
        focusedWorkspace: "2",
        focusedWindow: .init(isFloating: false, isFullscreen: false),
    )

    /// The names and the symbols of the 'labels' theme for the sample workspaces. 6 has neither: it shows its name
    static let labels = ["1": "Terminal", "2": "Code", "3": "Web", "4": "Chat", "5": "AI"]
    static let symbols = ["1": "terminal", "2": "chevron.left.forwardslash.chevron.right", "3": "globe", "4": "bubble.left", "5": "sparkles"]

    /// The config, with the sample labels and symbols if it is the 'labels' theme and it has none of its own
    static func withSampleLabels(_ config: MenuBarConfig) -> MenuBarConfig {
        guard config.theme == .labels, config.labels.isEmpty, config.symbols.isEmpty else { return config }
        return config.copy(\.labels, labels).copy(\.symbols, symbols)
    }

    /// Two monitors: 1 to 4 on the left one, 5 and 6 on the right one, which shows 5
    static let twoMonitors = MenuBarSnapshot(
        workspaces: [
            .init(name: "1", isOccupied: true, monitor: 0),
            .init(name: "2", isOccupied: true, monitor: 0, isVisible: true),
            .init(name: "3", isOccupied: true, monitor: 0),
            .init(name: "4", isOccupied: false, monitor: 0),
            .init(name: "5", isOccupied: true, monitor: 1, isVisible: true),
            .init(name: "6", isOccupied: false, monitor: 1),
        ],
        focusedWorkspace: "2",
        focusedWindow: .init(isFloating: false, isFullscreen: false),
    )

    /// The item drawn the way the menu bar draws it, but with the color of the menu bar text baked in
    @MainActor
    static func image(
        _ config: MenuBarConfig,
        snapshot: MenuBarSnapshot = snapshot,
        transition: MenuBarFocusTransition? = nil,
        isDarkBar: Bool,
        scale: CGFloat,
    ) -> NSImage? {
        let layout = MenuBarLayout.make(snapshot, config, transition: transition, measure: MenuBarFont.size)
        // Never a template: nobody is going to pick black or white for it
        let palette = MenuBarPalette.resolve(
            config,
            style: layout.style,
            isDarkBar: isDarkBar,
            systemAccent: .systemAccent,
            needsColor: layout.needsColor,
            allowsTemplate: false,
        )
        return MenuBarRenderer.image(layout, palette, scale: scale)
    }
}

extension MenuBarSamples {
    /// The item over a small menu bar: the thumbnail of a theme in the pop-up of the settings
    @MainActor
    static func thumbnail(_ config: MenuBarConfig, isDarkBar: Bool, height: CGFloat = 20) -> NSImage? {
        guard let item = image(withSampleLabels(config), isDarkBar: isDarkBar, scale: 2) else { return nil }
        let zoom = (height - 4) / item.size.height
        let itemSize = CGSize(width: item.size.width * zoom, height: item.size.height * zoom)
        let padding: CGFloat = 6
        let bar = isDarkBar ? NSColor(srgbRed: 0.24, green: 0.25, blue: 0.37, alpha: 1) : NSColor(srgbRed: 0.90, green: 0.90, blue: 0.91, alpha: 1)
        return NSImage(size: CGSize(width: itemSize.width + 2 * padding, height: height), flipped: false) { rect in
            bar.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            item.draw(in: CGRect(x: padding, y: (rect.height - itemSize.height) / 2, width: itemSize.width, height: itemSize.height))
            return true
        }
    }
}

/// `Inlay --render-menu-bar <dir>`: draws the menu bar item off screen, for every theme, in a dark and in a light menu bar,
/// with the default colors and with custom ones, and the menu that it opens. A way to look at them without running Inlay
///
/// - Parameter scale: pixels per point. 2 is what a Retina display gets; more than that gives an enlarged item
@MainActor
func renderMenuBarSamples(to directory: URL, scale: CGFloat = 2) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let custom = MenuBarColors(
        accent: .rgba(Rgba(hex: "#E06C75").orDie()),
        focused: .rgba(Rgba(hex: "#D19A66").orDie()),
        occupied: .rgba(Rgba(hex: "#ABB2BF").orDie()),
        empty: .rgba(Rgba(hex: "#6B7280").orDie()),
    )
    var resize = MenuBarSamples.snapshot
    resize.mode = "resize"
    var fullscreen = MenuBarSamples.snapshot
    fullscreen.isFocusedWorkspaceFullscreen = true
    var resizeFullscreen = resize
    resizeFullscreen.isFocusedWorkspaceFullscreen = true
    var paused = MenuBarSamples.snapshot
    paused.status = .paused
    var needsAccessibility = MenuBarSamples.snapshot
    needsAccessibility.status = .needsAccessibility

    var variants: [(name: String, config: MenuBarConfig, snapshot: MenuBarSnapshot, transition: MenuBarFocusTransition?)] = []
    func append(_ name: String, _ config: MenuBarConfig, _ snapshot: MenuBarSnapshot, _ transition: MenuBarFocusTransition? = nil) {
        variants.append((name, MenuBarSamples.withSampleLabels(config), snapshot, transition))
    }
    for theme in MenuBarTheme.allCases {
        append("\(theme.rawValue)-default", MenuBarConfig(theme: theme), MenuBarSamples.snapshot)
        append("\(theme.rawValue)-custom", MenuBarConfig(theme: theme, colors: custom), MenuBarSamples.snapshot)
        append("\(theme.rawValue)-mode", MenuBarConfig(theme: theme, showMode: true), resize)
        append("\(theme.rawValue)-mode-accent", MenuBarConfig(theme: theme, showMode: true, colors: MenuBarColors(accent: .systemAccent)), resize)
        append("\(theme.rawValue)-mode-custom", MenuBarConfig(theme: theme, showMode: true, colors: custom), resize)
        append("\(theme.rawValue)-mode-fullscreen", MenuBarConfig(theme: theme, showMode: true), resizeFullscreen)
        append("\(theme.rawValue)-fullscreen", MenuBarConfig(theme: theme), fullscreen)
    }
    append("chips-no-dim", MenuBarConfig(theme: .chips, dimEmptyWorkspaces: false), MenuBarSamples.snapshot)
    append("chips-accent-focused", MenuBarConfig(theme: .chips, colors: MenuBarColors(focused: .systemAccent)), MenuBarSamples.snapshot)
    // 'per-monitor': the workspaces of each monitor together, and 5 shown by the other monitor
    for theme in MenuBarTheme.allCases {
        append("\(theme.rawValue)-per-monitor", MenuBarConfig(theme: theme, perMonitor: true), MenuBarSamples.twoMonitors)
    }
    // The focus on its way from workspace 5 to workspace 2, in the themes whose marker changes shape as it goes
    for theme in [MenuBarTheme.pills, .dots, .underline, .liquid, .labels, .segments, .capsule] {
        for percent in [20, 40, 60, 80] {
            append("\(theme.rawValue)-slide-\(percent)", MenuBarConfig(theme: theme), MenuBarSamples.snapshot, .init(from: "5", progress: Double(percent) / 100))
        }
    }
    append("paused", MenuBarConfig(), paused)
    append("needs-accessibility", MenuBarConfig(), needsAccessibility)
    try renderMenuSamples(to: directory, scale: scale)


    let padding: CGFloat = 8
    var rendered: [(name: String, bitmap: NSBitmapImageRep)] = []
    defer { _ = try? contactSheet(rendered)?.write(to: directory.appending(path: "_sheet.png")) }
    for (name, config, snapshot, transition) in variants {
        // What the menu bar gets when the item is one color: a template image, black with different opacities
        let layout = MenuBarLayout.make(snapshot, config, transition: transition, measure: MenuBarFont.size)
        let palette = MenuBarPalette.resolve(config, style: layout.style, isDarkBar: true, systemAccent: .systemAccent, needsColor: layout.needsColor)
        if palette.isTemplate, let template = MenuBarRenderer.bitmap(layout, palette, scale: scale)?.representation(using: .png, properties: [:]) {
            try template.write(to: directory.appending(path: "\(name)-template.png"))
        }
        for isDarkBar in [true, false] {
            guard let item = MenuBarSamples.image(config, snapshot: snapshot, transition: transition, isDarkBar: isDarkBar, scale: scale) else { continue }
            // Over something like a menu bar
            let size = CGSize(width: item.size.width + 2 * padding, height: item.size.height + 2)
            guard let bitmap = NSBitmapImageRep.rgba(pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), scale: scale),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            (isDarkBar ? NSColor(srgbRed: 0.22, green: 0.24, blue: 0.36, alpha: 1) : NSColor(srgbRed: 0.90, green: 0.90, blue: 0.90, alpha: 1)).setFill()
            NSRect(origin: .zero, size: size).fill()
            item.draw(in: NSRect(x: padding, y: 1, width: item.size.width, height: item.size.height))
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: directory.appending(path: "\(name)-\(isDarkBar ? "dark" : "light").png"))
            rendered.append((name, bitmap))
        }
    }
}

/// The menu that a click on the item opens, in a dark and in a light appearance: menu-<state>-<dark|light>.png.
/// Over the color of the menus, without their blur
@MainActor
private func renderMenuSamples(to directory: URL, scale: CGFloat) throws {
    let reloaded = Date.now.addingTimeInterval(-3)
    let cards: [(String, MenuBarCard)] = [
        ("running", MenuBarCard(status: .running, workspace: "2", focusedApp: "Zed", windowLayout: .tiling, lastReload: reloaded)),
        ("mode-problems", MenuBarCard(
            status: .running,
            configProblems: "Config contains warnings…",
            workspace: "2",
            focusedApp: "Zed",
            windowLayout: .floating,
            mode: "resize",
            modeExitKey: "esc",
            problemLines: ["[WARNING] animations.curve: Unknown curve 'bounce2'"],
            lastReload: reloaded,
        )),
        ("empty", MenuBarCard(status: .running, workspace: "6", lastReload: reloaded)),
        ("paused", MenuBarCard(status: .paused, workspace: "2", lastReload: reloaded)),
        ("needs-accessibility", MenuBarCard(status: .needsAccessibility, workspace: "1")),
    ]
    for (name, card) in cards {
        for isDark in [true, false] {
            let view = MenuBarPanelView(content: MenuBarPanelContent(card), run: { _ in })
                .background(Color(nsColor: .windowBackgroundColor))
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            hosting.layoutSubtreeIfNeeded()
            let pixels = CGSize(width: hosting.bounds.width * scale, height: hosting.bounds.height * scale)
            guard let bitmap = NSBitmapImageRep.rgba(pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height), scale: scale) else { continue }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "menu-\(name)-\(isDark ? "dark" : "light").png"))
        }
    }
}

/// All the variants in one image, enlarged: a row per variant, the dark menu bar on the left and the light one on the right
@MainActor
private func contactSheet(_ rendered: [(name: String, bitmap: NSBitmapImageRep)]) -> Data? {
    let zoom: CGFloat = 3
    let labelWidth: CGFloat = 190
    let rowHeight: CGFloat = 24 * zoom + 8
    let columnWidth = (rendered.map(\.bitmap.size.width).max() ?? 0) * zoom + 12
    let rows = stride(from: 0, to: rendered.count - 1, by: 2).map { (rendered[$0], rendered[$0 + 1]) }
    let size = CGSize(width: labelWidth + 2 * columnWidth, height: CGFloat(rows.count) * rowHeight + 8)
    guard let sheet = NSBitmapImageRep.rgba(pixelsWide: Int(size.width), pixelsHigh: Int(size.height), scale: 1),
          let context = NSGraphicsContext(bitmapImageRep: sheet) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor(white: 0.12, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    for (index, (dark, light)) in rows.enumerated() {
        let y = size.height - CGFloat(index + 1) * rowHeight
        NSAttributedString(string: dark.name, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white])
            .draw(at: NSPoint(x: 8, y: y + rowHeight / 2 - 8))
        for (column, bitmap) in [dark.bitmap, light.bitmap].enumerated() {
            let rect = NSRect(x: labelWidth + CGFloat(column) * columnWidth, y: y, width: bitmap.size.width * zoom, height: bitmap.size.height * zoom)
            bitmap.draw(in: rect)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return sheet.representation(using: .png, properties: [:])
}

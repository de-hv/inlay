import AppKit
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

/// `Inlay --render-menu-bar <dir>`: draws the menu bar item off screen, for every theme, in a dark and in a light menu bar,
/// with the default colors and with custom ones. A way to look at the item without running Inlay
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
        variants.append((name, config, snapshot, transition))
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
    // The palettes of [theme], in the default theme
    for palette in ThemePalette.allCases where palette != .system {
        append("pills-palette-\(palette.rawValue)", MenuBarConfig(palette: palette), MenuBarSamples.snapshot)
    }
    // Material You from another seed
    append("pills-palette-material-seed", MenuBarConfig(palette: .material, paletteSeed: Rgba(hex: "#B5651D").orDie()), MenuBarSamples.snapshot)
    // The focus on its way from workspace 5 to workspace 2, in the themes whose marker changes shape as it goes
    for theme in [MenuBarTheme.pills, .dots, .underline, .liquid] {
        for percent in [20, 40, 60, 80] {
            append("\(theme.rawValue)-slide-\(percent)", MenuBarConfig(theme: theme), MenuBarSamples.snapshot, .init(from: "5", progress: Double(percent) / 100))
        }
    }
    append("paused", MenuBarConfig(), paused)
    append("needs-accessibility", MenuBarConfig(), needsAccessibility)

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

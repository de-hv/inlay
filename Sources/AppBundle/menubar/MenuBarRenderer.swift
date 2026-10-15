import AppKit
import Common
import SwiftUI
import os

extension MenuBarFont {
    // Immutable fonts, never changed after they are created: safe to read from any thread
    nonisolated(unsafe) private static let fonts: [MenuBarFont: NSFont] = {
        typealias M = MenuBarMetrics
        return [
            .chipName: .monospacedDigitSystemFont(ofSize: M.chipFontSize, weight: .semibold),
            .squareName: .monospacedDigitSystemFont(ofSize: M.workspaceFontSize, weight: .medium),
            .modeInitial: .systemFont(ofSize: M.modeSquareFontSize, weight: .heavy),
            .chipModeInitial: .systemFont(ofSize: M.chipModeFontSize, weight: .heavy),
        ]
    }()

    /// Created once: making a font is slow, compared to everything else that the layout of the item does
    var nsFont: NSFont { unsafe Self.fonts[self].orDie() }

    private struct Measured: Hashable {
        var string: String
        var font: MenuBarFont
    }

    /// The texts of the item are the names of the workspaces and the initials of the modes: a few, always the same
    private static let sizes = OSAllocatedUnfairLock<[Measured: CGSize]>(initialState: [:])
    private static let maxCachedSizes = 512

    /// The real `MenuBarLayout.Measure`
    static func size(of string: String, _ font: MenuBarFont) -> CGSize {
        let measured = Measured(string: string, font: font)
        if let size = sizes.withLock({ $0[measured] }) { return size }
        let size = NSAttributedString(string: string, attributes: [.font: font.nsFont]).size()
        sizes.withLock {
            if $0.count >= maxCachedSizes { $0.removeAll() }
            $0[measured] = size
        }
        return size
    }
}

/// Everything that the image of the menu bar item is drawn from. Two equal keys give the same image
struct MenuBarDrawKey: Equatable, Sendable {
    var state: MenuBarState
    /// The frame of the slide of the focus marker
    var transition: MenuBarFocusTransition? = nil
    var isDarkBar: Bool
    var systemAccent: Rgba
    /// Pixels per point
    var scale: CGFloat
}

/// Draws a `MenuBarLayout` with a `MenuBarPalette`
@MainActor
enum MenuBarRenderer {
    static func image(_ key: MenuBarDrawKey) -> NSImage? {
        let layout = MenuBarLayout.make(key.state.snapshot, key.state.config, transition: key.transition, measure: MenuBarFont.size)
        let palette = MenuBarPalette.resolve(
            key.state.config,
            style: layout.style,
            isDarkBar: key.isDarkBar,
            systemAccent: key.systemAccent,
            needsColor: layout.needsColor,
        )
        return image(layout, palette, scale: key.scale)
    }

    /// - Parameter scale: pixels per point
    static func image(_ layout: MenuBarLayout, _ palette: MenuBarPalette, scale: CGFloat) -> NSImage? {
        guard let bitmap = bitmap(layout, palette, scale: scale) else { return nil }
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        image.isTemplate = palette.isTemplate
        return image
    }

    static func bitmap(_ layout: MenuBarLayout, _ palette: MenuBarPalette, scale: CGFloat) -> NSBitmapImageRep? {
        let pixels = CGSize(width: max(1, (layout.size.width * scale).rounded(.up)), height: max(1, (layout.size.height * scale).rounded(.up)))
        guard let bitmap = NSBitmapImageRep.rgba(pixelsWide: Int(pixels.width), pixelsHigh: Int(pixels.height), scale: scale),
              let bitmapContext = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        let cg = bitmapContext.cgContext
        // Top left origin, like the layout
        cg.translateBy(x: 0, y: bitmap.size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(layout, palette, in: cg, scale: scale)
        return bitmap
    }

    /// Draws into a flipped context (top left origin) that is also the current NSGraphicsContext
    static func draw(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext, scale: CGFloat) {
        var layout = layout
        // Shapes start at whole pixels, like SwiftUI places them in Aeromenu. Otherwise their straight edges are blurred
        func snap(_ rect: CGRect) -> CGRect {
            CGRect(x: (rect.minX * scale).rounded() / scale, y: (rect.minY * scale).rounded() / scale, width: rect.width, height: rect.height)
        }
        for index in layout.cells.indices where layout.style == .chips {
            layout.cells[index].frame = snap(layout.cells[index].frame)
        }
        if let marker = layout.marker {
            let frame = snap(marker.frame)
            layout.marker?.frame = frame
            // The initial of the binding mode goes with its marker
            layout.marker?.initial?.frame = marker.initial?.frame.offsetBy(dx: frame.minX - marker.frame.minX, dy: frame.minY - marker.frame.minY) ?? .zero
        }
        pixel = 1 / scale
        if let placeholder = layout.placeholder {
            draw(placeholder, palette, in: cg)
            return
        }
        switch layout.style {
            case .chips: drawChips(layout, palette, in: cg)
            case .square: drawSquare(layout, palette, in: cg)
        }
    }

    // MARK: - Chips

    private static func drawChips(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        // The row as if no workspace was focused
        for cell in layout.cells {
            // Only the workspaces with windows get a chip, so the background itself says "something is here"
            if cell.isOccupied {
                cg.fill(roundedRect(cell.frame, M.chipCornerRadius), palette.occupiedBackground)
            }
            draw(cell.name, palette.nameColor(of: cell))
        }
        guard let marker = layout.marker else { return }
        let path = roundedRect(marker.frame, marker.cornerRadius)
        // Clears the faint chip under the marker
        cg.fill(path, .black, blendMode: .destinationOut)
        if let initial = marker.initial {
            // A binding mode: its initial instead of the name of the workspace
            draw(marker, initial, palette, in: cg)
            return
        }
        if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.outlineWidth, palette.focused)
        } else {
            cg.fill(path, palette.focused)
        }
        // The same row again, names only. Whatever part of it the marker covers is what the marker shows,
        // so the names stay put while the marker slides over them
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        for cell in layout.cells {
            switch (marker.isOutlined, palette.focusedName) {
                case (true, _): draw(cell.name, palette.focused)
                case (false, let color?): draw(cell.name, color)
                // In negative: cut out of the marker
                case (false, nil): draw(cell.name, .black, blendMode: .destinationOut)
            }
        }
        cg.restoreGState()
    }

    // MARK: - Square

    private static func drawSquare(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        for cell in layout.cells {
            // The name gives way to the marker
            let color = palette.nameColor(of: cell).opacity(1 - cell.focus)
            draw(cell.name, color)
        }
        guard let marker = layout.marker else { return }
        // Clears what is under the marker first: mid-slide it passes over the names in between
        let clearance = marker.frame.insetBy(dx: -M.markerClearance, dy: -M.markerClearance)
        cg.fill(roundedRect(clearance, marker.cornerRadius + M.markerClearance), .black, blendMode: .destinationOut)
        if let initial = marker.initial {
            draw(marker, initial, palette, in: cg)
        } else if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.outlineWidth, palette.focused)
        } else {
            cg.fill(roundedRect(marker.frame, marker.cornerRadius), palette.focused)
        }
    }

    // MARK: - Binding mode

    /// The marker of a binding mode, the same in every theme: the initial of the mode cut out of a filled marker
    /// (or in black or white, over a fixed color), or drawn inside of an outlined one while a window is fullscreen
    private static func draw(_ marker: MenuBarLayout.Marker, _ initial: MenuBarLayout.Text, _ palette: MenuBarPalette, in cg: CGContext) {
        if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: MenuBarMetrics.outlineWidth, palette.modeMarker)
            draw(initial, palette.modeMarker)
            return
        }
        cg.fill(roundedRect(marker.frame, marker.cornerRadius), palette.modeMarker)
        switch palette.modeInitial {
            case let color?: draw(initial, color)
            case nil: draw(initial, .black, blendMode: .destinationOut)
        }
    }

    // MARK: - Placeholder

    private static func draw(_ placeholder: MenuBarLayout.Placeholder, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        drawSymbol(placeholder.symbolName, pointSize: M.statusSymbolSize, centeredIn: placeholder.symbolFrame, palette.base)
        // The app icon as a glyph: six workspaces in a 3x2 grid, none of them focused
        for row in 0 ..< 2 {
            for column in 0 ..< 3 {
                let square = CGRect(
                    x: placeholder.glyphFrame.minX + CGFloat(column) * (M.glyphSide + M.glyphGap),
                    y: placeholder.glyphFrame.minY + CGFloat(row) * (M.glyphSide + M.glyphGap),
                    width: M.glyphSide,
                    height: M.glyphSide,
                )
                let snapped = CGRect(x: (square.minX / pixel).rounded() * pixel, y: (square.minY / pixel).rounded() * pixel, width: square.width, height: square.height)
                cg.strokeBorder(snapped, M.glyphCornerRadius, lineWidth: M.glyphLineWidth, palette.base.opacity(placeholder.glyphOpacity))
            }
        }
    }

    // MARK: - Primitives

    /// The size of a pixel of the context being drawn, in points
    private static var pixel: CGFloat = 0.5

    /// The same shape as RoundedRectangle(cornerRadius:style: .continuous) of SwiftUI, that Aeromenu draws
    private static func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
        Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
    }

    private static func draw(_ text: MenuBarLayout.Text, _ color: Rgba, blendMode: CGBlendMode = .normal) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        cg.setBlendMode(blendMode)
        NSAttributedString(string: text.string, attributes: [.font: text.font.nsFont, .foregroundColor: color.nsColor])
            .draw(at: text.frame.origin)
        cg.restoreGState()
    }

    /// SF Symbols are rasterized by SwiftUI, so they come out exactly like in Aeromenu.
    /// AppKit places the lines of the same symbol a fraction of a pixel off
    private static func drawSymbol(_ name: String, pointSize: CGFloat, centeredIn frame: CGRect, _ color: Rgba) {
        let key = SymbolKey(name: name, pointSize: pointSize, color: color.hex, scale: 1 / pixel)
        if symbols[key] == nil {
            let renderer = ImageRenderer(content: Image(systemName: name).font(.system(size: pointSize)).foregroundStyle(Color(nsColor: color.nsColor)))
            renderer.scale = 1 / pixel
            symbols[key] = renderer.nsImage
        }
        guard let symbol = symbols[key] else { return }
        let size = symbol.size
        // Whole pixels again, or the lines of the symbol are blurred
        let target = CGRect(
            x: ((frame.midX - size.width / 2) / pixel).rounded() * pixel,
            y: ((frame.midY - size.height / 2) / pixel).rounded() * pixel,
            width: size.width,
            height: size.height,
        )
        symbol.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private struct SymbolKey: Hashable {
        var name: String
        var pointSize: CGFloat
        var color: String
        var scale: CGFloat
    }

    private static var symbols: [SymbolKey: NSImage] = [:]
}

extension CGContext {
    fileprivate func fill(_ path: CGPath, _ color: Rgba, blendMode: CGBlendMode = .normal) {
        saveGState()
        setBlendMode(blendMode)
        setFillColor(color.cgColor)
        addPath(path)
        fillPath()
        restoreGState()
    }

    /// The stroke stays inside of the rect, like strokeBorder of SwiftUI
    fileprivate func strokeBorder(_ rect: CGRect, _ radius: CGFloat, lineWidth: CGFloat, _ color: Rgba) {
        saveGState()
        setStrokeColor(color.cgColor)
        setLineWidth(lineWidth)
        let inset = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        addPath(Path(roundedRect: inset, cornerRadius: max(0, radius - lineWidth / 2), style: .continuous).cgPath)
        strokePath()
        restoreGState()
    }
}

extension NSBitmapImageRep {
    /// An empty 8-bit RGBA bitmap. Its size in points is the size in pixels divided by the scale
    static func rgba(pixelsWide: Int, pixelsHigh: Int, scale: CGFloat) -> NSBitmapImageRep? {
        let bitmap = unsafe NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0,
        )
        bitmap?.size = CGSize(width: CGFloat(pixelsWide) / scale, height: CGFloat(pixelsHigh) / scale)
        return bitmap
    }
}

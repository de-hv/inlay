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
        let size = font == .symbol
            ? NSImage(systemSymbolName: string, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: MenuBarMetrics.labelSymbolSize, weight: .regular))?.size ?? .zero
            : NSAttributedString(string: string, attributes: [.font: font.nsFont]).size()
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
        for index in layout.cells.indices where [MenuBarLayout.Style.chips, .dots, .labels, .segments, .capsule].contains(layout.style) {
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
            case .dots: drawDots(layout, palette, in: cg)
            case .underline: drawUnderline(layout, palette, in: cg)
            case .glyphs: drawGlyphs(layout, palette, in: cg)
            case .liquid: drawLiquid(layout, palette, in: cg)
            case .labels: drawLabels(layout, palette, in: cg)
            case .segments: drawSegments(layout, palette, in: cg)
            case .capsule: drawCapsule(layout, palette, in: cg)
        }
        // 'per-monitor'
        for separator in layout.separators {
            cg.fill(CGPath(rect: separator, transform: nil), palette.base.opacity(MenuBarMetrics.emptyWorkspaceOpacity))
        }
        for marker in layout.visibleElsewhere {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: MenuBarMetrics.outlineWidth, palette.focused)
        }
    }

    // MARK: - Chips

    private static func drawChips(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        // The row as if no workspace was focused
        for cell in layout.cells {
            // Only the workspaces with windows get a chip, so the background itself says "something is here"
            if cell.isOccupied {
                cg.fill(roundedRect(cell.frame, layout.cornerRadius), palette.occupiedBackground)
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

    // MARK: - Dots

    private static func drawDots(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        for cell in layout.cells {
            // The slot widens while the pill arrives, but its dot stays round: only the pill stretches.
            // A disc says "something is here", a ring says "nothing yet"
            let dot = CGRect(x: cell.frame.midX - M.dotSide / 2, y: cell.frame.midY - M.dotSide / 2, width: M.dotSide, height: M.dotSide)
            if cell.isOccupied {
                cg.fill(roundedRect(dot, M.dotSide / 2), palette.nameColor(of: cell))
            } else {
                cg.strokeBorder(dot, M.dotSide / 2, lineWidth: M.dotLineWidth, palette.nameColor(of: cell))
            }
        }
        guard let marker = layout.marker else { return }
        let path = roundedRect(marker.frame, marker.cornerRadius)
        cg.fill(path, .black, blendMode: .destinationOut)
        if let initial = marker.initial {
            draw(marker, initial, palette, in: cg)
        } else if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.dotLineWidth, palette.focused)
        } else {
            cg.fill(path, palette.focused)
        }
    }

    // MARK: - Underline

    private static func drawUnderline(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        let initial = layout.marker?.initial
        for cell in layout.cells {
            // The focused name takes the color of the bar. In a binding mode the initial takes its place
            draw(cell.name, palette.nameColor(of: cell).opacity(1 - cell.focus))
            if initial == nil, cell.focus > 0 {
                draw(cell.name, palette.focused.opacity(cell.focus))
            }
        }
        guard let marker = layout.marker else { return }
        let color = initial == nil ? palette.focused : palette.modeMarker
        if let initial { draw(initial, color) }
        if marker.isOutlined {
            // A hollow bar, a bit taller so that its hole can be seen
            let frame = marker.frame.insetBy(dx: 0, dy: -0.75)
            cg.strokeBorder(frame, frame.height / 2, lineWidth: 1, color)
        } else {
            cg.fill(roundedRect(marker.frame, marker.cornerRadius), color)
        }
    }

    // MARK: - Glyphs

    private static func drawGlyphs(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        let isOutlined = layout.marker?.isOutlined == true
        for cell in layout.cells {
            let center = CGPoint(x: cell.frame.midX, y: cell.frame.midY)
            func circle(_ side: CGFloat) -> CGRect { CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side) }
            // The glyph of the workspace fades out while the target of the focus grows over it
            let rest = palette.nameColor(of: cell).opacity(1 - cell.focus)
            if cell.isOccupied {
                cg.fill(roundedRect(circle(M.ringDiscSide), M.ringDiscSide / 2), rest)
            } else {
                cg.strokeBorder(circle(M.ringEmptySide), M.ringEmptySide / 2, lineWidth: M.ringLineWidth, rest)
            }
            guard cell.focus > 0 else { continue }
            let ring = M.ringEmptySide + (M.ringSide - M.ringEmptySide) * cell.focus
            let color = palette.focused.opacity(cell.focus)
            cg.strokeBorder(circle(ring), ring / 2, lineWidth: M.ringLineWidth, color)
            // A fullscreen window leaves the target hollow, like the outlined marker of the other themes
            if !isOutlined {
                cg.fill(roundedRect(circle(M.ringCenterSide), M.ringCenterSide / 2), color)
            }
        }
        guard let marker = layout.marker, let initial = marker.initial else { return }
        let clearance = marker.frame.insetBy(dx: -M.markerClearance, dy: -M.markerClearance)
        cg.fill(roundedRect(clearance, clearance.height / 2), .black, blendMode: .destinationOut)
        draw(marker, initial, palette, in: cg)
    }

    // MARK: - Liquid

    private static func drawLiquid(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        for cell in layout.cells {
            let side = cell.isOccupied ? M.liquidOccupiedDot : M.liquidEmptyDot
            let dot = CGRect(x: cell.frame.midX - side / 2, y: cell.frame.midY - side / 2, width: side, height: side)
            cg.fill(roundedRect(dot, side / 2), palette.nameColor(of: cell))
        }
        guard let marker = layout.marker else { return }
        let color = marker.initial == nil ? palette.focused : palette.modeMarker
        // Filled one by one: where they overlap, the winding of one path could cut a hole in another
        let drop = dropPaths(marker.frame, trail: marker.trail)
        for path in drop { cg.fill(path, .black, blendMode: .destinationOut) }
        if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.outlineWidth, color)
        } else {
            for path in drop { cg.fill(path, color) }
        }
        if let initial = marker.initial {
            if !marker.isOutlined { cg.fill(roundedRect(marker.frame, marker.cornerRadius), palette.modeMarker) }
            switch (marker.isOutlined, palette.modeInitial) {
                case (true, _): draw(initial, palette.modeMarker)
                case (false, let color?): draw(initial, color)
                case (false, nil): draw(initial, .black, blendMode: .destinationOut)
            }
            return
        }
        // The drop carries the name of the workspace it is closest to: the one it leaves, then the one it reaches
        guard let cell = layout.cells.max(by: { $0.focus < $1.focus }) else { return }
        var name = cell.name
        name.frame.origin = CGPoint(x: marker.frame.midX - name.frame.width / 2, y: marker.frame.midY - name.frame.height / 2)
        switch (marker.isOutlined, palette.focusedName) {
            case (true, _): draw(name, palette.focused)
            case (false, let color?): draw(name, color)
            case (false, nil): draw(name, .black, blendMode: .destinationOut)
        }
    }

    /// The drop and its trail joined by a neck that gets thinner as they move apart: two circles on the same line,
    /// and the curves between their tops and between their bottoms
    private static func dropPaths(_ drop: CGRect, trail: CGRect?) -> [CGPath] {
        guard let trail else { return [CGPath(ellipseIn: drop, transform: nil)] }
        let path = CGMutablePath()
        let (dropRadius, trailRadius) = (drop.height / 2, trail.height / 2)
        let distance = abs(drop.midX - trail.midX)
        let neck = trailRadius * max(0.35, 1 - distance / (4 * drop.width))
        let midX = (drop.midX + trail.midX) / 2
        let y = drop.midY
        path.move(to: CGPoint(x: trail.midX, y: y - trailRadius))
        path.addQuadCurve(to: CGPoint(x: drop.midX, y: y - dropRadius), control: CGPoint(x: midX, y: y - neck))
        path.addLine(to: CGPoint(x: drop.midX, y: y + dropRadius))
        path.addQuadCurve(to: CGPoint(x: trail.midX, y: y + trailRadius), control: CGPoint(x: midX, y: y + neck))
        path.closeSubpath()
        return [CGPath(ellipseIn: trail, transform: nil), path, CGPath(ellipseIn: drop, transform: nil)]
    }

    // MARK: - Labels

    private static func drawLabels(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        for cell in layout.cells {
            let color = palette.nameColor(of: cell)
            if let symbol = cell.symbol {
                drawSymbol(symbol.string, pointSize: M.labelSymbolSize, centeredIn: symbol.frame, color)
            } else {
                draw(cell.name, color)
            }
        }
        guard let marker = layout.marker else { return }
        let path = roundedRect(marker.frame, marker.cornerRadius)
        // Clears the symbol under the marker
        cg.fill(path, .black, blendMode: .destinationOut)
        if let initial = marker.initial {
            draw(marker, initial, palette, in: cg)
            return
        }
        if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.outlineWidth, palette.focused)
        } else {
            cg.fill(path, palette.focused)
        }
        // Whatever the marker covers, cut out of it or over it, like the names of the chips: the symbol and the label of
        // the workspaces it leaves or reaches, and the symbol of the ones it passes over on its way
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        for cell in layout.cells {
            let texts = cell.focus > 0 ? cell.expanded : [cell.symbol ?? cell.name]
            for text in texts {
                let color = marker.isOutlined ? palette.focused : palette.focusedName
                if text.font == .symbol {
                    drawSymbol(text.string, pointSize: M.labelSymbolSize, centeredIn: text.frame, color ?? .black, cutOut: color == nil)
                } else if let color {
                    draw(text, color)
                } else {
                    draw(text, .black, blendMode: .destinationOut)
                }
            }
        }
        cg.restoreGState()
    }

    // MARK: - Segments

    private static func drawSegments(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        // The ends of the track are round, and so are the ones next to the gap between two monitors ('per-monitor')
        let cells = layout.cells
        for (index, cell) in cells.enumerated() {
            let isStart = index == 0 || cell.frame.minX - cells[index - 1].frame.maxX > M.segmentSpacing + 0.5
            let isEnd = index == cells.count - 1 || cells[index + 1].frame.minX - cell.frame.maxX > M.segmentSpacing + 0.5
            let left = isStart ? M.segmentEndRadius : M.segmentInnerRadius
            let right = isEnd ? M.segmentEndRadius : M.segmentInnerRadius
            // A filled segment says "something is here", a hollow one says "nothing yet"
            if cell.isOccupied {
                cg.fill(segmentPath(cell.frame, left: left, right: right), palette.nameColor(of: cell))
            } else {
                let inset = M.segmentLineWidth / 2
                cg.stroke(segmentPath(cell.frame.insetBy(dx: inset, dy: inset), left: left - inset, right: right - inset), lineWidth: M.segmentLineWidth, palette.nameColor(of: cell))
            }
        }
        guard let marker = layout.marker else { return }
        let color = marker.initial == nil ? palette.focused : palette.modeMarker
        let path = roundedRect(marker.frame, marker.cornerRadius)
        cg.fill(path, .black, blendMode: .destinationOut)
        if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.segmentLineWidth, color)
        } else {
            cg.fill(path, color)
        }
        if let text = marker.initial ?? layout.label { draw(text, color) }
    }

    /// A segment of the track: its left and its right corners rounded each their own way
    private static func segmentPath(_ rect: CGRect, left: CGFloat, right: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let (left, right) = (min(left, rect.height / 2), min(right, rect.height / 2))
        path.move(to: CGPoint(x: rect.minX + left, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: right)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: right)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: left)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: left)
        path.closeSubpath()
        return path
    }

    // MARK: - Capsule

    private static func drawCapsule(_ layout: MenuBarLayout, _ palette: MenuBarPalette, in cg: CGContext) {
        typealias M = MenuBarMetrics
        for cell in layout.cells {
            // The dots of 'dots': a disc says "something is here", a ring says "nothing yet"
            let dot = CGRect(x: cell.frame.midX - M.dotSide / 2, y: cell.frame.midY - M.dotSide / 2, width: M.dotSide, height: M.dotSide)
            if cell.isOccupied {
                cg.fill(roundedRect(dot, M.dotSide / 2), palette.nameColor(of: cell))
            } else {
                cg.strokeBorder(dot, M.dotSide / 2, lineWidth: M.dotLineWidth, palette.nameColor(of: cell))
            }
        }
        guard let marker = layout.marker else { return }
        let path = roundedRect(marker.frame, marker.cornerRadius)
        cg.fill(path, .black, blendMode: .destinationOut)
        if let initial = marker.initial {
            draw(marker, initial, palette, in: cg)
            return
        }
        if marker.isOutlined {
            cg.strokeBorder(marker.frame, marker.cornerRadius, lineWidth: M.outlineWidth, palette.focused)
        } else {
            cg.fill(path, palette.focused)
        }
        // The names, like the ones of the chips: whatever part of them the capsule covers is what it shows, so the name
        // of the workspace it leaves goes away as the one of the workspace it reaches comes in
        cg.saveGState()
        cg.addPath(path)
        cg.clip()
        for cell in layout.cells where cell.focus > 0 {
            switch (marker.isOutlined, palette.focusedName) {
                case (true, _): draw(cell.name, palette.focused)
                case (false, let color?): draw(cell.name, color)
                case (false, nil): draw(cell.name, .black, blendMode: .destinationOut)
            }
        }
        cg.restoreGState()
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
    /// - Parameter cutOut: the symbol is cut out of what is under it instead of drawn
    private static func drawSymbol(_ name: String, pointSize: CGFloat, centeredIn frame: CGRect, _ color: Rgba, cutOut: Bool = false) {
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
        symbol.draw(in: target, from: .zero, operation: cutOut ? .destinationOut : .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
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

    fileprivate func stroke(_ path: CGPath, lineWidth: CGFloat, _ color: Rgba) {
        saveGState()
        setStrokeColor(color.cgColor)
        setLineWidth(lineWidth)
        addPath(path)
        strokePath()
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

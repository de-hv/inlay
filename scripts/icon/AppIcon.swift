// Draws the Inlay app icon (1024x1024 PNG) with AppKit.
//
//   swift scripts/icon/AppIcon.swift <output.png>
//
// The drawing is three tiled windows in a dwindle layout, set into a dark plate; the focused one has an accent border.

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: AppIcon.swift <output.png>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])

let size = 1024
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("error: can't create the bitmap\n".utf8))
    exit(1)
}
NSGraphicsContext.current = context

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha,
    )
}

// The plate. macOS icons leave a margin of about 10% around the shape
let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
let platePath = NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185)
NSGradient(starting: color(0x2B3140), ending: color(0x12151C))?.draw(in: platePath, angle: -90)
color(0xFFFFFF, alpha: 0.10).setStroke()
platePath.lineWidth = 4
platePath.stroke()

// Dwindle layout: one window on the left, two stacked on the right
let inset: CGFloat = 96
let gap: CGFloat = 36
let area = plate.insetBy(dx: inset, dy: inset)
let columnWidth = (area.width - gap) / 2
let rowHeight = (area.height - gap) / 2
let left = NSRect(x: area.minX, y: area.minY, width: columnWidth, height: area.height)
let topRight = NSRect(x: area.minX + columnWidth + gap, y: area.minY + rowHeight + gap, width: columnWidth, height: rowHeight)
let bottomRight = NSRect(x: area.minX + columnWidth + gap, y: area.minY, width: columnWidth, height: rowHeight)

let accent = color(0x5CC8FF)
for (rect, isFocused) in [(left, true), (topRight, false), (bottomRight, false)] {
    let path = NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44)
    (isFocused ? accent.withAlphaComponent(0.22) : color(0xFFFFFF, alpha: 0.10)).setFill()
    path.fill()
    (isFocused ? accent : color(0xFFFFFF, alpha: 0.38)).setStroke()
    path.lineWidth = isFocused ? 22 : 12
    path.stroke()
}

context.flushGraphics()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("error: can't encode the PNG\n".utf8))
    exit(1)
}
do {
    try png.write(to: output)
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}

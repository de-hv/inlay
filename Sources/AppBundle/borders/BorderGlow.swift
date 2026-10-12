import CoreGraphics

/// The glow of a border: a halo of the color of the border that fades out from the outer edge of the ring outwards.
/// Nothing is drawn under the ring or inside of it, so the glow never covers the window.
///
/// The glow of a big window isn't drawn at its size. Along the straight sides the glow is the same everywhere, so
/// a small image with the four corners is drawn once, and the layer of the panel stretches its middle (`contentsCenter`).
/// Moving or resizing the window draws nothing
struct BorderGlow: Equatable, Sendable {
    /// The size of the image, in points. The size of the panel, or smaller
    var size: CGSize
    /// The part of the image that is stretched to fill the panel, in the unit coordinates of `CALayer.contentsCenter`
    var center: CGRect
    /// The outer edge of the ring inside of the image
    var outerRect: CGRect
    var outerRadius: CGFloat
    var blurRadius: CGFloat
    var color: Rgba
    /// Pixels per point
    var scale: CGFloat

    /// nil if the border doesn't glow
    init?(_ geometry: BorderGeometry, color: Rgba) {
        guard geometry.glowRadius > 0, geometry.glowMargin > 0 else { return nil }
        let margin = geometry.glowMargin
        let panel = geometry.panelFrame.size
        // Past the margin and the rounded corner, and one margin further: that far the corner still shapes the glow
        let corner = ((2 * margin + geometry.outerRadius) * geometry.scale).rounded(.up) / geometry.scale
        let stretch = 1 / geometry.scale // One pixel of the middle is enough
        func side(_ panelSide: CGFloat) -> (size: CGFloat, center: ClosedRange<CGFloat>) {
            let full = 2 * corner + stretch
            // A small panel gets the whole glow drawn, and nothing is stretched
            return panelSide > full ? (full, corner / full ... (corner + stretch) / full) : (panelSide, 0 ... 1)
        }
        let (width, x) = side(panel.width), (height, y) = side(panel.height)
        size = CGSize(width: width, height: height)
        center = CGRect(x: x.lowerBound, y: y.lowerBound, width: x.upperBound - x.lowerBound, height: y.upperBound - y.lowerBound)
        outerRect = CGRect(origin: .zero, size: size).insetBy(dx: margin, dy: margin)
        outerRadius = min(geometry.outerRadius, outerRect.width / 2, outerRect.height / 2)
        blurRadius = geometry.glowRadius
        self.color = color
        scale = geometry.scale
    }

    /// The image of the glow, `size * scale` pixels. Transparent inside of the outer edge of the ring
    func image() -> CGImage? {
        let pixelsWide = Int((size.width * scale).rounded()), pixelsHigh = Int((size.height * scale).rounded())
        guard pixelsWide > 0, pixelsHigh > 0, let context = unsafe CGContext(
            data: nil,
            width: pixelsWide,
            height: pixelsHigh,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.scaleBy(x: scale, y: scale)
        let shape = unsafe CGPath(roundedRect: outerRect, cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
        // Only outside of the shape: the shape casts the glow, and it isn't drawn itself
        context.addRect(CGRect(origin: .zero, size: size))
        context.addPath(shape)
        context.clip(using: .evenOdd)
        // The blur of a shadow is in pixels, whatever the transform of the context is
        context.setShadow(offset: .zero, blur: blurRadius * scale, color: color.cgColor)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        // Twice: one gaussian falloff starts at half of the color at the edge of the ring, which looks detached from it
        for _ in 0 ..< 2 {
            context.addPath(shape)
            context.fillPath()
        }
        return context.makeImage()
    }
}

import CoreGraphics

/// A screen as the borders need it
struct BorderScreen: Equatable, Sendable {
    /// In the coordinates of the layout: the origin is the top left corner of the main screen, Y grows downwards
    var frame: CGRect
    /// Pixels per point
    var scale: CGFloat

    /// The scale of the screen that shows the biggest part of the rect. 2 if there are no screens
    static func scale(for rect: CGRect, in screens: [BorderScreen]) -> CGFloat {
        func area(_ screen: BorderScreen) -> CGFloat {
            let common = screen.frame.intersection(rect)
            return common.isNull ? 0 : common.width * common.height
        }
        var best: BorderScreen? = nil
        for screen in screens where best.map({ area(screen) > area($0) }) ?? true {
            best = screen
        }
        return best?.scale ?? 2
    }
}

/// Where the panel of a border goes, and the shape that is drawn in it. Pure geometry
///
/// The border is a ring: the hole is the frame of the window, with rounded corners,
/// and the ring is `width` points thick all around. A border that glows has a margin around the ring,
/// where the glow fades out.
///
/// With square corners the outer edge of the ring is a plain rectangle, while the hole keeps the rounded corners
/// of the window: the ring fills the corners that the window leaves empty, and the window looks square
struct BorderGeometry: Equatable, Sendable {
    /// The frame of the panel: the frame of the window, snapped to the pixels of its screen and
    /// grown by the width of the border and by the margin of the glow. In the coordinates of the layout (Y grows downwards)
    var panelFrame: CGRect
    /// The thickness of the ring, snapped to pixels. At least one pixel
    var width: CGFloat
    /// The radius of the corners of the hole
    var innerRadius: CGFloat
    /// The outer edge of the ring is square, and the ring fills the rounded corners of the window
    var squareCorners: Bool
    /// The blur radius of the glow: twice the standard deviation of its gaussian falloff. 0: no glow
    var glowRadius: CGFloat
    /// The room around the ring for the glow, snapped to pixels: three standard deviations. The glow is gone
    /// before that (at about two), so the edge of the panel never cuts it. 0 without glow
    var glowMargin: CGFloat
    /// Pixels per point
    var scale: CGFloat

    init(frame: CGRect, width: CGFloat, cornerRadius: CGFloat, squareCorners: Bool = false, glowRadius: CGFloat = 0, scale: CGFloat) {
        let scale = scale > 0 ? scale : 1
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = snap(frame.minX), minY = snap(frame.minY)
        let hole = CGRect(x: minX, y: minY, width: max(snap(frame.maxX) - minX, 0), height: max(snap(frame.maxY) - minY, 0))
        self.scale = scale
        self.width = max(snap(width), 1 / scale)
        self.innerRadius = min(max(cornerRadius, 0), hole.width / 2, hole.height / 2)
        self.squareCorners = squareCorners
        self.glowRadius = max(glowRadius, 0)
        self.glowMargin = (self.glowRadius * 1.5 * scale).rounded(.up) / scale
        self.panelFrame = hole.insetBy(dx: -self.width - glowMargin, dy: -self.width - glowMargin)
    }

    init(_ item: BorderItem, scale: CGFloat) {
        self.init(
            frame: item.frame,
            width: item.width,
            cornerRadius: item.cornerRadius,
            squareCorners: item.squareCorners,
            glowRadius: item.glowRadius,
            scale: scale,
        )
    }

    /// The hole, in the coordinates of the panel
    var innerRect: CGRect { outerRect.insetBy(dx: width, dy: width) }
    /// The outer edge of the ring, in the coordinates of the panel: the whole panel, but for the margin of the glow
    var outerRect: CGRect { CGRect(origin: .zero, size: panelFrame.size).insetBy(dx: glowMargin, dy: glowMargin) }
    /// The outer edge is parallel to the inner one. Square windows, and square corners, get a square border
    var outerRadius: CGFloat { squareCorners || innerRadius <= 0 ? 0 : innerRadius + width }

    /// The frame of the panel for AppKit: the origin is the bottom left corner of the main screen, Y grows upwards
    func appKitFrame(mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: panelFrame.minX, y: mainScreenHeight - panelFrame.maxY, width: panelFrame.width, height: panelFrame.height)
    }

    /// The ring. To be filled with the even-odd rule. Symmetric, so it doesn't matter which way Y grows
    func path() -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(in: outerRect, cornerWidth: outerRadius, cornerHeight: outerRadius)
        if innerRect.width > 0 && innerRect.height > 0 {
            path.addRoundedRect(in: innerRect, cornerWidth: innerRadius, cornerHeight: innerRadius)
        }
        return path
    }
}

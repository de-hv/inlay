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
/// and the ring is `width` points thick all around
struct BorderGeometry: Equatable, Sendable {
    /// The frame of the panel: the frame of the window, snapped to the pixels of its screen and
    /// grown by the width of the border. In the coordinates of the layout (Y grows downwards)
    var panelFrame: CGRect
    /// The thickness of the ring, snapped to pixels. At least one pixel
    var width: CGFloat
    /// The radius of the corners of the hole
    var innerRadius: CGFloat

    init(frame: CGRect, width: CGFloat, cornerRadius: CGFloat, scale: CGFloat) {
        let scale = scale > 0 ? scale : 1
        func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
        let minX = snap(frame.minX), minY = snap(frame.minY)
        let hole = CGRect(x: minX, y: minY, width: max(snap(frame.maxX) - minX, 0), height: max(snap(frame.maxY) - minY, 0))
        self.width = max(snap(width), 1 / scale)
        self.innerRadius = min(max(cornerRadius, 0), hole.width / 2, hole.height / 2)
        self.panelFrame = hole.insetBy(dx: -self.width, dy: -self.width)
    }

    init(_ item: BorderItem, scale: CGFloat) {
        self.init(frame: item.frame, width: item.width, cornerRadius: item.cornerRadius, scale: scale)
    }

    /// The hole, in the coordinates of the panel
    var innerRect: CGRect { outerRect.insetBy(dx: width, dy: width) }
    /// The outer edge of the ring, in the coordinates of the panel: the whole panel
    var outerRect: CGRect { CGRect(origin: .zero, size: panelFrame.size) }
    /// The outer edge is parallel to the inner one. Square windows get a square border
    var outerRadius: CGFloat { innerRadius > 0 ? innerRadius + width : 0 }

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

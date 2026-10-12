import AppKit

/// The window of one border: transparent, click-through, never focused, never listed anywhere.
/// It only holds a shape layer, and the layer of the glow. Moving the panel doesn't redraw anything
final class BorderPanel: NSPanel {
    private let borderView = BorderView()
    private(set) var geometry: BorderGeometry? = nil
    private var color: Rgba? = nil
    /// The glow that the layer of the glow shows
    private var glow: BorderGlow? = nil

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 8, height: 8), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isFloatingPanel = false
        // The normal level, the same one as the windows it decorates: the panel is ordered right above its window.
        // See: BorderStacking
        level = .normal
        // transient: hidden in Mission Control, and not a window of its own in the Spaces
        // ignoresCycle: not a part of the cmd-` cycle
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        isMovable = false
        setAccessibilityElement(false)
        contentView = borderView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Makes the panel show the border. Only what is different from what it shows already is changed
    func apply(_ geometry: BorderGeometry, color: Rgba, mainScreenHeight: CGFloat) {
        let frame = geometry.appKitFrame(mainScreenHeight: mainScreenHeight)
        if self.frame != frame { setFrame(frame, display: false) }
        // The shape only depends on the size: moving the panel doesn't rebuild it
        let previous = self.geometry
        if previous?.panelFrame.size != geometry.panelFrame.size || previous?.width != geometry.width ||
            previous?.innerRadius != geometry.innerRadius || previous?.glowMargin != geometry.glowMargin
        {
            borderView.shape.path = geometry.path()
            borderView.glow.frame = CGRect(origin: .zero, size: geometry.panelFrame.size)
        }
        if self.color != color { borderView.shape.fillColor = color.cgColor }
        self.geometry = geometry
        self.color = color

        // The image of the glow is drawn again only if it would be another one. See: BorderGlow
        let glow = BorderGlow(geometry, color: color)
        if glow == self.glow { return }
        self.glow = glow
        borderView.glow.contents = glow?.image()
        borderView.glow.contentsCenter = glow?.center ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        borderView.glow.contentsScale = geometry.scale
    }
}

/// A layer-backed view whose layer is the shape of the border
final class BorderView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Not supported") }

    var shape: CAShapeLayer { layer as! CAShapeLayer }

    /// The glow around the ring. It never overlaps the ring: its image is empty there. See: BorderGlow
    let glow: CALayer = {
        let glow = CALayer()
        glow.contentsGravity = .resize
        glow.actions = ["contents": NSNull(), "contentsCenter": NSNull(), "contentsScale": NSNull(), "bounds": NSNull(), "position": NSNull()]
        return glow
    }()

    override func makeBackingLayer() -> CALayer {
        let shape = CAShapeLayer()
        shape.fillRule = .evenOdd
        shape.strokeColor = nil
        shape.lineWidth = 0
        // No implicit animations: a border must never trail behind its window
        shape.actions = ["path": NSNull(), "fillColor": NSNull(), "bounds": NSNull(), "position": NSNull(), "contentsScale": NSNull()]
        shape.addSublayer(glow)
        return shape
    }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The panel has moved to a screen with another pixel density
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = unsafe window?.backingScaleFactor { layer?.contentsScale = scale }
    }
}

import AppKit

/// The window of one border: transparent, click-through, never focused, never listed anywhere.
/// It only holds a shape layer. Moving the panel doesn't redraw anything
final class BorderPanel: NSPanel {
    private let borderView = BorderView()
    private(set) var geometry: BorderGeometry? = nil

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

    func apply(_ geometry: BorderGeometry, mainScreenHeight: CGFloat) {
        let frame = geometry.appKitFrame(mainScreenHeight: mainScreenHeight)
        if self.frame != frame { setFrame(frame, display: false) }
        // The shape only depends on the size: moving the panel doesn't rebuild it
        let previous = self.geometry
        if previous?.panelFrame.size != geometry.panelFrame.size || previous?.width != geometry.width || previous?.innerRadius != geometry.innerRadius {
            borderView.shape.path = geometry.path()
        }
        self.geometry = geometry
    }

    func setColor(_ color: Rgba) {
        borderView.shape.fillColor = color.cgColor
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

    override func makeBackingLayer() -> CALayer {
        let shape = CAShapeLayer()
        shape.fillRule = .evenOdd
        shape.strokeColor = nil
        shape.lineWidth = 0
        // No implicit animations: a border must never trail behind its window
        shape.actions = ["path": NSNull(), "fillColor": NSNull(), "bounds": NSNull(), "position": NSNull(), "contentsScale": NSNull()]
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

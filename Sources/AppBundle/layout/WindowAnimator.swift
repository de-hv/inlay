import AppKit
import Common

/// A tiling window sliding from one frame to another. Pure.
/// The frames are in the coordinates of the layout: the origin is the top left corner of the main screen, Y grows downwards
struct FrameAnimation: Equatable, Sendable {
    var from: CGRect
    var to: CGRect
    var start: ContinuousClock.Instant
    var duration: Duration

    /// 0 when it starts, 1 once it is over
    func progress(at now: ContinuousClock.Instant) -> Double {
        guard duration > .zero else { return 1 }
        return min(max((now - start) / duration, 0), 1)
    }

    func isFinished(at now: ContinuousClock.Instant) -> Bool { progress(at: now) >= 1 }

    /// Where the window is at that instant. Exactly `to` once it is over
    func frame(at now: ContinuousClock.Instant) -> CGRect {
        isFinished(at: now) ? to : Self.interpolate(from, to, Self.ease(progress(at: now)))
    }

    /// Ease out: quick to leave, gentle to arrive. The same curve as the focus marker of the menu bar item
    static func ease(_ progress: Double) -> Double { 1 - pow(1 - progress, 3) }

    static func interpolate(_ from: CGRect, _ to: CGRect, _ progress: Double) -> CGRect {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        return CGRect(x: mix(from.minX, to.minX), y: mix(from.minY, to.minY), width: mix(from.width, to.width), height: mix(from.height, to.height))
    }
}

/// Slides the tiling windows to the frames that the layout gives them, when the layout changes because a window
/// opened or closed, or because a window was moved with 'swap' or 'move'. See: requestAnimatedLayout, [animations]
///
/// macOS doesn't let Inlay move the windows of other apps any other way than through the Accessibility API, one frame
/// at a time. A frame that an app hasn't applied yet is dropped when the next one comes (MacApp.setAxFrame), so a window
/// that is slow to resize skips frames. The last frame is always the one of the layout.
///
/// The border of a window follows it: BordersSnapshot asks for the frame of the animation. See: currentFrame
@MainActor
final class WindowAnimator {
    static let shared = WindowAnimator()

    private var animations: [UInt32: (window: Window, animation: FrameAnimation)] = [:]
    /// The windows whose size the current animation has already set. While the size doesn't change, only the position is
    /// set: the app doesn't have to lay out its content again
    private var sized: Set<UInt32> = []
    /// The workspace that each screen showed in the previous layout pass, by the top left corner of the screen
    private var shownWorkspaces: [CGPoint: String] = [:]
    /// The workspaces that come in during this layout pass -> how far from their tiles their windows start
    private var slidingIn: [String: CGSize] = [:]
    /// The windows that slide out of the screen -> what happens to them once they are out (they are hidden in a corner)
    private var slideOutEnds: [UInt32: @MainActor () async -> Void] = [:]
    private var task: Task<Void, Never>? = nil
    /// When something asked for the next layout to be animated. See: requestAnimatedLayout
    private var requestedAt: ContinuousClock.Instant? = nil
    /// The tests turn the animations on to test them. Otherwise every layout of every test would have to wait for them
    var isEnabledInTests = false

    private static let frameInterval: Duration = .milliseconds(8)
    /// A request older than this belongs to a layout that never happened (a cancelled refresh session):
    /// it must not animate a later one, like the switch to another workspace
    private static let requestLifetime: Duration = .seconds(1)

    private init() {}

    /// The layout of the visible workspaces is about to change in a way that is worth animating:
    /// a window opened or closed, or a window was moved with 'swap' or 'move'
    func requestAnimatedLayout() {
        requestedAt = .now
    }

    var isAnimatedLayoutRequested: Bool {
        requestedAt.map { .now - $0 < Self.requestLifetime } ?? false
    }

    /// The windows have been laid out. See: layoutWorkspaces
    func layoutDidFinish() {
        requestedAt = nil
        slidingIn = [:]
    }

    /// Before the layout of the visible workspaces: the screens that show another workspace than in the previous pass
    /// slide their windows. Returns the workspaces that are left -> how far their windows slide out.
    /// The windows of the workspace that is shown slide in. See: WorkspaceSlide
    func beginLayout(_ monitors: [any MonitorInfo]) -> [String: CGSize] {
        slidingIn = [:]
        var shown: [CGPoint: String] = [:]
        for monitor in monitors { shown[monitor.rect.topLeftCorner] = monitor.activeWorkspace.name }
        let previous = shownWorkspaces
        shownWorkspaces = shown
        let mode = config.animations.workspaceSwitch
        guard mode != .off, duration > .zero else { return [:] }
        let order = Workspace.all.map(\.name)
        let screens = monitors.map { CGRect($0.rect) }
        var slidingOut: [String: CGSize] = [:]
        for (index, monitor) in monitors.enumerated() {
            let new = monitor.activeWorkspace.name
            // The workspace that was left is gone (it had no windows), or another screen shows it now
            guard let old = previous[monitor.rect.topLeftCorner], old != new, !shown.values.contains(old),
                  let direction = WorkspaceSlide.direction(from: old, to: new, order: order) else { continue }
            var others = screens
            others.remove(at: index)
            guard let slide = WorkspaceSlide.slide(mode, screens[index], others: others, direction: direction) else {
                DebugStats.count("animation.workspace-switch.blocked")
                continue
            }
            DebugStats.count("animation.workspace-switch.\(slide.name)")
            slidingIn[new] = slide.slidingIn
            slidingOut[old] = slide.slidingOut
        }
        return slidingOut
    }

    /// Slides a tiling window of the workspace that is left out of the screen, by `distance`, and then runs `end`,
    /// which hides it. See: layoutWorkspaces
    func slideOut(_ window: Window, distance: CGSize, then end: @escaping @MainActor () async -> Void) {
        if slideOutEnds[window.windowId] != nil { return }
        let now: ContinuousClock.Instant = .now
        guard let from = currentFrame(window.windowId) ?? (window.lastAppliedLayoutPhysicalRect ?? window.fullscreenFrame).map(CGRect.init) else {
            Task { @MainActor in await end() }
            return
        }
        slideOutEnds[window.windowId] = end
        start(window, FrameAnimation(from: from, to: from.offsetBy(dx: distance.width, dy: distance.height), start: now, duration: duration), now: now)
    }

    /// The window is sliding out of the screen: it is hidden once it is out
    func isSlidingOut(_ windowId: UInt32) -> Bool { slideOutEnds[windowId] != nil }

    private var duration: Duration {
        if isUnitTest && !isEnabledInTests { return .zero }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .zero }
        return config.animations.effectiveDuration
    }

    /// Puts a tiling window in the frame of the layout: right away, or sliding there if the layout is animated.
    ///
    /// - Parameter previous: the frame that the previous layout gave to the window. The window slides from there,
    ///   or grows from the center of its tile if it is new (Window.isEntering), or comes in from the side of the screen
    ///   if its workspace is being switched to (see beginLayout), or goes on from where it is if it is already sliding
    func setFrame(_ window: Window, _ rect: Rect, previous: Rect?) {
        let target = CGRect(rect)
        let now: ContinuousClock.Instant = .now
        let current = animations[window.windowId]
        let isEntering = window.isEntering
        window.isEntering = false
        // The layout runs more than once for the same change (the light session, then the complete one)
        if let current, current.animation.to == target { return }
        // Shown again while it was sliding out: it isn't hidden
        slideOutEnds[window.windowId] = nil
        let duration = duration
        let slide = window.nodeWorkspace.flatMap { slidingIn[$0.name] }
        let from = current.map { $0.animation.frame(at: now) }
            ?? (isEntering ? Self.entryFrame(target) : slide.map { target.offsetBy(dx: $0.width, dy: $0.height) } ?? previous.map(CGRect.init))
        guard isAnimatedLayoutRequested || slide != nil, duration > .zero, let from, from != target else {
            animations[window.windowId] = nil
            window.setAxFrame(target.origin, target.size)
            return
        }
        DebugStats.count("animation.started")
        start(window, FrameAnimation(from: from, to: target, start: now, duration: duration), now: now)
    }

    private func start(_ window: Window, _ animation: FrameAnimation, now: ContinuousClock.Instant) {
        animations[window.windowId] = (window, animation)
        sized.remove(window.windowId)
        tick(now: now)
        startLoop()
    }

    /// How big a new window is when it starts to grow, as a fraction of its tile: like the 'popin' of Hyprland
    static let entryScale: CGFloat = 0.8

    /// Where a new window starts: smaller than its tile, in its center
    static func entryFrame(_ tile: CGRect) -> CGRect {
        tile.insetBy(dx: tile.width * (1 - entryScale) / 2, dy: tile.height * (1 - entryScale) / 2)
    }

    /// Something else places the window: hiding it in a corner, the mouse, the fullscreen
    func cancel(_ windowId: UInt32) {
        animations[windowId] = nil
        slideOutEnds[windowId] = nil
    }

    /// Where the window is while it slides. nil if it isn't sliding
    func currentFrame(_ windowId: UInt32) -> CGRect? {
        animations[windowId]?.animation.frame(at: .now)
    }

    var isAnimating: Bool { !animations.isEmpty }

    /// Stops every animation where it is
    func cancelAll() {
        animations = [:]
        slideOutEnds = [:]
        slidingIn = [:]
        shownWorkspaces = [:]
    }

    private func startLoop() {
        // The tests drive the frames themselves. See: tick
        guard task == nil, !isUnitTest else { return }
        task = Task { [weak self] in
            while let self, self.isAnimating, !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                self.tick(now: .now)
            }
            self?.task = nil
        }
    }

    /// Moves every sliding window to its frame of that instant, and the borders with them
    func tick(now: ContinuousClock.Instant) {
        for (windowId, (window, animation)) in animations {
            // The window has closed, or the mouse has taken it
            if window.parent == nil || windowId == currentlyManipulatedWithMouseWindowId {
                animations[windowId] = nil
                slideOutEnds[windowId] = nil
                continue
            }
            let isFinished = animation.isFinished(at: now)
            // Whole points: a fraction of a point makes some apps lay out their content again for nothing
            let frame = isFinished ? animation.to : animation.frame(at: now).integral(roundingTo: 1)
            DebugStats.count("animation.frame")
            // The size is set in the first frame and in the last one. In between, only if it changes
            let movesOnly = !isFinished && animation.from.size == animation.to.size && sized.contains(windowId)
            window.setAxFrame(frame.origin, movesOnly ? nil : frame.size)
            sized.insert(windowId)
            if isFinished {
                animations[windowId] = nil
                sized.remove(windowId)
                if let end = slideOutEnds.removeValue(forKey: windowId) {
                    Task { @MainActor in await end() }
                }
            }
        }
        BordersController.shared.refresh()
    }
}

/// The slide of the windows when a screen switches workspaces. Pure
enum WorkspaceSlide {
    /// 1: the workspace that is shown comes after the one that is left, in the order of the menu bar item. Its windows come
    /// in from the right, and the others go out by the left. -1: the other way. nil if one of them isn't in the order
    static func direction(from old: String, to new: String, order: [String]) -> CGFloat? {
        guard let oldIndex = order.firstIndex(of: old), let newIndex = order.firstIndex(of: new), oldIndex != newIndex else { return nil }
        return newIndex > oldIndex ? 1 : -1
    }

    enum Axis: String, Equatable, Sendable {
        /// Out by one side of the screen and in by the other
        case horizontal
        /// Through the bottom of the screen: out downwards, and in from below. macOS doesn't let a window above the
        /// menu bar, so the top of the screen can't be used
        case vertical
    }

    /// How the windows of a screen slide, so that they never cross another screen: sideways if there is no screen on its
    /// left or on its right, else through its bottom if there is no screen below it. nil: they can't slide.
    /// The frames are in the coordinates of the layout: Y grows downwards
    static func axis(_ screen: CGRect, others: [CGRect]) -> Axis? {
        if !others.contains(where: { $0.minY < screen.maxY && $0.maxY > screen.minY }) { return .horizontal }
        if !others.contains(where: { $0.minX < screen.maxX && $0.maxX > screen.minX && $0.minY >= screen.midY }) { return .vertical }
        return nil
    }

    /// How far from their tiles the windows that come in start, and how far the windows that go out go.
    /// Horizontally, toward a later workspace they move to the left, and to the right toward an earlier one.
    /// Vertically, always down and up through the bottom of the screen
    static func offsets(_ axis: Axis, direction: CGFloat, screen: CGSize) -> (slidingIn: CGSize, slidingOut: CGSize) {
        switch axis {
            case .horizontal: (CGSize(width: direction * screen.width, height: 0), CGSize(width: -direction * screen.width, height: 0))
            case .vertical: (CGSize(width: 0, height: screen.height), CGSize(width: 0, height: screen.height))
        }
    }

    struct Slide: Equatable, Sendable {
        var slidingIn: CGSize
        var slidingOut: CGSize
        /// For the counters of DebugStats
        var name: String
    }

    /// How the windows of a screen slide with the direction chosen in the config, without crossing another screen.
    /// nil: they can't slide.
    ///
    /// - horizontal: from side to side. With another screen on one side, in and out by the free side. With screens on
    ///   both sides, no slide
    /// - vertical: through the bottom. With another screen below, no slide (the top can't be used: macOS doesn't let
    ///   a window above the menu bar)
    /// - auto: horizontal without screens on the sides, else vertical. See: axis
    static func slide(_ mode: WorkspaceSwitch, _ screen: CGRect, others: [CGRect], direction: CGFloat) -> Slide? {
        func make(_ axis: Axis) -> Slide {
            let offsets = offsets(axis, direction: direction, screen: screen.size)
            return Slide(slidingIn: offsets.slidingIn, slidingOut: offsets.slidingOut, name: axis.rawValue)
        }
        let below = others.contains { $0.minX < screen.maxX && $0.maxX > screen.minX && $0.minY >= screen.midY }
        switch mode {
            case .off: return nil
            case .auto: return axis(screen, others: others).map(make)
            case .vertical: return below ? nil : make(.vertical)
            case .horizontal:
                let beside = others.filter { $0.minY < screen.maxY && $0.maxY > screen.minY }
                let left = beside.contains { $0.midX < screen.midX }
                let right = beside.contains { $0.midX >= screen.midX }
                switch (left, right) {
                    case (false, false): return make(.horizontal)
                    case (true, true): return nil
                    // In and out by the free side: right if the screen on the left blocks, left otherwise
                    case (true, false), (false, true):
                        let free = CGSize(width: (left ? 1 : -1) * screen.width, height: 0)
                        return Slide(slidingIn: free, slidingOut: free, name: "horizontal-free-side")
                }
        }
    }
}

extension CGRect {
    init(_ rect: Rect) {
        self.init(x: rect.topLeftX, y: rect.topLeftY, width: rect.width, height: rect.height)
    }

    /// The rect with its origin and its size rounded to multiples of `step`
    fileprivate func integral(roundingTo step: CGFloat) -> CGRect {
        func round(_ value: CGFloat) -> CGFloat { (value / step).rounded() * step }
        return CGRect(x: round(minX), y: round(minY), width: round(width), height: round(height))
    }
}

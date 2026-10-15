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
    }

    private var duration: Duration {
        if isUnitTest && !isEnabledInTests { return .zero }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return .zero }
        return config.animations.effectiveDuration
    }

    /// Puts a tiling window in the frame of the layout: right away, or sliding there if the layout is animated.
    ///
    /// - Parameter previous: the frame that the previous layout gave to the window. The window slides from there,
    ///   or out of the window it splits if it is new (Window.entryFrame), or from where it is if it is already sliding
    func setFrame(_ window: Window, _ rect: Rect, previous: Rect?) {
        let target = CGRect(rect)
        let now: ContinuousClock.Instant = .now
        let current = animations[window.windowId]
        let entryFrame = window.entryFrame
        window.entryFrame = nil
        // The layout runs more than once for the same change (the light session, then the complete one)
        if let current, current.animation.to == target { return }
        let duration = duration
        let from = current.map { $0.animation.frame(at: now) } ?? entryFrame.map(CGRect.init) ?? previous.map(CGRect.init)
        guard isAnimatedLayoutRequested, duration > .zero, let from, from != target else {
            animations[window.windowId] = nil
            window.setAxFrame(target.origin, target.size)
            return
        }
        DebugStats.count("animation.started")
        animations[window.windowId] = (window, FrameAnimation(from: from, to: target, start: now, duration: duration))
        tick(now: now)
        startLoop()
    }

    /// Something else places the window: hiding it in a corner, the mouse, the fullscreen
    func cancel(_ windowId: UInt32) {
        animations[windowId] = nil
    }

    /// Where the window is while it slides. nil if it isn't sliding
    func currentFrame(_ windowId: UInt32) -> CGRect? {
        animations[windowId]?.animation.frame(at: .now)
    }

    var isAnimating: Bool { !animations.isEmpty }

    /// Stops every animation where it is
    func cancelAll() {
        animations = [:]
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
                continue
            }
            let isFinished = animation.isFinished(at: now)
            // Whole points: a fraction of a point makes some apps lay out their content again for nothing
            let frame = isFinished ? animation.to : animation.frame(at: now).integral(roundingTo: 1)
            DebugStats.count("animation.frame")
            window.setAxFrame(frame.origin, frame.size)
            if isFinished { animations[windowId] = nil }
        }
        BordersController.shared.refresh()
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

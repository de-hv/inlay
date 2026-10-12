/// Draws something again only when what it is drawn from has changed, however often and for whatever reason
/// it is asked to.
///
/// Drawing can cause the very event that asks to draw again: a new image in the menu bar item makes AppKit redraw
/// the copies of the item for the other displays, which changes the appearance of its button for a moment, which is
/// what the item observes to follow the menu bar. Without this, such a loop keeps the main thread drawing forever
@MainActor
final class CoalescedRedraw<Key: Equatable> {
    /// The prefix of its counters. See: DebugStats
    private let name: String
    /// Everything that the drawing depends on, right now. It must be cheap. nil: there is nothing to draw (yet)
    private let key: @MainActor () -> Key?
    private let draw: @MainActor (Key) -> Void
    private var drawn: Key? = nil
    private var isScheduled = false

    init(name: String, key: @escaping @MainActor () -> Key?, draw: @escaping @MainActor (Key) -> Void) {
        self.name = name
        self.key = key
        self.draw = draw
    }

    /// Something that the drawing may depend on has changed. Any number of requests in a row end up in a single
    /// `drawIfChanged`, once the caller is done
    /// - Parameter reason: what asks. Only for the counters
    func request(_ reason: String) {
        DebugStats.count("\(name).request.\(reason)")
        if isScheduled { return }
        isScheduled = true
        Task { @MainActor [weak self] in
            self?.isScheduled = false
            self?.drawIfChanged()
        }
    }

    /// Draws right now, unless the last drawing was made from the same key
    func drawIfChanged() {
        guard let key = key() else { return }
        if key == drawn {
            DebugStats.count("\(name).skipped-same")
            return
        }
        drawn = key
        DebugStats.count("\(name).drawn")
        draw(key)
    }
}

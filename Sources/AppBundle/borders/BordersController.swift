import AppKit
import Common

/// Shows the borders of the windows. It is driven by the model: publishUiState calls `refresh`, the controller compares
/// the new snapshot with the borders on the screen, and creates, moves, recolors or destroys only what has changed.
///
/// Z order. A border is a panel of Inlay in the normal window level, ordered right above the window it decorates with
/// `NSWindow.order(.above, relativeTo:)`. The window server accepts the number of a window of another app there, so
/// a floating window of another app covers the borders of the windows behind it. The window server doesn't keep
/// the two windows together: when the window is raised, the panel stays where it was. That's why the order is checked
/// (one cheap call, `NSWindow.windowNumbers`) on every refresh, and fixed only for the panels that are out of place.
///
/// The refresh runs before the apps have reacted to the new frames and to the new focus. So a short while after it,
/// the controller looks once more at the real windows: it fixes the order again, and it moves the borders of
/// the windows that didn't take the frame they were asked to take. It's a bounded check after a change, not polling
@MainActor
final class BordersController {
    static let shared = BordersController()

    private init() {}

    /// What the model wants
    private var wanted: [BorderItem] = []
    /// What is on the screen
    private var shown: [BorderItem] = []
    private var panels: [UInt32: BorderPanel] = [:]
    /// The real frames of the windows whose frame differs from the wanted one, and the wanted frame they were measured for
    private var measured: [UInt32: (wanted: CGRect, real: CGRect)] = [:]
    /// The screens as they were when the panels were last placed all over again. See: screensDidChange
    private var placedScreens: [BorderScreen] = []
    private var settleTasks: [Task<Void, Never>] = []
    private var observers: [any NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation? = nil

    /// The delays of the checks that follow a refresh. The apps move their windows asynchronously
    static let settleDelays: [Duration] = [.milliseconds(120), .milliseconds(600)]

    var panelCount: Int { panels.count }
    /// windowId -> the window number of the panel of its border. For debugging
    var panelNumbers: [UInt32: Int] { panels.mapValues(\.windowNumber) }

    func start() {
        if !observers.isEmpty { return }
        placedScreens = Self.screens()
        let center = NotificationCenter.default
        // The pixel density or the height of the main screen has changed: every panel must be placed again
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BordersController.shared.screensDidChange() }
        })
        // Light or dark: 'system-accent' may change with it
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { _, _ in
            MainActor.assumeIsolated { BordersController.shared.refresh() }
        }
        // 'system-accent'
        observers.append(center.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { BordersController.shared.systemColorsDidChange() }
        })
    }

    /// See: publishUiState
    func refresh() {
        if isUnitTest { return } // The tests must not open windows. They test the snapshot and the diff
        show(.fromModel())
    }

    /// The notification comes for more than the accent color, and in bursts: nothing is done unless a border changes
    private func systemColorsDidChange() {
        if isUnitTest { return }
        let snapshot = BordersSnapshot.fromModel()
        if snapshot.items == wanted {
            DebugStats.count("borders.system-colors.same")
            return
        }
        DebugStats.count("borders.system-colors.changed")
        show(snapshot)
    }

    /// Makes the borders on the screen match the snapshot
    func show(_ snapshot: BordersSnapshot) {
        DebugStats.count(snapshot.items == wanted ? "borders.snapshot.same" : "borders.snapshot.changed")
        wanted = snapshot.items
        let ids = Set(wanted.map(\.windowId))
        measured = measured.filter { ids.contains($0.key) }
        render()
        restack()
        scheduleSettle()
    }

    /// Removes every border right now. Inlay is about to quit
    func removeAll() {
        cancelSettle()
        wanted = []
        measured = [:]
        render()
    }

    private func render() {
        let real = measured.compactMapValues { $0.real }
        let stillValid = wanted.filter { measured[$0.windowId]?.wanted == $0.frame }.map(\.windowId).toSet()
        let target = BorderCorrection.corrected(wanted, actual: real.filter { stillValid.contains($0.key) })
        let ops = BordersDiff.ops(from: shown, to: target)
        if ops.isEmpty { return }
        // No screens (the displays are being reconfigured): keep what is shown, screensDidChange comes next
        guard let mainScreenHeight = Self.mainScreenHeight() else { return }
        let screens = Self.screens()
        shown = target
        var items: [UInt32: BorderItem] = [:]
        for item in target { items[item.windowId] = item }
        /// Makes the panel of the window show its border as it has to be now, color included
        func apply(_ windowId: UInt32) {
            guard let item = items[windowId] else { return }
            let geometry = BorderGeometry(item, scale: BorderScreen.scale(for: item.frame, in: screens))
            panels[windowId]?.apply(geometry, color: item.color, mainScreenHeight: mainScreenHeight)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for op in ops {
            DebugStats.count("borders.op.\(op.statName)")
            switch op {
                case .add(let item):
                    panels[item.windowId] = BorderPanel()
                    apply(item.windowId)
                // A window that gets or loses the focus changes its color, and its shape if the focused window glows:
                // the panel takes both at once, and the second of the two changes finds nothing left to do
                case .reshape(let item): apply(item.windowId)
                case .recolor(let windowId, _): apply(windowId)
                case .remove(let windowId):
                    if let panel = panels.removeValue(forKey: windowId) {
                        panel.orderOut(nil)
                        panel.close()
                    }
            }
        }
        CATransaction.commit()
    }

    /// Glues every panel to its window. See: BorderStacking
    private func restack() {
        if panels.isEmpty { return }
        DebugStats.count("borders.restack.check")
        let order = (NSWindow.windowNumbers(options: [.allApplications]) ?? []).map(\.intValue)
        let state = panels.map { BorderStacking.Panel(windowId: $0.key, panelNumber: $0.value.windowNumber, isVisible: $0.value.isVisible) }
        for op in BorderStacking.plan(order: order, panels: state) {
            switch op {
                case .orderAbove(let windowId):
                    DebugStats.count("borders.restack.order-above")
                    panels[windowId]?.order(.above, relativeTo: Int(windowId))
                case .hide(let windowId):
                    DebugStats.count("borders.restack.hide")
                    panels[windowId]?.orderOut(nil)
            }
        }
    }

    private func scheduleSettle() {
        cancelSettle()
        if panels.isEmpty { return }
        settleTasks = Self.settleDelays.map { delay in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }
                self?.settle()
            }
        }
    }

    private func cancelSettle() {
        settleTasks.forEach { $0.cancel() }
        settleTasks = []
    }

    /// Looks at the real windows once: where they are, and how they are stacked
    private func settle() {
        if panels.isEmpty { return }
        DebugStats.count("borders.settle")
        let real = Self.realFrames()
        measured = [:]
        for item in wanted {
            if let frame = real[item.windowId] { measured[item.windowId] = (item.frame, frame) }
        }
        render()
        restack()
    }

    private func screensDidChange() {
        // The notification also comes when the Dock or the menu bar change the usable part of a screen, and in bursts.
        // The panels only depend on the frames and on the pixel density of the screens
        let screens = Self.screens()
        if screens == placedScreens {
            DebugStats.count("borders.screens.same")
            return
        }
        DebugStats.count("borders.screens.changed")
        placedScreens = screens
        // Forget what is on the screen: every panel is placed and shaped again
        let items = shown
        shown = []
        for item in items {
            if let panel = panels.removeValue(forKey: item.windowId) {
                panel.orderOut(nil)
                panel.close()
            }
        }
        render()
        restack()
        scheduleSettle()
    }

    // MARK: - The real world

    /// The frames of the windows that are on the screen, in the coordinates of the layout.
    /// It needs no permission: the bounds of the windows are public, unlike their titles and their contents
    private static func realFrames() -> [UInt32: CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [:] }
        var result: [UInt32: CGRect] = [:]
        for window in list {
            guard let number = window[kCGWindowNumber as String] as? UInt32,
                  let bounds = window[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: bounds as! CFDictionary) else { continue }
            result[number] = rect
        }
        return result
    }

    static func screens() -> [BorderScreen] {
        guard let height = mainScreenHeight() else { return [] }
        return NSScreen.screens.map { screen in
            let frame = screen.frame
            return BorderScreen(frame: CGRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height), scale: screen.backingScaleFactor)
        }
    }

    /// The height of the screen with the menu bar: the one all the coordinates are relative to
    static func mainScreenHeight() -> CGFloat? {
        let screens = NSScreen.screens
        return (screens.first { $0.frame.origin == .zero } ?? screens.first)?.frame.height
    }
}

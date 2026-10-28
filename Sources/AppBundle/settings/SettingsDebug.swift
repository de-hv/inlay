import AppKit
import Common
import SwiftUI

let debugSettingsFlag = "--debug-settings"

/// `Inlay --debug-settings <config> [--inspect] [--screen-height <points>]`: the real Settings window and nothing else.
/// No window manager, no key bindings, no menu bar item, no borders, no server and no Accessibility permission.
/// The window edits the `config` file, and nothing is reloaded. Exits when the window is closed.
///
/// With `--inspect` nobody has to look at the window: every tab is shown in turn, a report of where its controls
/// ended up is printed, and the mode exits with an error if one of them can't be reached with the mouse.
///
/// With `--screen-height` the window behaves as if the usable part of the screen was that tall: a way to see it
/// on the screen of a smaller Mac
@MainActor
func runSettingsDebug(config: URL, inspect: Bool, screenHeight: CGFloat?) -> Never {
    useConfigLocation(config.path)
    NSApplication.shared.setActivationPolicy(.accessory)
    // The window as it is once Inlay manages windows: nothing is disabled
    ServerState.shared.axPermissionStatus = .granted
    ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now, url: config, errorCount: 0, warningCount: 0, isApplied: true)
    let controller = SettingsWindowController(model: SettingsModel(reloadsConfig: false))
    // The top of the real screen, so the window is where it would be
    let window = controller.makeWindow(visibleFrame: screenHeight.map { height in
        { window in
            (window.screen ?? NSScreen.main).map(\.visibleFrame).map { CGRect(x: $0.minX, y: $0.maxY - height, width: $0.width, height: height) }
        }
    })
    controller.show(window)
    if inspect {
        let problems = inspectSettingsWindow(window, config: config)
        exit(problems == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }
    let token = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
        exit(EXIT_SUCCESS)
    }
    NSApplication.shared.run()
    NotificationCenter.default.removeObserver(token)
    exit(EXIT_SUCCESS)
}

/// Prints the frames of the window, of the content of every tab and of every control in it, and whether a click
/// in the middle of each control gets to it, scrolling to it first if it takes that. The segmented controls are also
/// used: another segment is picked, which must change the config file. Returns how many things are wrong: the controls
/// that can't be reached or do nothing, and the tabs whose window isn't entirely on the screen or doesn't scroll
@MainActor
private func inspectSettingsWindow(_ window: NSWindow, config: URL) -> Int {
    func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    func text(_ rect: CGRect) -> String {
        "x=\(Int(rect.minX.rounded())) y=\(Int(rect.minY.rounded())) w=\(Int(rect.width.rounded())) h=\(Int(rect.height.rounded()))"
    }
    func subviews(of view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + subviews(of: $0) } }
    func hasControlAncestor(_ view: NSView) -> Bool {
        var ancestor = unsafe view.superview
        while let current = ancestor {
            if current is NSControl { return true }
            ancestor = unsafe current.superview
        }
        return false
    }
    guard let tabs = SettingsWindowController.pages(of: window), let root = unsafe window.contentView?.superview else { return 1 }
    var problems = 0
    for index in tabs.tabViewItems.indices {
        tabs.selectedTabViewItemIndex = index
        wait(0.8)
        let item = tabs.tabViewItems[index]
        guard let content = item.viewController?.view, let visible = tabs.visibleFrame(window) else { continue }
        let area = window.contentLayoutRect
        let isOnScreen = visible.insetBy(dx: -0.5, dy: -0.5).contains(window.frame)
        let asked = (item.viewController as? SettingsPageController)?.contentSize ?? .zero
        print("--- tab '\(item.label)'")
        print("  screen, the usable part: \(text(visible))")
        print("  window: \(text(window.frame)), entirely on the screen: \(isOnScreen)")
        print("  content area, below the title bar: \(text(area)). The tab asks for \(Int(asked.width))x\(Int(asked.height))")
        if !isOnScreen { problems += 1 }
        let page = content as? NSScrollView
        if asked.height > area.height + 0.5 {
            let before = page?.contentView.bounds.origin.y
            // What a turn of the wheel over the middle of the tab does
            if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: -5, wheel2: 0, wheel3: 0).flatMap(NSEvent.init(cgEvent:)) {
                root.hitTest(CGPoint(x: area.midX, y: area.midY))?.scrollWheel(with: event)
            }
            wait(0.5)
            let scrolls = page.map { $0.contentView.bounds.origin.y != before } ?? false
            print("  the tab is taller than its window. The mouse wheel scrolls it: \(scrolls)")
            if !scrolls { problems += 1 }
        }
        for control in subviews(of: content).compactMap({ $0 as? NSControl }) where !control.isHiddenOrHasHiddenAncestor && !hasControlAncestor(control) && !(control is NSScroller) {
            var frame = control.convert(control.bounds, to: nil)
            let wasScrolledAway = !area.contains(frame)
            if wasScrolledAway {
                if let document = page?.documentView {
                    document.scrollToVisible(control.convert(control.bounds, to: document).insetBy(dx: 0, dy: -8))
                }
                wait(0.15)
                frame = control.convert(control.bounds, to: nil)
            }
            let hit = root.hitTest(CGPoint(x: frame.midX, y: frame.midY))
            let isHit = hit.map { $0 === control || $0.isDescendant(of: control) } ?? false
            // A disabled control gives the click to what is behind it. That is how it must be
            let isReachable = area.contains(frame) && (isHit || !control.isEnabled)
            if !isReachable {
                problems += 1
                if let document = page?.documentView {
                    print("        in the page: \(text(control.convert(control.bounds, to: document))), the page is \(text(document.bounds))")
                }
            }
            let title = (control as? NSButton)?.title.takeIf { !$0.isEmpty }.map { " '\($0)'" } ?? ""
            print("  \(isReachable ? "ok  " : "FAIL") \(type(of: control))\(title) \(text(frame)) \(control.isEnabled ? "enabled" : "disabled")" +
                "\(wasScrolledAway ? ", after scrolling to it" : "") inside=\(area.contains(frame)) " +
                "click=\(isHit ? "itself" : hit.map { String(describing: type(of: $0)) } ?? "nothing")")
            // The modes of the shortcuts only change the window, not the config: they aren't picked
            guard let segmented = control as? NSSegmentedControl, segmented.isEnabled, segmented.segmentCount > 1,
                  segmented.label(forSegment: 0) != mainModeId else { continue }
            let before = try? String(contentsOf: config, encoding: .utf8)
            segmented.selectedSegment = (segmented.selectedSegment + 1) % segmented.segmentCount
            if let action = segmented.action { segmented.sendAction(action, to: segmented.target) }
            wait(0.3)
            let wrote = (try? String(contentsOf: config, encoding: .utf8)) != before
            if !wrote { problems += 1 }
            print("  \(wrote ? "ok  " : "FAIL") picking its next segment changed the config file: \(wrote)")
        }
    }
    print("problems: \(problems)")
    return problems
}

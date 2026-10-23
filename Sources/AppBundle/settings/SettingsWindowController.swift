import AppKit
import Common
import SwiftUI

/// The height of the pages of the settings window, whatever the page
let settingsContentHeight: CGFloat = 640

/// Shows the settings window: a tab per group of settings, in the toolbar, like the settings of every macOS app.
///
/// Inlay has no Dock icon and is never the active app on its own, so the window is brought forward by hand
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    let model: SettingsModel
    private var window: NSWindow?
    /// What the model was last refreshed for. See: modelDidChange
    private var lastSeenState: [AnyHashable] = []
    private var screenObservers: [any NSObjectProtocol] = []
    private var keyMonitor: Any?

    init(model: SettingsModel = SettingsModel()) {
        self.model = model
    }

    func show() {
        show(window ?? makeWindow())
    }

    func show(_ window: NSWindow) {
        self.window = window
        refresh()
        // The screen may not be the one of the last time
        tabs?.fitWindow(animate: false)
        select(model.page)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private var tabs: SettingsTabViewController? { window?.contentViewController as? SettingsTabViewController }

    /// Shows a page, from the outside
    func select(_ page: SettingsPageID) {
        model.page = page
        tabs?.selectedTabViewItemIndex = SettingsPageID.allCases.firstIndex(of: page) ?? 0
    }

    /// See: publishUiState. It's called very often, and the window only cares about the config and the state of the server
    func modelDidChange() {
        guard window?.isVisible == true, serverState != lastSeenState else { return }
        refresh()
    }

    private var serverState: [AnyHashable] {
        let state = ServerState.shared
        return [state.lastConfigLoad?.date, state.isEnabled, state.axPermissionStatus == .granted]
    }

    private func refresh() {
        lastSeenState = serverState
        DebugStats.count("settings.refresh")
        model.refresh()
    }

    /// - Parameter visibleFrame: the part of the screen that the window may use, if it isn't the real one.
    ///   The debug mode of the settings and the tests pretend a smaller screen
    func makeWindow(visibleFrame: ((NSWindow) -> CGRect?)? = nil) -> NSWindow {
        let tabs = SettingsTabViewController()
        if let visibleFrame { tabs.visibleFrame = visibleFrame }
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        for page in SettingsPageID.allCases {
            tabs.addTab(page.title, symbol: page.symbol, Self.view(of: page, model))
        }
        // A click on a tab of the toolbar: the window opens on it the next time
        tabs.onSelect = { [weak self] index in
            if let page = SettingsPageID.allCases.getOrNil(atIndex: index) { self?.model.page = page }
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = model.page.title
        // Kept after closing, so it reopens where it was
        window.isReleasedWhenClosed = false
        tabs.fitWindow(animate: false)
        window.center()
        // A display was plugged or unplugged, its resolution changed, the Dock moved, or the window went to another screen
        let changes = [(NSApplication.didChangeScreenParametersNotification, nil as NSWindow?), (NSWindow.didChangeScreenNotification, window)]
        for (name, object) in changes {
            screenObservers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak tabs] _ in
                MainActor.assumeIsolated { tabs?.fitWindow(animate: false) }
            })
        }
        installKeyMonitor(window)
        self.window = window
        return window
    }

    @ViewBuilder
    static func view(of page: SettingsPageID, _ model: SettingsModel) -> some View {
        switch page {
            case .general: GeneralSettingsView(model: model)
            case .appearance: AppearanceSettingsView(model: model)
            case .windows: WindowsSettingsView(model: model)
            case .keyboard: KeyboardSettingsView(model: model)
            case .changes: ChangesSettingsView(model: model)
        }
    }

    /// ⌥ shows the keys of every row; ⌘Z and ⇧⌘Z undo and redo the changes of the window, unless a text field is being
    /// edited (it has its own undo)
    private func installKeyMonitor(_ window: NSWindow) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        let windowNumber = window.windowNumber
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            // The parts of the event that matter, so that the event itself doesn't cross into the main actor
            let (isForWindow, isFlags, flags, key) = (
                event.windowNumber == windowNumber,
                event.type == .flagsChanged,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask),
                event.charactersIgnoringModifiers?.lowercased(),
            )
            let isConsumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isForWindow, let window = self.window else { return false }
                if isFlags {
                    self.model.isOptionHeld = flags == .option
                    return false
                }
                let isEditingText = window.firstResponder is NSTextView
                switch (flags, key) {
                    case ([.command], "z") where !isEditingText:
                        self.model.undo()
                        return true
                    case ([.command, .shift], "z") where !isEditingText:
                        self.model.redo()
                        return true
                    default:
                        return false
                }
            }
            return isConsumed ? nil : event
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.isOptionHeld = false }
        }
    }
}

/// A tab view that keeps its window as tall as the selected tab, or as tall as the screen allows
final class SettingsTabViewController: NSTabViewController {
    /// The part of the screen that the window may use
    var visibleFrame: (NSWindow) -> CGRect? = { ($0.screen ?? NSScreen.main)?.visibleFrame }
    /// A tab was selected
    var onSelect: (@MainActor (Int) -> Void)? = nil
    /// The window has the same height on every page, so that it doesn't jump from one to another: a page that is
    /// taller scrolls. Less on a screen that hasn't room for it
    var contentHeight: CGFloat = settingsContentHeight

    func addTab(_ title: String, symbol: String, _ view: some View) {
        let page = SettingsPageController(NSHostingController(rootView: AnyView(view)))
        page.title = title
        page.onContentSizeChange = { [weak self, weak page] in
            guard let self, let page, page === self.selectedPage else { return }
            // The form tells it in the middle of a layout pass of the window. Resizing the window right there leaves
            // the content view with the margins of the old size (under the toolbar, or with a gap): after the pass
            self.fitWindowAfterLayout()
        }
        let item = NSTabViewItem(viewController: page)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    private var selectedPage: SettingsPageController? {
        tabViewItems.getOrNil(atIndex: selectedTabViewItemIndex)?.viewController as? SettingsPageController
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelect?(selectedTabViewItemIndex)
        guard let window = unsafe view.window else { return }
        window.title = tabViewItem?.label ?? Strings.Settings.windowTitle
        fitWindow(animate: window.isVisible)
    }

    /// The title bar and the toolbar. Measured once, before the window is resized: right after a resize, and until the
    /// next layout pass, `contentLayoutRect` still has the old height, and a chrome worked out from it is wrong by the
    /// difference (the content then ends up taller than the window, under the toolbar, or shorter, with a gap)
    private var chromeHeight: CGFloat? = nil
    /// A resize makes the form and the scroll view change their frames, which asks for a resize again
    private var isFitting = false

    private var isFitScheduled = false

    /// fitWindow, once the layout pass that is going on is over
    func fitWindowAfterLayout() {
        if isFitScheduled { return }
        isFitScheduled = true
        RunLoop.main.perform(inModes: [.common]) { [weak self] in
            MainActor.assumeIsolated {
                self?.isFitScheduled = false
                self?.fitWindow(animate: false)
            }
        }
    }

    /// Gives the window the size of the selected tab, without leaving the screen. See: SettingsWindowSizing
    func fitWindow(animate: Bool) {
        guard !isFitting, let window = unsafe view.window, let content = selectedPage?.contentSize, content.height > 0 else { return }
        let chrome = chromeHeight ?? (window.frame.height - window.contentLayoutRect.height)
        chromeHeight = chrome
        let frame = SettingsWindowSizing.frame(
            current: window.frame,
            chromeHeight: chrome,
            content: CGSize(width: content.width, height: contentHeight),
            visible: visibleFrame(window),
        )
        if frame != window.frame {
            isFitting = true
            defer { isFitting = false }
            window.setFrame(frame, display: true, animate: animate)
        }
    }
}

/// A tab of the settings: its SwiftUI form inside of a scroll view.
///
/// The form is always as tall as its rows. On a big enough screen the window is that tall too, and nothing scrolls.
/// On a small one the window is as tall as the screen allows, and the form scrolls: every row can be reached.
/// (A window as tall as the form, whatever the screen, left a part of the form out of the screen for good:
/// the window can't be resized, and macOS doesn't let it go above the menu bar)
final class SettingsPageController: NSViewController {
    private let hosting: NSHostingController<AnyView>
    /// The form got taller or shorter: a banner, a text that takes one more line...
    var onContentSizeChange: (@MainActor () -> Void)? = nil
    private var frameObserver: (any NSObjectProtocol)?

    init(_ hosting: NSHostingController<AnyView>) {
        self.hosting = hosting
        super.init(nibName: nil, bundle: nil)
        // AppKit keeps the view of the form as tall as this size says, and tells when it changes
        hosting.sizingOptions = [.preferredContentSize]
        addChild(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The size that the form asks for
    var contentSize: CGSize { hosting.preferredContentSize }



    /// Until then, every change of the size of the form or of the window shows the top of the form again:
    /// the form and the window take their new sizes in several steps after a part of the tab replaces another one
    private var keepsTopUntil: ContinuousClock.Instant? = nil
    private var clipObserver: (any NSObjectProtocol)?

    /// Shows the top of the form, now and while the form and the window settle
    func scrollToTop() {
        keepsTopUntil = .now + .milliseconds(500)
        settleScroll()
    }

    /// The scroll position stays where the form is: never past its end, never above its top. A form that got
    /// shorter, or a window that got taller, would otherwise leave its top out of sight with nothing to scroll back
    private func settleScroll() {
        guard let scrollView = view as? NSScrollView, let form = scrollView.documentView else { return }
        let keepsTop = keepsTopUntil.map { .now < $0 } ?? false
        func settle(_ scrollView: NSScrollView) {
            let clip = scrollView.contentView
            let documentHeight = scrollView.documentView?.frame.height ?? 0
            let maxY = max(0, documentHeight - clip.bounds.height)
            let y = keepsTop ? (clip.isFlipped ? 0 : maxY) : min(max(clip.bounds.origin.y, 0), maxY)
            // Never sideways: the page is as wide as the window
            if y != clip.bounds.origin.y || clip.bounds.origin.x != 0 {
                clip.scroll(to: NSPoint(x: 0, y: y))
                scrollView.reflectScrolledClipView(clip)
            }
        }
        func inner(_ view: NSView) -> [NSScrollView] {
            view.subviews.flatMap { subview in (subview as? NSScrollView).map { [$0] } ?? inner(subview) }
        }
        settle(scrollView)
        inner(form).forEach(settle)
    }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView = TopAlignedClipView()
        scrollView.contentView.drawsBackground = false
        let form = hosting.view
        form.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = form
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            form.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            form.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])
        view = scrollView
        // AppKit resizes the view of the form when the size that the form asks for changes
        form.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: form, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onContentSizeChange?()
                self?.settleScroll()
            }
        }
        // The window got taller or shorter
        scrollView.contentView.postsFrameChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scrollView.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settleScroll() }
        }
    }

}

/// The document starts at the top of the scroll view, not at the bottom
private final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Where the settings window goes. Pure geometry, in the coordinates of the screen (y grows up)
enum SettingsWindowSizing {
    /// - Parameter current: the frame of the window. Its top left corner stays where it is, if the screen allows it
    /// - Parameter chromeHeight: the title bar and the toolbar
    /// - Parameter content: the size that the selected tab asks for
    /// - Parameter visible: the part of the screen that isn't taken by the menu bar and the Dock. nil if it isn't known
    /// - Returns: a frame that is never taller than the visible part of the screen, and that is inside of it.
    ///   When the content doesn't fit, the tab scrolls
    static func frame(current: CGRect, chromeHeight: CGFloat, content: CGSize, visible: CGRect?) -> CGRect {
        var frame = CGRect(x: current.minX, y: 0, width: content.width, height: content.height + chromeHeight)
        if let visible { frame.size.height = min(frame.height, visible.height) }
        frame.origin.y = current.maxY - frame.height
        guard let visible else { return frame }
        // The top wins over the bottom: the title bar is what moves the window
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        if frame.width <= visible.width {
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        }
        return frame
    }
}

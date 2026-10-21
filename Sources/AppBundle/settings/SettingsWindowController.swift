import AppKit
import Common
import SwiftUI

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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private var tabs: SettingsTabViewController? { window?.contentViewController as? SettingsTabViewController }

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
        tabs.addTab(Strings.Settings.general, symbol: "gearshape", GeneralSettingsView(model: model))
        tabs.addTab(Strings.Settings.themes, symbol: "paintpalette", ThemesSettingsView(model: model))
        tabs.addTab(Strings.Settings.tiling, symbol: "rectangle.split.2x2", TilingSettingsView(model: model))
        tabs.addTab(Strings.Settings.gaps, symbol: "rectangle.split.3x1", GapsSettingsView(model: model))
        tabs.addTab(Strings.Settings.animations, symbol: "wand.and.stars", AnimationsSettingsView(model: model))
        tabs.addTab(Strings.Settings.menuBar, symbol: "menubar.rectangle", MenuBarSettingsView(model: model))
        if SettingsFeatures.borders {
            tabs.addTab(Strings.Settings.borders, symbol: "rectangle.dashed", BordersSettingsView(model: model))
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = Strings.Settings.windowTitle
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
        return window
    }
}

/// A tab view that keeps its window as tall as the selected tab, or as tall as the screen allows
final class SettingsTabViewController: NSTabViewController {
    /// The part of the screen that the window may use
    var visibleFrame: (NSWindow) -> CGRect? = { ($0.screen ?? NSScreen.main)?.visibleFrame }

    func addTab(_ title: String, symbol: String, _ view: some View) {
        let page = SettingsPageController(NSHostingController(rootView: AnyView(view)))
        page.title = title
        page.onContentSizeChange = { [weak self, weak page] in
            if let self, let page, page === self.selectedPage { self.fitWindow(animate: false) }
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
        guard let window = unsafe view.window else { return }
        // The toolbar style keeps the title of the window in sync with the tab. One title for all of them is enough
        window.title = Strings.Settings.windowTitle
        fitWindow(animate: window.isVisible)
    }

    /// Gives the window the size of the selected tab, without leaving the screen. See: SettingsWindowSizing
    func fitWindow(animate: Bool) {
        guard let window = unsafe view.window, let content = selectedPage?.contentSize, content.height > 0 else { return }
        let frame = SettingsWindowSizing.frame(
            current: window.frame,
            chromeHeight: window.frame.height - window.contentLayoutRect.height,
            content: content,
            visible: visibleFrame(window),
        )
        if frame != window.frame { window.setFrame(frame, display: true, animate: animate) }
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
            MainActor.assumeIsolated { self?.onContentSizeChange?() }
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

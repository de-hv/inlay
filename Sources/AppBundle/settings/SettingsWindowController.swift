import AppKit
import Common
import SwiftUI

/// Shows the settings window: a tab per group of settings, in the toolbar, like the settings of every macOS app.
///
/// Inlay has no Dock icon and is never the active app on its own, so the window is brought forward by hand
@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    let model = SettingsModel()
    private var window: NSWindow?
    /// What the model was last refreshed for. See: modelDidChange
    private var lastSeenState: [AnyHashable] = []

    override private init() {}

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
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
        model.refresh()
    }

    func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTab(Strings.Settings.general, symbol: "gearshape", GeneralSettingsView(model: model))
        tabs.addTab(Strings.Settings.menuBar, symbol: "menubar.rectangle", MenuBarSettingsView(model: model))
        if SettingsFeatures.borders {
            tabs.addTab(Strings.Settings.borders, symbol: "rectangle.dashed", BordersSettingsView(model: model))
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = Strings.Settings.windowTitle
        // Kept after closing, so it reopens where it was
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

/// A tab view that resizes its window to the tab on show
final class SettingsTabViewController: NSTabViewController {
    func addTab(_ title: String, symbol: String, _ view: some View) {
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = [.preferredContentSize]
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        addTabViewItem(item)
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let window = unsafe view.window, let size = tabViewItem?.viewController?.view.fittingSize, size.height > 0 else { return }
        // The toolbar style keeps the title of the window in sync with the tab. One title for all of them is enough
        window.title = Strings.Settings.windowTitle
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        // The top left corner stays where it is
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

import AppKit
import Common

/// The entry point of the app. Inlay is an agent app: no Dock icon and no main menu,
/// only the menu bar item, the settings window and the window with the config diagnostics
@MainActor
public func runInlayApp() -> Never {
    // Handled before anything else: it must not ask for permissions or show the menu bar item
    if let index = CommandLine.arguments.firstIndex(of: renderMenuBarFlag) {
        guard let directory = CommandLine.arguments.getOrNil(atIndex: index + 1) else {
            exit(EXIT_CODE_TWO, err: "Missing <dir> in \(renderMenuBarFlag) flag")
        }
        do {
            try renderMenuBarSamples(to: URL(filePath: directory))
        } catch {
            exit(EXIT_CODE_TWO, err: "Can't render the menu bar item: \(error.localizedDescription)")
        }
        exit(EXIT_CODE_ZERO, out: "The menu bar item was rendered to \(directory)")
    }
    if let index = CommandLine.arguments.firstIndex(of: renderBordersFlag) {
        guard let directory = CommandLine.arguments.getOrNil(atIndex: index + 1) else {
            exit(EXIT_CODE_TWO, err: "Missing <dir> in \(renderBordersFlag) flag")
        }
        do {
            try renderBorderSamples(to: URL(filePath: directory))
        } catch {
            exit(EXIT_CODE_TWO, err: "Can't render the borders: \(error.localizedDescription)")
        }
        exit(EXIT_CODE_ZERO, out: "The borders were rendered to \(directory)")
    }
    if let index = CommandLine.arguments.firstIndex(of: debugBordersFlag) {
        let seconds = CommandLine.arguments.getOrNil(atIndex: index + 1).flatMap(Double.init) ?? 4
        runBordersDebug(seconds: min(max(seconds, 1), 60))
    }
    let app = NSApplication.shared
    let delegate = InlayAppDelegate()
    app.delegate = delegate
    initAppBundle()
    app.run()
    exit(EXIT_SUCCESS)
}

let renderMenuBarFlag = "--render-menu-bar"

@MainActor
final class InlayAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Otherwise the windows of Inlay can't get the focus and the keyboard when it doesn't run from an app bundle
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = makeMainMenu()
        MessageWindowController.shared.start()
        MenuBarController.shared.start()
        BordersController.shared.start()
    }

    /// Opening Inlay again (from Applications, Spotlight...) shows the settings.
    /// It's the way back to them when the menu bar item is hidden
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }

    /// The main menu is never shown, but its key equivalents work in the windows of Inlay: copy and paste, close...
    private func makeMainMenu() -> NSMenu {
        func submenu(_ title: String, _ items: [(String, Selector, String, NSEvent.ModifierFlags)]) -> NSMenuItem {
            let menu = NSMenu(title: title)
            for (title, action, key, modifiers) in items {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
                item.keyEquivalentModifierMask = modifiers
                menu.addItem(item)
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            return item
        }
        let main = NSMenu()
        main.addItem(submenu(inlayAppName, []))
        main.addItem(submenu("Edit", [
            ("Undo", Selector(("undo:")), "z", .command),
            ("Redo", Selector(("redo:")), "z", [.command, .shift]),
            ("Cut", #selector(NSText.cut(_:)), "x", .command),
            ("Copy", #selector(NSText.copy(_:)), "c", .command),
            ("Paste", #selector(NSText.paste(_:)), "v", .command),
            ("Select All", #selector(NSText.selectAll(_:)), "a", .command),
        ]))
        main.addItem(submenu("Window", [
            ("Close", #selector(NSWindow.performClose(_:)), "w", .command),
            ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", .command),
        ]))
        return main
    }
}

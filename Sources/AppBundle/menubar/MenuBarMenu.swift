import AppKit
import Common
import HotKey

/// The menu of the menu bar item. It is rebuilt from the model every time it opens
@MainActor
final class MenuBarMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    private let icons = AppIconCache()

    private static let iconSize: CGFloat = 16

    override init() {
        super.init()
        menu.delegate = self
        // The items are enabled by hand: which ones apply depends on the state of Inlay
        menu.autoenablesItems = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MenuBarStore.shared.refresh()
        guard let snapshot = MenuBarStore.shared.state?.snapshot else { return }
        menu.removeAllItems()
        switch snapshot.status {
            case .needsAccessibility:
                menu.addItem(item(Strings.Menu.needsAccessibility, #selector(promptForAccessibility), symbol: "exclamationmark.triangle"))
            case .paused:
                menu.addItem(item(Strings.Menu.paused, nil, isEnabled: false))
                menu.addItem(.separator())
                addConfigItems(snapshot, to: menu)
            case .running:
                if let title = Strings.Menu.configProblems(ServerState.shared.lastConfigLoad) {
                    menu.addItem(item(title, #selector(showConfigWarnings), symbol: "exclamationmark.triangle.fill"))
                    menu.addItem(.separator())
                }
                addWorkspaces(snapshot, to: menu)
                menu.addItem(.separator())
                addFocusedWindow(snapshot, to: menu)
                menu.addItem(.separator())
                addLayout(snapshot, to: menu)
                menu.addItem(.separator())
                addModes(snapshot, to: menu)
                menu.addItem(.separator())
                addConfigItems(snapshot, to: menu)
        }
        menu.addItem(.separator())
        let version = item(Strings.Menu.version, #selector(copyVersion))
        version.toolTip = Strings.Menu.copyVersionToolTip
        menu.addItem(version)
        menu.addItem(item(Strings.Menu.quit, #selector(quit), key: "q"))
    }

    // MARK: - Sections

    private func addWorkspaces(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: Strings.Menu.workspaces))
        for workspace in snapshot.workspaces {
            let item = commandItem(workspace.name, "workspace \(workspace.name)")
            item.attributedTitle = workspaceTitle(workspace, namesApps: true)
            item.state = workspace.name == snapshot.focusedWorkspace ? .on : .off
            menu.addItem(item)
        }
    }

    private func addFocusedWindow(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: Strings.Menu.focusedWindow))
        let window = snapshot.focusedWindow
        let move = item(Strings.Menu.moveTo, nil, symbol: "arrow.right.square", isEnabled: window != nil)
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for workspace in snapshot.workspaces {
            let target = commandItem(workspace.name, "move-node-to-workspace \(workspace.name)", isEnabled: workspace.name != snapshot.focusedWorkspace)
            target.attributedTitle = workspaceTitle(workspace, namesApps: false)
            target.state = workspace.name == snapshot.focusedWorkspace ? .on : .off
            submenu.addItem(target)
        }
        move.submenu = submenu
        menu.addItem(move)

        let floating = commandItem(Strings.Menu.floating, "layout floating tiling", symbol: "macwindow.on.rectangle", isEnabled: window != nil)
        floating.state = window?.isFloating == true ? .on : .off
        menu.addItem(floating)
        let fullscreen = commandItem(Strings.Menu.fullscreen, "fullscreen", symbol: "arrow.up.left.and.arrow.down.right", isEnabled: window != nil)
        fullscreen.state = window?.isFullscreen == true ? .on : .off
        menu.addItem(fullscreen)
    }

    private func addLayout(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: Strings.Menu.layout))
        // The orientation is the one of the container of the focused window, so it needs a tiling window
        let isTiling = snapshot.focusedWindow?.isFloating == false
        let horizontal = commandItem(Strings.Menu.horizontal, "layout horizontal", symbol: "rectangle.split.2x1", isEnabled: isTiling)
        horizontal.state = isTiling && snapshot.orientation == .h ? .on : .off
        menu.addItem(horizontal)
        let vertical = commandItem(Strings.Menu.vertical, "layout vertical", symbol: "rectangle.split.1x2", isEnabled: isTiling)
        vertical.state = isTiling && snapshot.orientation == .v ? .on : .off
        menu.addItem(vertical)
        menu.addItem(commandItem(Strings.Menu.balanceSizes, "balance-sizes", symbol: "equal.square"))
        menu.addItem(commandItem(Strings.Menu.resetLayout, "flatten-workspace-tree", symbol: "arrow.counterclockwise"))
    }

    private func addModes(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: Strings.Menu.bindingMode))
        // 'main' first
        for mode in [mainModeId] + config.modes.keys.filter({ $0 != mainModeId }).sorted() {
            let item = commandItem(mode, "mode \(mode)")
            item.state = mode == snapshot.mode ? .on : .off
            menu.addItem(item)
        }
    }

    private func addConfigItems(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        let isPaused = snapshot.status == .paused
        menu.addItem(item(Strings.Menu.reloadConfig, #selector(reloadConfig), symbol: "arrow.clockwise", key: "r", isEnabled: !isPaused))
        menu.addItem(item(Strings.Menu.openConfig, #selector(openConfig), symbol: "doc.text"))
        menu.addItem(item(isPaused ? Strings.Menu.resume : Strings.Menu.pause, #selector(togglePause), symbol: isPaused ? "play.circle" : "pause.circle", key: "e"))
        menu.addItem(item(Strings.Menu.settings, #selector(openSettings), symbol: "slider.horizontal.3", key: ","))
    }

    // MARK: - Items

    private func item(_ title: String, _ action: Selector?, symbol: String? = nil, key: String = "", isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    /// An item that runs a command. It shows the key binding of the main mode that runs the same command, if there is one.
    ///
    /// The binding is shown as a badge, which is only text. It isn't the key equivalent of the item: the binding belongs
    /// to the main mode, not to the menu, and pressing it while the menu is open must not choose the item
    private func commandItem(_ title: String, _ command: String, symbol: String? = nil, isEnabled: Bool = true) -> NSMenuItem {
        let item = item(title, #selector(runCommand(_:)), symbol: symbol, isEnabled: isEnabled)
        item.representedObject = command
        if let shortcut = mainModeShortcut(for: command) {
            item.badge = NSMenuItemBadge(string: shortcut)
        }
        return item
    }

    /// "4  [icon][icon] Telegram, WhatsApp", "4  [icon][icon] 2 apps" or "6  Empty"
    private func workspaceTitle(_ workspace: MenuBarSnapshot.Workspace, namesApps: Bool) -> NSAttributedString {
        let size = NSFont.menuFont(ofSize: 0).pointSize
        // Monospaced digits keep the icons in one column
        let title = NSMutableAttributedString(
            string: workspace.name + "\u{2003}",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium)],
        )
        let font = NSFont.menuFont(ofSize: size)
        guard !workspace.apps.isEmpty else {
            title.append(NSAttributedString(string: Strings.Menu.empty, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
            return title
        }
        for app in workspace.apps {
            guard let icon = icons.icon(app) else { continue }
            let attachment = NSTextAttachment()
            attachment.image = icon
            // Centred on the capital letters rather than sitting on the baseline
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
            title.append(NSAttributedString(attachment: attachment))
            title.append(NSAttributedString(string: "\u{2009}"))
        }
        let names = namesApps || workspace.apps.count == 1
            ? workspace.apps.map(\.name).joinTruncating(separator: ", ", length: 40)
            : Strings.Menu.apps(workspace.apps.count)
        title.append(NSAttributedString(string: " " + names, attributes: [.font: font]))
        return title
    }

    // MARK: - Actions

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        runMenuBarCommand(command)
    }

    @objc private func togglePause() {
        runMenuBarCommand("enable toggle", force: true)
    }

    @objc private func reloadConfig() {
        reloadConfigFromUi(warningsAsErrors: false)
    }

    @objc private func showConfigWarnings() {
        reloadConfigFromUi(warningsAsErrors: true)
    }

    @objc private func openConfig() {
        openConfigInEditor()
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func promptForAccessibility() {
        ServerState.shared.axPermissionStatus = .waitingWithPrompt
    }

    @objc private func copyVersion() {
        Strings.Menu.versionToCopy.copyToClipboard()
    }

    @objc private func quit() {
        Task.startUnstructured { @MainActor in
            terminationHandler?.beforeTermination()
            terminateApp()
        }
    }
}

/// The key binding of the main mode that runs exactly this command, as text: "⌥⇧1"
@MainActor
func mainModeShortcut(for command: String) -> String? {
    guard let target = parseCommand(command, allowExecAndForget: false, allowEval: false).cmdOrNil else { return nil }
    return (config.modes[mainModeId]?.bindings ?? [:]).values
        .filter { $0.commands.strictEquals(target) }
        .min { $0.descriptionWithKeyCode < $1.descriptionWithKeyCode }?
        .menuText
}

extension HotkeyBinding {
    /// The binding the way the menus of macOS write a shortcut: the modifiers in their usual order, and then the key
    var menuText: String {
        let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let modifiers = symbols.filter { self.modifiers.contains($0.0) }.map(\.1).joined()
        // The names of some keys start with a private use character that only means something to a key equivalent: F5
        let key = String(String.UnicodeScalarView(keyCode.description.unicodeScalars.filter { $0.properties.generalCategory != .privateUse }))
        return modifiers + (keyCode == .space ? "Space" : key)
    }
}

// MARK: - Shared with the message window

@MainActor
func reloadConfigFromUi(warningsAsErrors: Bool) {
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        try await runLightSession(.menuBarButton, token) {
            let args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []).copy(\.warningsAsErrors, warningsAsErrors)
            _ = await reloadConfig_nonCancellable(args: args)
        }
    }
}

func getTextEditorToOpenConfig() -> URL {
    NSWorkspace.shared.urlForApplication(toOpen: findCustomConfigUrl().urlOrNil ?? defaultConfigUrl)?
        .takeIf { $0.lastPathComponent != "Xcode.app" } // Blacklist Xcode. It is too heavy to open plain text files
        ?? URL(filePath: "/System/Applications/TextEdit.app")
}

/// Opens the config of the user, creating it from the built-in one if there is none yet
@MainActor
func openConfigInEditor() {
    let editor = getTextEditorToOpenConfig()
    switch findCustomConfigUrl() {
        case .file(let url):
            url.open(with: editor)
        case .noCustomConfigExists:
            let url = newUserConfigUrl
            _ = try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            _ = try? FileManager.default.copyItem(atPath: defaultConfigUrl.path, toPath: url.path)
            url.open(with: editor)
        case .ambiguousConfigError(let candidates):
            candidates.first?.open(with: editor)
    }
}

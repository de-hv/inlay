import AppKit
import Common

/// The menu of the menu bar item. It is rebuilt from the model every time it opens
@MainActor
final class MenuBarMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()

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
                addWindowsOfFocusedWorkspace(snapshot, to: menu)
                menu.addItem(.separator())
                addFocusedWindow(snapshot, to: menu)
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

    /// The windows of the focused workspace, by the name of their app, without icons: a click focuses one
    private func addWindowsOfFocusedWorkspace(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        menu.addItem(.sectionHeader(title: Strings.Menu.workspace(snapshot.focusedWorkspace)))
        let windows = focus.workspace.allLeafWindowsRecursive
        if windows.isEmpty {
            menu.addItem(item(Strings.Menu.noWindows, nil, isEnabled: false))
            return
        }
        let focusedId = focus.windowOrNil?.windowId
        for window in windows {
            let item = commandItem(window.app.name ?? "?", "focus --window-id \(window.windowId)")
            item.state = window.windowId == focusedId ? .on : .off
            menu.addItem(item)
        }
    }

    /// The only thing of the focused window that the menu changes. The rest is done with the key bindings
    private func addFocusedWindow(_ snapshot: MenuBarSnapshot, to menu: NSMenu) {
        let window = snapshot.focusedWindow
        let floating = commandItem(Strings.Menu.floating, "layout floating tiling", symbol: "macwindow.on.rectangle", isEnabled: window != nil)
        floating.state = window?.isFloating == true ? .on : .off
        menu.addItem(floating)
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

    /// An item that runs a command. The key bindings of the config aren't shown: the menu doesn't repeat them
    private func commandItem(_ title: String, _ command: String, symbol: String? = nil, isEnabled: Bool = true) -> NSMenuItem {
        let item = item(title, #selector(runCommand(_:)), symbol: symbol, isEnabled: isEnabled)
        item.representedObject = command
        return item
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

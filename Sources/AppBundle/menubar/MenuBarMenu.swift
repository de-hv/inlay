import AppKit
import Common

/// The menu of the menu bar item: native items, rebuilt from the model every time it opens. See: MenuBarCard
///
/// What Inlay is doing, the layout of the focused window in a submenu, the config, and Inlay itself. Switching
/// workspaces, focusing or moving windows and the binding modes are for the key bindings
@MainActor
final class MenuBarMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    /// What the menu shows, as of the last time it opened
    private(set) var card: MenuBarCard?

    override init() {
        super.init()
        menu.delegate = self
        // The items are enabled by hand: which ones apply depends on the state of Inlay
        menu.autoenablesItems = false
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        MenuBarStore.shared.refresh()
        guard let state = MenuBarStore.shared.state else { return }
        let card = MenuBarCard.fromModel(state)
        self.card = card
        menu.removeAllItems()
        for item in items(card) { menu.addItem(item) }
    }

    private func items(_ card: MenuBarCard) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        // What Inlay is doing: information, not actions
        switch card.status {
            case .running:
                items.append(info(Strings.Menu.workspaceAndApp(card.workspace, card.focusedApp)))
                if let mode = card.mode { items.append(info(Strings.Menu.modeHelp(mode, card.modeExitKey))) }
            case .paused:
                items.append(info(Strings.Menu.paused))
            case .needsAccessibility:
                items.append(item(.promptForAccessibility, card))
        }
        if let lastReload = card.lastReload {
            items.append(info(Strings.Menu.reloaded(RelativeDateTimeFormatter().localizedString(for: lastReload, relativeTo: .now))))
        }
        if card.configProblems != nil {
            items.append(item(.showConfigProblems, card))
            for line in card.problemLines {
                let problem = info(line)
                problem.indentationLevel = 1
                items.append(problem)
            }
        }
        if card.status == .needsAccessibility {
            return items + [.separator(), item(.quit, card, key: "q")]
        }
        items.append(.separator())
        items.append(windowItem(card))
        items.append(.separator())
        items.append(item(.reloadConfig, card, key: "r"))
        items.append(item(.openConfig, card))
        items.append(item(.openSettings, card, key: ","))
        items.append(.separator())
        items.append(item(.togglePause, card, key: "e"))
        items.append(item(.quit, card, key: "q"))
        return items
    }

    /// "Window ▸": the focused window, tiling, floating or fullscreen. Disabled without a focused window
    private func windowItem(_ card: MenuBarCard) -> NSMenuItem {
        let submenu = NSMenu(title: Strings.Menu.window)
        submenu.autoenablesItems = false
        submenu.addItem(info(card.focusedApp ?? Strings.Menu.noFocusedWindow))
        submenu.addItem(.separator())
        for layout in MenuBarCard.WindowLayout.allCases {
            let item = item(.setLayout(layout), card, title: Strings.Menu.layoutShort(layout))
            item.state = card.windowLayout == layout ? .on : .off
            submenu.addItem(item)
        }
        let item = NSMenuItem(title: Strings.Menu.window, action: nil, keyEquivalent: "")
        item.submenu = submenu
        item.isEnabled = card.windowLayout != nil
        return item
    }

    private func item(_ action: MenuBarCardAction, _ card: MenuBarCard, title: String? = nil, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title ?? action.title(card), action: #selector(run(_:)), keyEquivalent: key)
        item.target = self
        item.representedObject = action
        item.isEnabled = card.isEnabled(action)
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuBarCardAction else { return }
        // After the menu is gone: Settings, for one, opens a window
        Task.startUnstructured { @MainActor in self.perform(action) }
    }

    func perform(_ action: MenuBarCardAction) {
        switch action {
            case .setLayout(let layout):
                if let current = card?.windowLayout {
                    runMenuBarCommands(Self.layoutCommands(from: current, to: layout))
                }
            case .reloadConfig:
                reloadConfigFromUi(warningsAsErrors: false)
            case .showConfigProblems:
                reloadConfigFromUi(warningsAsErrors: true)
            case .openConfig:
                openConfigInEditor()
            case .togglePause:
                runMenuBarCommand("enable toggle", force: true)
            case .openSettings:
                SettingsWindowController.shared.show()
            case .promptForAccessibility:
                ServerState.shared.axPermissionStatus = .waitingWithPrompt
            case .quit:
                Task.startUnstructured { @MainActor in
                    terminationHandler?.beforeTermination()
                    terminateApp()
                }
        }
    }

    /// From the layout of the focused window to another one, with the commands of the key bindings: 'fullscreen'
    /// toggles it, like cmd-alt-shift-enter. Fullscreen is for a tiling window: a floating one is tiled first, so that
    /// it is laid out like with the key binding (like a window alone in its workspace: [borders.single-window])
    static func layoutCommands(from current: MenuBarCard.WindowLayout, to layout: MenuBarCard.WindowLayout) -> [String] {
        let leaveFullscreen = current == .fullscreen ? ["fullscreen"] : []
        return switch layout {
            case _ where layout == current: []
            case .tiling: leaveFullscreen + (current == .floating ? ["layout tiling"] : [])
            case .floating: leaveFullscreen + ["layout floating"]
            case .fullscreen: (current == .floating ? ["layout tiling"] : []) + ["fullscreen"]
        }
    }
}

// MARK: - What the menu shows

/// What the items of the menu do. The key bindings of the config aren't shown: the menu doesn't repeat them
enum MenuBarCardAction: Hashable, Sendable {
    /// The focused window becomes tiling, floating or fullscreen
    case setLayout(MenuBarCard.WindowLayout)
    case reloadConfig
    case showConfigProblems
    case openConfig
    case togglePause
    case openSettings
    case promptForAccessibility
    case quit

    /// The title of the item, and what VoiceOver reads
    func title(_ card: MenuBarCard) -> String {
        switch self {
            case .setLayout(let layout): Strings.Menu.layout(layout)
            case .reloadConfig: Strings.Menu.reloadConfig
            case .showConfigProblems: card.configProblems ?? ""
            case .openConfig: Strings.Menu.openConfig
            case .togglePause: card.status == .paused ? Strings.Menu.resume : Strings.Menu.pause
            case .openSettings: Strings.Menu.settings
            case .promptForAccessibility: Strings.Menu.needsAccessibility
            case .quit: Strings.Menu.quit
        }
    }
}

/// What the menu shows. Derived from the model when the menu opens
struct MenuBarCard: Equatable {
    enum WindowLayout: Hashable, Sendable, CaseIterable {
        case tiling, floating, fullscreen
    }

    var status: MenuBarSnapshot.Status
    /// The errors and the warnings of the last load of the config. nil if it had none
    var configProblems: String? = nil
    var workspace: String
    /// The focused window: the name of its app, and how it is laid out. nil without one
    var focusedApp: String? = nil
    var windowLayout: WindowLayout? = nil
    /// The binding mode, if it isn't main, and the key that goes back to main
    var mode: String? = nil
    var modeExitKey: String? = nil
    /// The first errors and warnings of the last load of the config, one line each
    var problemLines: [String] = []
    /// When the config was loaded last: a reload from the menu answers with it, now that there is no notice
    var lastReload: Date? = nil

    func isEnabled(_ action: MenuBarCardAction) -> Bool {
        switch action {
            case .reloadConfig: status != .paused
            case .setLayout: windowLayout != nil
            default: true
        }
    }

    @MainActor
    static func fromModel(_ state: MenuBarState) -> MenuBarCard {
        let snapshot = state.snapshot
        var card = MenuBarCard(status: snapshot.status, workspace: snapshot.focusedWorkspace)
        let load = ServerState.shared.lastConfigLoad
        card.lastReload = load?.date
        guard snapshot.status == .running else { return card }
        card.configProblems = Strings.Menu.configProblems(load)
        card.problemLines = (load?.problems ?? []).prefix(3).map { $0.split(separator: "\n").first.map(String.init) ?? $0 }
        if let window = focus.windowOrNil, let focused = snapshot.focusedWindow {
            card.focusedApp = window.app.name ?? "?"
            card.windowLayout = focused.isFullscreen ? .fullscreen : focused.isFloating ? .floating : .tiling
        }
        card.mode = snapshot.nonMainMode
        card.modeExitKey = card.mode.flatMap { exitKey(of: $0) }
        return card
    }
}

/// The key of a binding mode that goes back to main: esc if it does, else the first one in the order of the keys
@MainActor
private func exitKey(of mode: String) -> String? {
    let bindings = config.modes[mode]?.bindings.values.filter { $0.commands.shellOfCommandsDescription.contains("mode \(mainModeId)") } ?? []
    let keys = bindings.map(\.descriptionWithKeyNotation).sorted()
    return keys.contains("esc") ? "esc" : keys.first.map(prettyKeyNotation)
}

/// Runs commands one after the other, the way a key binding with several commands does
@MainActor
func runMenuBarCommands(_ raws: [String]) {
    let commands = raws.compactMap { parseCommand($0, allowExecAndForget: false, allowEval: false).cmdOrNil }
    guard commands.count == raws.count else {
        NSSound.beep()
        return
    }
    Task.startUnstructured { @MainActor in
        // The menu is gone by then: the commands run as if a key binding ran them
        try await Task.sleep(for: .milliseconds(120))
        guard let token: RunSessionGuard = .isServerEnabled else { return }
        try await runLightSession(.menuBarButton, token) {
            for command in commands {
                _ = await command.run(.defaultEnv, .emptyStdin)
            }
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

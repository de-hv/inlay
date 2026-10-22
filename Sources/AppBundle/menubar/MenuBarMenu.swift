import AppKit
import Common
import SwiftUI

/// The menu of the menu bar item: one card, rebuilt from the model every time it opens. See: MenuBarCardView
///
/// It is still an NSMenu: macOS closes it, gives it the material of the menus, in the appearance of the system, and
/// pops it up below the item. Its shortcuts are hidden items, so they only exist while the menu is open
@MainActor
final class MenuBarMenu: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    /// What the card shows, as of the last time the menu opened
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
        let view = NSHostingView(rootView: MenuBarCardView(card: card) { [weak self, weak menu] action in
            menu?.cancelTracking()
            // After the menu is gone: Settings, for one, opens a window
            Task.startUnstructured { @MainActor in self?.perform(action) }
        })
        view.frame.size = view.fittingSize
        let item = NSMenuItem(title: inlayAppName, action: nil, keyEquivalent: "")
        item.view = view
        item.setAccessibilityLabel(inlayAppName)
        menu.addItem(item)
        for shortcut in card.shortcuts {
            let item = NSMenuItem(title: shortcut.action.title(card), action: #selector(runShortcut(_:)), keyEquivalent: shortcut.key)
            item.target = self
            item.representedObject = shortcut.action
            item.isEnabled = card.isEnabled(shortcut.action)
            item.isHidden = true
            item.allowsKeyEquivalentWhenHidden = true
            menu.addItem(item)
        }
    }

    @objc private func runShortcut(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? MenuBarCardAction else { return }
        perform(action)
    }

    func perform(_ action: MenuBarCardAction) {
        switch action {
            case .toggleFloating:
                runMenuBarCommand("layout floating tiling")
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
            case .copyVersion:
                Strings.Menu.versionToCopy.copyToClipboard()
            case .quit:
                Task.startUnstructured { @MainActor in
                    terminationHandler?.beforeTermination()
                    terminateApp()
                }
        }
    }

    /// From the layout of the focused window to another one, with the commands of the key bindings: 'fullscreen'
    /// toggles it, like cmd-alt-ctrl-enter. Fullscreen is for a tiling window: a floating one is tiled first, so that
    /// it is laid out like with the key binding (alone in its workspace, without gaps nor border with 'gaps.smart')
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

// MARK: - The card

/// What the card of the menu does. The key bindings of the config aren't shown: the menu doesn't repeat them
enum MenuBarCardAction: Hashable, Sendable {
    case toggleFloating
    /// The focused window becomes tiling, floating or fullscreen
    case setLayout(MenuBarCard.WindowLayout)
    case reloadConfig
    case showConfigProblems
    case openConfig
    case togglePause
    case openSettings
    case promptForAccessibility
    case copyVersion
    case quit

    /// The whole name: the tooltip, what VoiceOver reads, and the title of the hidden item of a shortcut
    func title(_ card: MenuBarCard) -> String {
        switch self {
            case .toggleFloating: Strings.Menu.floating
            case .setLayout(let layout): Strings.Menu.layout(layout)
            case .reloadConfig: Strings.Menu.reloadConfig
            case .showConfigProblems: card.configProblems ?? ""
            case .openConfig: Strings.Menu.openConfig
            case .togglePause: card.status == .paused ? Strings.Menu.resume : Strings.Menu.pause
            case .openSettings: Strings.Menu.settings
            case .promptForAccessibility: Strings.Menu.needsAccessibility
            case .copyVersion: Strings.Menu.version
            case .quit: Strings.Menu.quit
        }
    }
}

/// What the card of the menu shows. Derived from the model when the menu opens
struct MenuBarCard: Equatable {
    struct Window: Equatable {
        var app: String
        var isFocused: Bool
    }

    enum WindowLayout: Hashable, Sendable, CaseIterable {
        case tiling, floating, fullscreen
    }

    struct Shortcut: Equatable {
        var action: MenuBarCardAction
        var key: String
    }

    var status: MenuBarSnapshot.Status
    /// The errors and the warnings of the last load of the config. nil if it had none
    var configProblems: String? = nil
    var workspace: String
    /// The windows of the focused workspace, by the name of their app. Only shown: a window is focused with the keys
    var windows: [Window] = []
    /// nil without a focused window
    var isFloating: Bool? = nil
    /// The focused window: the name of its app, and how it is laid out. nil without one
    var focusedApp: String? = nil
    var windowLayout: WindowLayout? = nil
    /// The binding mode, if it isn't main, and the key that goes back to main
    var mode: String? = nil
    var modeExitKey: String? = nil
    /// The first errors and warnings of the last load of the config, one line each
    var problemLines: [String] = []

    /// The marker of the focused window, and the switch when it is on: the focused color of the palette
    var accent: Rgba

    /// The row of buttons. Without the permission there is nothing to do but to grant it
    var buttons: [MenuBarCardAction] {
        status == .needsAccessibility ? [] : [.reloadConfig, .openConfig, .togglePause, .openSettings]
    }

    var shortcuts: [Shortcut] {
        let buttons: [Shortcut] = self.buttons.isEmpty ? [] : [.init(action: .reloadConfig, key: "r"), .init(action: .togglePause, key: "e"), .init(action: .openSettings, key: ",")]
        return buttons + [.init(action: .quit, key: "q")]
    }

    func isEnabled(_ action: MenuBarCardAction) -> Bool {
        switch action {
            case .reloadConfig: status != .paused
            case .toggleFloating, .setLayout: isFloating != nil
            default: true
        }
    }

    @MainActor
    static func fromModel(_ state: MenuBarState) -> MenuBarCard {
        let snapshot = state.snapshot
        let colors = state.config.colors.applying(state.config.palette, seed: state.config.paletteSeed, isDark: isSystemAppearanceDark)
        let accent = (colors.focused == .auto ? colors.accent : colors.focused).resolve(auto: .systemAccent, systemAccent: .systemAccent)
        var card = MenuBarCard(status: snapshot.status, workspace: snapshot.focusedWorkspace, accent: accent)
        guard snapshot.status == .running else { return card }
        let load = ServerState.shared.lastConfigLoad
        card.configProblems = Strings.Menu.configProblems(load)
        card.problemLines = (load?.problems ?? []).prefix(3).map { $0.split(separator: "\n").first.map(String.init) ?? $0 }
        let focusedId = focus.windowOrNil?.windowId
        card.windows = focus.workspace.allLeafWindowsRecursive.map { Window(app: $0.app.name ?? "?", isFocused: $0.windowId == focusedId) }
        card.isFloating = snapshot.focusedWindow?.isFloating
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
            _ = await reloadConfig_nonCancellable(args: args, notice: .always)
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

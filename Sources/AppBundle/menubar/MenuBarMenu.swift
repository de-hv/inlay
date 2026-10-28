import AppKit
import Common
import SwiftUI

/// The menu of the menu bar item: a panel right below the item, rebuilt from the model every time it opens.
/// See: MenuBarCard, MenuBarPanelView
///
/// What Inlay is doing, the layout of the focused window and of its workspace, the config, and Inlay itself. Switching
/// workspaces, focusing or moving windows and the binding modes are for the key bindings
@MainActor
final class MenuBarMenu: NSObject {
    /// What the menu shows, as of the last time it opened
    private(set) var card: MenuBarCard?
    private var panel: MenuBarPanel?
    private var monitors: [Any] = []
    /// Where the menu bar item is, in screen coordinates: a click on it toggles the menu, so it doesn't count as a
    /// click outside
    private var itemFrame: CGRect = .null
    /// When a click outside closed the menu last
    private var closedByClickAt: ContinuousClock.Instant?

    var isOpen: Bool { panel?.isVisible == true }

    /// A press of the item with the mouse comes after the mouse went down. That mouse down may have closed the menu
    /// already: the item can get the click through another window of the menu bar than the one of its button (macOS
    /// draws copies of the item), which the check of `itemFrame` doesn't recognize. Up to this long after a click
    /// closed the menu, a press of the item is that same click
    nonisolated static let pressAfterClose: TimeInterval = 0.6

    /// What a press of the item does to the menu: true opens it. A press while it is open closes it, and a press right
    /// after a click closed it is the end of that click: it closed the menu, and the press leaves it closed
    nonisolated static func pressOpens(isOpen: Bool, closedByClickAgo: TimeInterval?) -> Bool {
        !isOpen && !(closedByClickAgo.map { $0 < pressAfterClose } ?? false)
    }

    /// The item was pressed: opens the menu below the item, or closes it. See: pressOpens
    func toggle(at topLeft: NSPoint, on screen: NSScreen?, itemFrame: CGRect) {
        let ago = closedByClickAt.map { (ContinuousClock.now - $0) / .seconds(1) }
        closedByClickAt = nil
        if Self.pressOpens(isOpen: isOpen, closedByClickAgo: ago) {
            open(at: topLeft, on: screen, itemFrame: itemFrame)
        } else {
            close()
        }
    }

    /// The card of the model as it is now
    @discardableResult
    func update() -> MenuBarCard? {
        MenuBarStore.shared.refresh()
        guard let state = MenuBarStore.shared.state else { return nil }
        let card = MenuBarCard.fromModel(state)
        self.card = card
        return card
    }

    /// Opens the panel with its top left corner at `topLeft`, in screen coordinates, kept inside of `screen`
    func open(at topLeft: NSPoint, on screen: NSScreen?, itemFrame: CGRect) {
        guard let card = update() else { return }
        self.itemFrame = itemFrame
        let panel = panel ?? makePanel()
        self.panel = panel
        let host = NSHostingView(rootView: MenuBarPanelView(content: MenuBarPanelContent(card), run: { [weak self] in self?.run($0) }))
        let size = host.fittingSize
        panel.setContent(host, size: size)
        var origin = NSPoint(x: topLeft.x, y: topLeft.y - size.height)
        if let visible = screen?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX + Self.screenMargin), visible.maxX - size.width - Self.screenMargin)
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        startMonitoring()
    }

    func close() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        panel?.orderOut(nil)
    }

    private static let screenMargin: CGFloat = 6

    private func makePanel() -> MenuBarPanel {
        let panel = MenuBarPanel()
        panel.onCancel = { [weak self] in self?.close() }
        panel.onCommandKey = { [weak self] key in
            guard let self, let card = self.card, let action = MenuBarCardAction.forShortcut(key), card.isEnabled(action) else { return false }
            self.run(action)
            return true
        }
        return panel
    }

    /// A click anywhere but in the panel or on the item closes it, like a menu. A click on the item is left to the
    /// item, which toggles the menu. See: toggle
    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked(at: NSEvent.mouseLocation, inPanel: false) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { [weak self] event in
            let location = NSEvent.mouseLocation
            let window = event.window
            MainActor.assumeIsolated { self?.clicked(at: location, inPanel: window != nil && window === self?.panel) }
            return event
        }) { monitors.append(local) }
    }

    private func clicked(at location: NSPoint, inPanel: Bool) {
        guard !inPanel, !itemFrame.contains(location) else { return }
        close()
        closedByClickAt = .now
    }

    private func run(_ action: MenuBarCardAction) {
        close()
        // After the panel is gone: the config, for one, opens in an editor
        Task.startUnstructured { @MainActor in self.perform(action) }
    }

    func perform(_ action: MenuBarCardAction) {
        switch action {
            case .setLayout(let layout):
                if let current = card?.windowLayout {
                    runMenuBarCommands(Self.layoutCommands(from: current, to: layout))
                }
            case .arrange(let arrangement):
                runMenuBarCommands(["arrange-workspace \(arrangement.rawValue)"])
            case .reloadConfig:
                reloadConfigFromUi(warningsAsErrors: false)
            case .showConfigProblems:
                reloadConfigFromUi(warningsAsErrors: true)
            case .openConfig:
                openConfigInEditor()
            case .togglePause:
                runMenuBarCommand("enable toggle", force: true)
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
    /// The windows of the focused workspace are arranged again: 'arrange-workspace'
    case arrange(WorkspaceArrangement)
    case reloadConfig
    case showConfigProblems
    case openConfig
    case togglePause
    case promptForAccessibility
    case quit

    /// The title of the item, and what VoiceOver reads
    func title(_ card: MenuBarCard) -> String {
        switch self {
            case .setLayout(let layout): Strings.Menu.layout(layout)
            case .arrange(let arrangement): Strings.Menu.arrange(arrangement)
            case .reloadConfig: Strings.Menu.reloadConfig
            case .showConfigProblems: card.configProblems ?? ""
            case .openConfig: Strings.Menu.openConfig
            case .togglePause: card.status == .paused ? Strings.Menu.resume : Strings.Menu.pause
            case .promptForAccessibility: Strings.Menu.needsAccessibility
            case .quit: Strings.Menu.quit
        }
    }

    /// The key that runs the action with ⌘ while the menu is open. The key bindings of the config aren't these
    var shortcut: String? {
        switch self {
            case .reloadConfig: "r"
            case .togglePause: "e"
            case .quit: "q"
            default: nil
        }
    }

    static func forShortcut(_ key: String) -> MenuBarCardAction? {
        [.reloadConfig, .togglePause, .quit].first { $0.shortcut == key.lowercased() }
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
            case .arrange: status == .running
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

/// What the panel shows, line by line, derived from the card. MenuBarPanelView only lays it out
struct MenuBarPanelContent: Equatable {
    struct Problems: Equatable {
        /// The button that shows them all
        var title: String
        /// The first ones, one line each
        var lines: [String]
    }

    var title: String
    /// Under the title, dimmed: the binding mode and the key that leaves it, and when the config was loaded last
    var details: [String] = []
    var problems: Problems? = nil
    /// Without the permission there is nothing but asking for it, and quitting
    var prompt: MenuBarCardAction? = nil
    /// Tiling, floating or fullscreen, and the arrangements of the workspace. Not shown without the permission
    var showsLayouts: Bool = true
    var windowLayout: MenuBarCard.WindowLayout? = nil
    var canSetLayout: Bool = false
    var canArrange: Bool = false
    /// The buttons at the bottom, from left to right
    var footer: [Button] = []

    struct Button: Equatable {
        var action: MenuBarCardAction
        var title: String
        var symbol: String
        var isEnabled: Bool
    }

    init(_ card: MenuBarCard) {
        let ago = card.lastReload.map { Strings.Menu.reloaded(RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: .now)) }
        switch card.status {
            case .running:
                title = Strings.Menu.workspaceAndApp(card.workspace, card.focusedApp)
                if let mode = card.mode { details.append(Strings.Menu.modeHelp(mode, card.modeExitKey)) }
            case .paused:
                title = Strings.Menu.paused
            case .needsAccessibility:
                title = Strings.Menu.needsAccessibility
                prompt = .promptForAccessibility
                showsLayouts = false
        }
        if let ago { details.append(ago) }
        problems = card.configProblems.map { Problems(title: $0, lines: card.problemLines) }
        windowLayout = card.windowLayout
        canSetLayout = card.isEnabled(.setLayout(.tiling))
        canArrange = card.isEnabled(.arrange(.dwindle))
        let actions: [(MenuBarCardAction, String)] = card.status == .needsAccessibility
            ? [(.quit, "power")]
            : [
                (.reloadConfig, "arrow.clockwise"),
                (.openConfig, "doc.text"),
                (.togglePause, card.status == .paused ? "play" : "pause"),
                (.quit, "power"),
            ]
        footer = actions.map { Button(action: $0.0, title: $0.0.title(card), symbol: $0.1, isEnabled: card.isEnabled($0.0)) }
    }
}

/// The window of the menu: borderless, with the material of the menus. It takes the keyboard without making
/// Inlay the active app, like a menu
final class MenuBarPanel: NSPanel {
    /// ⌘ and a key: true if it was one of the menu
    var onCommandKey: ((String) -> Bool)?
    /// Esc
    var onCancel: (() -> Void)?
    private let effect = NSVisualEffectView()
    static let cornerRadius: CGFloat = 12

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = .roundedMask(radius: Self.cornerRadius)
        contentView = effect
    }

    func setContent(_ view: NSView, size: CGSize) {
        effect.subviews.forEach { $0.removeFromSuperview() }
        // The panel first: the content follows the size of the panel, and a content added to a panel that has yet to
        // get its size (it has none the first time) would grow by the whole size along with it, to twice its size
        setContentSize(size)
        view.frame = effect.bounds
        view.autoresizingMask = [.width, .height]
        effect.addSubview(view)
        invalidateShadow()
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers, onCommandKey?(key) == true
        {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

extension NSImage {
    /// A mask with round corners that stretches to any size: the shape of a visual effect view
    fileprivate static func roundedMask(radius: CGFloat) -> NSImage {
        let side = 2 * radius + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// "cmd-alt-ctrl-j" -> "⌃⌥⌘J", in the order macOS shows the modifiers
func prettyKeyNotation(_ binding: String) -> String {
    let symbols: [String: String] = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
    let keys: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "↩", "esc": "⎋", "space": "Space", "tab": "⇥",
        "backspace": "⌫", "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "minus": "-", "equal": "=",
        "leftSquareBracket": "[", "rightSquareBracket": "]", "quote": "'", "backtick": "`", "backslash": "\\",
    ]
    var parts = binding.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    // 'cmd-alt-minus' is written that way; a bare '-' would be an empty part
    let key = parts.popLast() ?? ""
    let modifiers = ["ctrl", "alt", "shift", "cmd"].filter(parts.contains).compactMap { symbols[$0] }.joined()
    return modifiers + (keys[key] ?? key.uppercased())
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

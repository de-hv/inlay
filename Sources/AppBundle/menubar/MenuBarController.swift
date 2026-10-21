import AppKit
import Common

/// Owns the menu bar item: draws the published `MenuBarState` into it, and opens the menu.
/// A click of the left button opens the menu, wherever it is on the item. See: opensMenu
///
/// It only reads the model through `MenuBarStore`. See: publishUiState
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private let menu = MenuBarMenu()
    private var state: MenuBarState?
    private var appearanceObservation: NSKeyValueObservation?
    private var notificationTokens: [any NSObjectProtocol] = []

    /// The focus marker sliding from the workspace focused before
    private var slide: (from: String, start: ContinuousClock.Instant)?
    private var slideTask: Task<Void, Never>?
    private var lastFocusedWorkspace: String?
    /// The only way to the image of the button. See: MenuBarDrawKey
    private lazy var redraw = CoalescedRedraw(
        name: "menu-bar.draw",
        key: { [weak self] in self?.drawKey() },
        draw: { [weak self] in self?.draw($0) },
    )

    private static let slideDuration: Duration = .milliseconds(180)
    private static let frameInterval: Duration = .milliseconds(16)

    override private init() {}

    /// Creates the item. It must be called once, after the app has finished launching
    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Remembers the position after a cmd-drag in the menu bar
        item.autosaveName = inlayAppName
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(pressed)
            // No menu is attached to the item: the left button must not open it. The action is what a press without
            // the mouse runs (VoiceOver), and what a click runs if it ever gets to the button
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // The mouse never reaches the button: a plain click must not even highlight it. See: MenuBarClickShield
            let shield = MenuBarClickShield(frame: button.bounds)
            shield.autoresizingMask = [.width, .height]
            shield.onClick = { [weak self] in self?.pressed() }
            button.addSubview(shield)
            button.setAccessibilityHelp(Strings.Item.accessibilityHelp)
            // A fixed color isn't a template image, so it has to follow the menu bar by hand.
            // AppKit also reports a change every time it redraws the copies of the item for the other displays,
            // which is every time the image changes: the request must never draw on its own. See: CoalescedRedraw
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.redraw.request("appearance") }
            }
        }
        // The accent color, and the scale of the screens
        let reasons = [(NSColor.systemColorsDidChangeNotification, "system-colors"), (NSApplication.didChangeScreenParametersNotification, "screens")]
        for (name, reason) in reasons {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.redraw.request(reason) }
            })
        }
        MenuBarStore.shared.onChange = { [weak self] in self?.render($0) }
        MenuBarStore.shared.refresh()
        if let state = MenuBarStore.shared.state { render(state) }
    }

    /// Draws the state, starting a slide when the focus moved
    private func render(_ state: MenuBarState) {
        let focused = state.snapshot.status == .running ? state.snapshot.focusedWorkspace : nil
        if let focused, let previous = lastFocusedWorkspace, previous != focused,
           state.config.theme != .minimal,
           state.snapshot.workspaces.contains(where: { $0.name == previous }),
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        {
            startSlide(from: previous)
        }
        lastFocusedWorkspace = focused
        self.state = state
        // Without the permission there is nothing but the item to tell what is going on, so it can't be hidden
        statusItem?.isVisible = state.config.enabled || state.snapshot.status == .needsAccessibility
        statusItem?.button?.toolTip = switch state.snapshot.status {
            case .running: Strings.Item.toolTip
            case .paused: Strings.Menu.paused
            case .needsAccessibility: Strings.Menu.needsAccessibility
        }
        redraw.drawIfChanged()
    }

    // MARK: - Drawing

    private func drawKey() -> MenuBarDrawKey? {
        // Asked first: it is also what ends the slide, whether there is something to draw or not
        let transition = currentTransition()
        guard let state, let button = statusItem?.button else { return nil }
        // A template image is the same over any menu bar, so the appearance of the button is left out of its key:
        // whatever AppKit does to the appearance, it can't ask for a new image. `mayShowMode` is true at least
        // whenever the layout draws the initial of the mode (MenuBarLayout.needsColor)
        let mayShowMode = state.config.showMode && state.snapshot.nonMainMode != nil
        // A palette has fixed colors: the item follows the menu bar by hand
        let followsBar = !MenuBarPalette.isTemplate(state.config.colors.applying(state.config.palette, isDark: true), needsColor: mayShowMode)
        return MenuBarDrawKey(
            state: state,
            transition: transition,
            isDarkBar: followsBar && button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            systemAccent: .systemAccent,
            scale: NSScreen.screens.map(\.backingScaleFactor).max() ?? 2,
        )
    }

    private func draw(_ key: MenuBarDrawKey) {
        let image = MenuBarRenderer.image(key)
        image?.accessibilityDescription = Strings.Item.accessibilityDescription(key.state.snapshot)
        statusItem?.button?.image = image
    }

    private func startSlide(from workspace: String) {
        slide = (workspace, .now)
        guard slideTask == nil else { return }
        slideTask = Task { [weak self] in
            while let self, self.slide != nil, !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                self.redraw.drawIfChanged()
            }
            self?.slideTask = nil
        }
    }

    /// The frame of the slide for this instant. Ends the slide once it has arrived
    private func currentTransition() -> MenuBarFocusTransition? {
        guard let slide else { return nil }
        let elapsed = (ContinuousClock.now - slide.start) / Self.slideDuration
        guard elapsed < 1 else {
            self.slide = nil
            return nil
        }
        // Ease out: quick to leave, gentle to arrive
        return MenuBarFocusTransition(from: slide.from, progress: 1 - pow(1 - elapsed, 3))
    }

    // MARK: - The menu

    /// The item was pressed: with the mouse (MenuBarClickShield), or without it (the action of the button)
    @objc private func pressed() {
        let event = NSApp.currentEvent
        let opensMenu = Self.opensMenu(
            eventType: event?.type,
            isControlPressed: event?.modifierFlags.contains(.control) == true,
            eventAge: event.map { ProcessInfo.processInfo.systemUptime - $0.timestamp },
        )
        if opensMenu { openMenu() }
    }

    /// A mouse event older than this isn't what pressed the item
    nonisolated private static let staleEventAge: TimeInterval = 1

    /// The menu opens with a plain click of the left button. The right button and a ctrl-click (the right click of
    /// a one-button mouse) do nothing.
    ///
    /// The item can also be pressed without the mouse: by VoiceOver and by the other clients of the accessibility API.
    /// That opens the menu, the only thing there is to do with the item. Such a press comes with no event of its own:
    /// the current event of the app is then missing, or it is an old event that has nothing to do with the press
    ///
    /// - Parameter eventType: the type of the current event of the app, if there is one
    /// - Parameter eventAge: how long ago the current event happened, in seconds
    nonisolated static func opensMenu(eventType: NSEvent.EventType?, isControlPressed: Bool, eventAge: TimeInterval?) -> Bool {
        guard let eventType, let eventAge, eventAge < staleEventAge else { return true }
        return switch eventType {
            case .leftMouseUp, .leftMouseDown: !isControlPressed
            case .rightMouseUp, .rightMouseDown: false
            default: true
        }
    }

    /// Room between the bottom of the menu bar and the top of the menu
    private static let menuGap: CGFloat = 3

    /// The menu pops up right below the item, without highlighting it: the item looks the same with the menu open.
    /// A menu attached to the item (`statusItem.menu`) would draw the rounded background of a pressed item behind it
    private func openMenu() {
        guard let button = statusItem?.button else { return }
        // The bottom of the menu bar is the bottom of the window of the item, which is as tall as the bar.
        // The button may be shorter
        let barBottom = unsafe button.window != nil ? button.convert(NSPoint.zero, from: nil).y : (button.isFlipped ? button.bounds.maxY : button.bounds.minY)
        let bottom = NSPoint(x: 0, y: barBottom + (button.isFlipped ? Self.menuGap : -Self.menuGap))
        // Blocks until the menu closes, like any menu
        menu.menu.popUp(positioning: nil, at: bottom, in: button)
    }
}

/// Covers the button of the menu bar item, and keeps the mouse away from it.
///
/// A button highlights itself while the mouse is held down on it, whatever its action does afterwards: a click that
/// does nothing (the right button) must not look like it did something. So the button never sees the mouse go down,
/// and the click is reported once the mouse goes up. If that opens the menu (see MenuBarController.opensMenu),
/// the item isn't highlighted either while the menu is open. See: MenuBarController.openMenu
///
/// VoiceOver and the other clients of the accessibility API don't come through here: they press the button itself.
/// Neither does a cmd-drag, which is how the items of the menu bar are moved around
final class MenuBarClickShield: NSView {
    /// A button of the mouse was released over the item
    var onClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) { super.mouseDown(with: event) }
    }

    override func mouseUp(with event: NSEvent) { onClick?() }

    override func rightMouseDown(with event: NSEvent) {}

    override func rightMouseUp(with event: NSEvent) { onClick?() }
}

/// Runs a command the same way a key binding does
@MainActor
func runMenuBarCommand(_ raw: String, force: Bool = false) {
    guard let command = parseCommand(raw, allowExecAndForget: false, allowEval: false).cmdOrNil else {
        NSSound.beep()
        return
    }
    Task.startUnstructured { @MainActor in
        guard let token: RunSessionGuard = force ? .forceRun : .isServerEnabled else { return }
        try await runLightSession(.menuBarButton, token) {
            _ = await command.run(.defaultEnv, .emptyStdin)
        }
    }
}

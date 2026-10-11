import AppKit
import Common

/// Owns the menu bar item: draws the published `MenuBarState` into it, handles the clicks in the workspaces,
/// and opens the menu.
///
/// It only reads the model through `MenuBarStore`. See: publishUiState
@MainActor
final class MenuBarController: NSObject {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private let menu = MenuBarMenu()
    private let icons = AppIconCache()
    private var state: MenuBarState?
    /// What is drawn in the item right now. The clicks are resolved against it
    private var layout: MenuBarLayout?
    private var appearanceObservation: NSKeyValueObservation?
    private var notificationTokens: [any NSObjectProtocol] = []

    /// The focus marker sliding from the workspace focused before
    private var slide: (from: String, start: ContinuousClock.Instant)?
    private var slideTask: Task<Void, Never>?
    private var lastFocusedWorkspace: String?

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
            button.action = #selector(clicked)
            // No menu is attached to the item: a click in a workspace must not open it
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // A fixed color isn't a template image, so it has to follow the menu bar by hand
            appearanceObservation = button.observe(\.effectiveAppearance) { [weak self] _, _ in
                Task { @MainActor in self?.draw() }
            }
        }
        // The accent color, and the scale of the screens
        for name in [NSColor.systemColorsDidChangeNotification, NSApplication.didChangeScreenParametersNotification] {
            notificationTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.draw() }
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
            case .running: nil
            case .paused: Strings.Menu.paused
            case .needsAccessibility: Strings.Menu.needsAccessibility
        }
        draw()
    }

    // MARK: - Drawing

    private func draw() {
        guard let state, let button = statusItem?.button else { return }
        let layout = MenuBarLayout.make(state.snapshot, state.config, transition: currentTransition(), measure: MenuBarFont.size)
        let palette = MenuBarPalette.resolve(
            state.config,
            style: layout.style,
            isDarkBar: button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua,
            systemAccent: .systemAccent,
            needsColor: layout.needsColor,
        )
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let image = MenuBarRenderer.image(layout, palette, scale: scale, icons: icons.icon)
        image?.accessibilityDescription = Strings.Item.accessibilityDescription(state.snapshot)
        button.image = image
        self.layout = layout
    }

    private func startSlide(from workspace: String) {
        slide = (workspace, .now)
        guard slideTask == nil else { return }
        slideTask = Task { [weak self] in
            while let self, self.slide != nil, !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                self.draw()
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

    // MARK: - Clicks

    @objc private func clicked() {
        // Without a mouse event (the item was pressed through the accessibility API) there is no workspace to tell
        guard let state, let layout, let button = statusItem?.button,
              let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .rightMouseUp else { return openMenu() }
        let isRightButton = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        let point = Self.layoutPoint(of: event, in: button, layoutSize: layout.size)
        switch layout.clickAction(at: point, isRightButton: isRightButton, snapshot: state.snapshot) {
            case .openMenu: openMenu()
            case .focusWorkspace(let workspace): runMenuBarCommand("workspace \(workspace)")
        }
    }

    /// The point of the click in the coordinates of the layout: the image is centered in the button
    private static func layoutPoint(of event: NSEvent, in button: NSStatusBarButton, layoutSize: CGSize) -> CGPoint {
        let location = button.convert(event.locationInWindow, from: nil)
        var imageRect = (button.cell as? NSButtonCell)?.imageRect(forBounds: button.bounds) ?? .zero
        if imageRect.isEmpty {
            imageRect = CGRect(
                x: (button.bounds.width - layoutSize.width) / 2,
                y: (button.bounds.height - layoutSize.height) / 2,
                width: layoutSize.width,
                height: layoutSize.height,
            )
        }
        return CGPoint(
            x: location.x - imageRect.minX,
            y: button.isFlipped ? location.y - imageRect.minY : imageRect.maxY - location.y,
        )
    }

    private func openMenu() {
        guard let statusItem else { return }
        // The menu is attached only while it is open. See: start
        statusItem.menu = menu.menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
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

/// The icons of the apps, by bundle id
@MainActor
final class AppIconCache {
    private var icons: [String: NSImage] = [:]

    func icon(_ app: MenuBarSnapshot.App) -> NSImage? {
        guard let bundleId = app.bundleId else { return nil }
        if let cached = icons[bundleId] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleId] = icon
        return icon
    }
}

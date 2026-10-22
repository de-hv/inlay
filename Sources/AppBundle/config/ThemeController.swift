import AppKit
import Common
import UniformTypeIdentifiers

/// The theme as a whole: when the palette changes, its wallpaper is put on every screen; when the colors change
/// (another palette, the other variant, another seed), the hooks of [theme] on-change run with the new colors.
/// See: 'inlay theme set', ThemeConfig
@MainActor
final class ThemeController {
    static let shared = ThemeController()

    /// The palette whose wallpaper was applied last. nil until the config of the user is loaded at startup
    private var appliedPalette: ThemePalette? = nil
    /// The colors that the hooks were last told about. See: themeEnvironment
    private var appliedEnvironment: [String: String]? = nil
    /// 'theme set': the wallpaper and the hooks are applied again, even if the palette is the one in use
    var forcesNextApply = false
    private var appearanceObserver: (any NSObjectProtocol)? = nil

    private init() {}

    /// After the config of the user is loaded. The first load (startup) is where the theme is taken as it is:
    /// nothing is applied until something changes
    func configDidLoad() {
        observeAppearance()
        let palette = config.theme.palette
        let environment = themeEnvironment()
        guard let previous = appliedPalette else {
            appliedPalette = palette
            appliedEnvironment = environment
            forcesNextApply = false
            return
        }
        let forces = forcesNextApply
        forcesNextApply = false
        appliedPalette = palette
        if palette != previous || forces { applyWallpaper(of: palette) }
        if environment != appliedEnvironment || forces { runHooks(environment) }
    }

    /// The appearance of the system or the seed of the wallpaper changed: the hooks run if the colors did
    func colorsMayHaveChanged() {
        guard appliedPalette != nil else { return }
        let environment = themeEnvironment()
        if environment != appliedEnvironment { runHooks(environment) }
    }

    private func observeAppearance() {
        if appearanceObserver != nil || isUnitTest { return }
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main,
        ) { _ in
            // The appearance of the app follows a moment later
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                ThemeController.shared.colorsMayHaveChanged()
            }
        }
    }

    // MARK: - The colors, for the hooks

    /// The colors in effect, as the hooks get them: INLAY_THEME_FOCUSED='#61AFEF'...
    func themeEnvironment() -> [String: String] {
        let theme = config.theme
        let isDark = isSystemAppearanceDark
        let seed = theme.seedColor(systemAccent: .systemAccent, wallpaper: WallpaperSeed.shared.color)
        let bar = config.menuBar.colors.applying(theme.palette, seed: seed, isDark: isDark)
        let borders = config.borders.applying(theme.palette, seed: seed, isDark: isDark)
        // 'auto' is the color of the text of the menu bar
        let text: Rgba = isDark ? .white : .black
        func hex(_ color: ConfigColor) -> String { color.resolve(auto: text, systemAccent: .systemAccent).hex }
        var result = [
            "INLAY_THEME": theme.palette.rawValue,
            "INLAY_THEME_VARIANT": isDark ? "dark" : "light",
            "INLAY_THEME_FOCUSED": hex(bar.focused),
            "INLAY_THEME_OCCUPIED": hex(bar.occupied),
            "INLAY_THEME_EMPTY": hex(bar.empty),
            "INLAY_THEME_ACCENT": hex(bar.accent),
            "INLAY_THEME_ACTIVE_BORDER": hex(borders.activeColor),
            "INLAY_THEME_INACTIVE_BORDER": hex(borders.inactiveColor),
            "INLAY_THEME_FLOATING_BORDER": hex(borders.floatingColor),
        ]
        if theme.palette == .material { result["INLAY_THEME_SEED"] = seed.hex }
        if let wallpaper = theme.wallpaper(of: theme.palette) { result["INLAY_THEME_WALLPAPER"] = expandedPath(wallpaper) }
        return result
    }

    private func runHooks(_ environment: [String: String]) {
        appliedEnvironment = environment
        if config.theme.onChange.isEmpty || isUnitTest { return }
        for script in config.theme.onChange {
            DebugStats.count("theme.hook")
            let process = Process()
            process.environment = config.execConfig.envVariables.merging(environment) { _, new in new }
            process.executableURL = URL(filePath: "/bin/bash")
            process.arguments = ["-c", script]
            _ = try? process.run()
        }
    }

    // MARK: - The wallpaper

    private func applyWallpaper(of palette: ThemePalette) {
        guard let raw = config.theme.wallpaper(of: palette), !isUnitTest else { return }
        let url = URL(filePath: expandedPath(raw))
        if FileManager.default.fileExists(atPath: url.path) {
            setWallpaper(url)
        } else {
            // Not in the middle of the load of the config: the question waits for the user
            let isOwn = config.theme.wallpapers[palette.rawValue] != nil
            Task { @MainActor in askForMissingWallpaper(palette: palette, path: raw, isOwn: isOwn) }
        }
    }

    func setWallpaper(_ url: URL) {
        DebugStats.count("theme.wallpaper")
        for screen in NSScreen.screens {
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    /// The wallpaper of the palette doesn't exist anymore: the user picks another one, which is written in the config,
    /// or keeps the wallpaper that is on the screen
    private func askForMissingWallpaper(palette: ThemePalette, path: String, isOwn: Bool) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = Strings.Theme.missingWallpaper(palette.title)
        alert.informativeText = Strings.Theme.missingWallpaperDetail(path)
        alert.addButton(withTitle: Strings.Theme.chooseWallpaper)
        alert.addButton(withTitle: Strings.Theme.keepWallpaper)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = Strings.Theme.chooseWallpaperMessage(palette.title)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let value = TomlValue.string((url.path as NSString).abbreviatingWithTildeInPath)
        let path = isOwn ? TomlKeyPath(["theme", "wallpapers"], palette.rawValue) : TomlKeyPath(["theme"], "wallpaper")
        setWallpaper(url)
        if case .success(let target) = ConfigEditor.target(), case .success = ConfigEditor.apply([ConfigEdit(path: path, value: value)], to: target) {
            Task.startUnstructured { @MainActor in
                try await runLightSession(.menuBarButton, .forceRun) {
                    _ = await reloadConfig_nonCancellable(notice: .always)
                }
            }
        }
    }

    private func expandedPath(_ path: String) -> String { (path as NSString).expandingTildeInPath }
}

/// The colors that the user wrote in the config, which win over the ones of the palette. See: ThemeColorSource
enum ManualColors {
    /// The keys of the colors that a palette gives, in the order of the settings window
    static let keys: [SettingsKey] = [
        .menuBarFocused, .menuBarOccupied, .menuBarEmpty, .menuBarAccent,
        .bordersActiveColor, .bordersInactiveColor, .bordersFloatingColor,
    ]

    /// The keys of the config whose color isn't the one of the palette
    static func keys(in config: Config) -> [SettingsKey] {
        let bar = config.menuBar.colors
        let borders = config.borders
        let defaults = BordersConfig()
        var result: [SettingsKey] = []
        if bar.focused != .auto { result.append(.menuBarFocused) }
        if bar.occupied != .auto { result.append(.menuBarOccupied) }
        if bar.empty != .auto { result.append(.menuBarEmpty) }
        if bar.accent != .auto { result.append(.menuBarAccent) }
        if borders.activeColor != defaults.activeColor { result.append(.bordersActiveColor) }
        if borders.inactiveColor != defaults.inactiveColor { result.append(.bordersInactiveColor) }
        if borders.floatingColor != defaults.floatingColor { result.append(.bordersFloatingColor) }
        return result
    }
}

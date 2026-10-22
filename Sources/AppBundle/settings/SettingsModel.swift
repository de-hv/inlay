import AppKit
import Common
import Observation

/// The state of the settings window: the config file as it is on disk, plus the changes that aren't written yet.
///
/// The window keeps nothing on its own. Every control reads its key from the text of the config file and writes it back
/// with `ConfigEditor`, and then the config is reloaded.
///
/// It's an observable object rather than @State in the views: @State is a macro whose plugin only ships with Xcode,
/// and Inlay must build with the Command Line Tools alone
@MainActor
@Observable
final class SettingsModel {
    /// The file to edit. nil if it can't be told or read
    private(set) var target: ConfigEditor.Target? = nil
    /// Why nothing can be changed right now. nil if the settings can be changed
    private(set) var unavailableReason: String? = nil
    private(set) var lastLoad: ConfigLoadStatus? = nil
    private(set) var isAccessibilityGranted: Bool = false
    private(set) var isPaused: Bool = false
    /// The last change that couldn't be written
    var errorMessage: String? = nil
    /// The binding modes of the config file that can have a color of their own in [borders.mode-colors], sorted.
    ///
    /// Not 'main'. It is the mode that is active all the time: its color would take the place of the active and
    /// the floating colors for good, which is what those two keys are for. (It can still be written by hand)
    private(set) var colorableModes: [String] = []

    /// The part of the Themes tab on the screen. Only the window remembers it, not the config
    var themesSection: ThemesSection = .palette

    // MARK: The window. None of it is kept in the config

    /// The page in the sidebar
    var page: SettingsPageID = .general
    /// The text of the search field of the sidebar
    var searchText: String = ""
    /// The row that a search result leads to: it is highlighted for a moment
    var highlightedTitle: String? = nil
    /// The row under the mouse: it shows its key. See: showsKey
    var hoveredKey: SettingsKey? = nil
    /// ⌥ is held down: every row shows its key
    var isOptionHeld: Bool = false
    /// The binding mode that the Shortcuts page shows, and the text that filters its bindings
    var shortcutsMode: String = mainModeId
    var shortcutsFilter: String = ""
    /// The variant of the palette that the previews of Themes show. nil: the one of the appearance of the system
    var previewVariantIsDark: Bool? = nil
    /// The palette under the mouse in Themes › Palette: the preview shows it, without writing it
    var hoveredPalette: ThemePalette? = nil
    /// The changes written by the window that can be undone, the last one at the end
    private(set) var undoStack: [SettingsChange] = []
    private(set) var redoStack: [SettingsChange] = []
    /// The config of the file, parsed. Its workspaces, rules and key bindings, for the pages that show them
    private(set) var config: Config = defaultConfig

    /// The values chosen in the window that aren't in the file yet: a slider being dragged, a color being picked
    private var pending: [SettingsKey: TomlValue] = [:]
    @ObservationIgnored private var root: [String: Any] = [:]
    @ObservationIgnored private var document = TomlPatcher.Document("")
    @ObservationIgnored private var commitTasks: [SettingsKey: Task<Void, Never>] = [:]

    @ObservationIgnored private let loadTarget: @MainActor () -> Result<ConfigEditor.Target, ConfigEditor.EditError>
    @ObservationIgnored private let reloadsConfig: Bool

    private static let commitDelay: Duration = .milliseconds(400)

    /// - Parameter loadTarget: finds and reads the config file. The tests point it to a file of their own
    /// - Parameter reloadsConfig: false if there is no window manager to tell about the changes. See: runSettingsDebug
    init(
        loadTarget: @escaping @MainActor () -> Result<ConfigEditor.Target, ConfigEditor.EditError> = ConfigEditor.target,
        reloadsConfig: Bool = !isUnitTest,
    ) {
        self.loadTarget = loadTarget
        self.reloadsConfig = reloadsConfig
    }

    /// Reads the config file and the state of the server again
    func refresh() {
        let state = ServerState.shared
        lastLoad = state.lastConfigLoad
        isAccessibilityGranted = state.axPermissionStatus == .granted
        isPaused = !state.isEnabled
        switch loadTarget() {
            case .success(let target):
                self.target = target
                root = (try? TomlPatcher.decode(target.text)) ?? [:]
                document = TomlPatcher.Document(target.text)
                let parsed = parseConfig(target.text)
                config = parsed.config
                colorableModes = parsed.config.modes.keys.filter { $0 != mainModeId }.sorted()
                unavailableReason = switch true {
                    // The config is loaded once the permission is granted. Until then there is nothing to reload
                    case !isAccessibilityGranted: Strings.Settings.needsAccessibility
                    case !parsed.errors.isEmpty: Strings.Settings.configHasErrors(target.url.lastPathComponent)
                    default: nil
                }
            case .failure(let error):
                target = nil
                root = [:]
                document = TomlPatcher.Document("")
                config = defaultConfig
                colorableModes = []
                unavailableReason = error.message
        }
    }

    // MARK: - Reading

    /// The value in effect: the one being edited, else the one of the file, else the default
    func value(_ key: SettingsKey) -> TomlValue {
        pending[key] ?? fileValue(key) ?? key.defaultValue
    }

    private func fileValue(_ key: SettingsKey) -> TomlValue? {
        _ = target // The file is what the views depend on
        return TomlValue(TomlPatcher.value(in: root, key.path), like: key.defaultValue)
    }

    func bool(_ key: SettingsKey) -> Bool { if case .bool(let value) = value(key) { value } else { false } }
    func string(_ key: SettingsKey) -> String { if case .string(let value) = value(key) { value } else { "" } }
    func int(_ key: SettingsKey) -> Int { if case .int(let value) = value(key) { value } else { 0 } }
    func float(_ key: SettingsKey) -> Double { if case .float(let value) = value(key) { value } else { 0 } }
    func strings(_ key: SettingsKey) -> [String] { if case .strings(let value) = value(key) { value } else { [] } }

    /// The text of the file, line by line, for the pages that show what it says: the key bindings and their comments
    var fileDocument: TomlPatcher.Document {
        _ = target
        return document
    }

    /// The file as TOMLDecoder gives it, for the pages that show more than single keys
    var rawRoot: [String: Any] {
        _ = target
        return root
    }

    /// The mouse entered or left the row of the key
    func hover(_ key: SettingsKey, _ isInside: Bool) {
        if isInside {
            hoveredKey = key
        } else if hoveredKey == key {
            hoveredKey = nil
        }
    }

    /// The row shows the name of its key: always with [settings] show-keys, otherwise while the mouse is over it or ⌥ is held
    func showsKey(_ key: SettingsKey) -> Bool {
        isOptionHeld || hoveredKey == key || bool(.settingsShowKeys)
    }
    func color(_ key: SettingsKey) -> ConfigColor { (try? ConfigColor.parse(string(key), allowAuto: true).get()) ?? .auto }

    /// The key is written in the file, so it can be reset to its default
    func isSet(_ key: SettingsKey) -> Bool {
        _ = target
        return pending[key] != nil || TomlPatcher.value(in: root, key.path) != nil
    }

    /// Why the control of the key is disabled. nil if it isn't
    func disabledReason(_ key: SettingsKey) -> String? {
        if let unavailableReason { return unavailableReason }
        _ = target
        if case .unsupported = document.locate(key.path) { return Strings.Settings.definedByHand }
        // A value that the control can't show: a gap per monitor, `[{ monitor.main = 16 }, 8]`
        if TomlPatcher.value(in: root, key.path) != nil && fileValue(key) == nil { return Strings.Settings.definedByHand }
        return nil
    }

    /// The [menu-bar] table as the window has it, for the preview
    var menuBarConfig: MenuBarConfig {
        MenuBarConfig(
            enabled: bool(.menuBarEnabled),
            theme: menuBarTheme,
            dimEmptyWorkspaces: bool(.menuBarDimEmpty),
            showMode: bool(.menuBarShowMode),
            colors: MenuBarColors(
                accent: color(.menuBarAccent),
                focused: color(.menuBarFocused),
                occupied: color(.menuBarOccupied),
                empty: color(.menuBarEmpty),
            ),
            perMonitor: bool(.menuBarPerMonitor),
            labels: config.menuBar.labels.merging(pendingStrings(SettingsKey.menuBarLabel)) { $1 }.filter { !$0.value.isEmpty },
            symbols: config.menuBar.symbols.merging(pendingStrings(SettingsKey.menuBarSymbol)) { $1 }.filter { !$0.value.isEmpty },
            palette: palette,
            paletteSeed: paletteSeed,
        )
    }

    /// The labels or the symbols being typed, not written yet
    private func pendingStrings(_ key: (String) -> SettingsKey) -> [String: String] {
        let table = key("").path.table
        return Dictionary(uniqueKeysWithValues: pending.compactMap { entry -> (String, String)? in
            guard entry.key.path.table == table, case .string(let value) = entry.value else { return nil }
            return (entry.key.path.key, value)
        })
    }

    /// The workspaces that the 'labels' theme can name: the persistent ones, and the ones that already have a label or
    /// a symbol, in the order of the config
    var labelWorkspaces: [String] {
        (config.persistentWorkspaces.elements + config.menuBar.labels.keys.sorted() + config.menuBar.symbols.keys.sorted())
            .toOrderedSet()
            .elements
    }

    /// The variant of the palettes in the previews of Themes
    var previewIsDark: Bool { previewVariantIsDark ?? isSystemAppearanceDark }

    var palette: ThemePalette { ThemePalette(rawValue: string(.themePalette)) ?? ThemeConfig().palette }

    /// [theme] seed, the color that 'material' is made from
    var paletteSeed: Rgba {
        let seed: ThemeSeed = string(.themeSeed) == ThemeSeed.wallpaperLiteral ? .wallpaper : .color(color(.themeSeed))
        return ThemeConfig(seed: seed).seedColor(systemAccent: .systemAccent, wallpaper: WallpaperSeed.shared.color)
    }

    /// The colors that the config sets by hand: the palette doesn't give them. See: ManualColors
    var manualColorKeys: [SettingsKey] {
        ManualColors.keys.filter { isSet($0) && value($0) != $0.defaultValue }
    }

    /// A palette is in use, and some colors are the user's own instead of its ones: no theme applies to them
    var hasCustomColors: Bool { palette != .system && !manualColorKeys.isEmpty }

    /// The color that the palette gives to the key, in the appearance of the system. nil for 'system', and for a key
    /// that a palette doesn't color
    func paletteColor(_ key: SettingsKey) -> Rgba? {
        guard let colors = palette.colors(isDark: isSystemAppearanceDark, seed: paletteSeed) else { return nil }
        return switch key {
            case .menuBarFocused: colors.focused
            case .menuBarOccupied: colors.occupied
            case .menuBarEmpty: colors.empty
            case .menuBarAccent: colors.accent
            case .bordersActiveColor: colors.activeBorder
            case .bordersInactiveColor: colors.inactiveBorder
            case .bordersFloatingColor: colors.floatingBorder
            default: nil
        }
    }

    /// Picks a palette in one write. With `resettingColors`, the colors set by hand are removed: the palette gives every color.
    /// - Parameter seed: the [theme] seed to write with it (Material You). nil: the seed stays as it is
    func setPalette(_ palette: ThemePalette, seed: String? = nil, resettingColors: Bool) {
        let manual = resettingColors ? manualColorKeys : []
        var edits = [ConfigEdit(path: SettingsKey.themePalette.path, value: .string(palette.rawValue))]
        var keys: [SettingsKey] = [.themePalette]
        if let seed {
            edits.append(ConfigEdit(path: SettingsKey.themeSeed.path, value: .string(seed)))
            keys.append(.themeSeed)
        }
        write(edits + manual.map { ConfigEdit(path: $0.path, value: nil) }, keys: keys + manual)
    }

    /// Removes every color set by hand, in one write: the palette gives them all again
    func resetManualColors() {
        let manual = manualColorKeys
        write(manual.map { ConfigEdit(path: $0.path, value: nil) }, keys: manual)
    }

    /// 'chips-icons', the theme of a previous version, is 'chips', like for the parser
    var menuBarTheme: MenuBarTheme {
        let raw = string(.menuBarTheme)
        return raw == "chips-icons" ? .chips : MenuBarTheme(rawValue: raw) ?? MenuBarConfig().theme
    }

    // MARK: - Writing

    /// Writes the value to the config file right away
    func set(_ key: SettingsKey, _ value: TomlValue) {
        write([ConfigEdit(path: key.path, value: value)], keys: [key])
    }

    /// Removes the key from the config file: its default value applies again
    func reset(_ key: SettingsKey) {
        write([ConfigEdit(path: key.path, value: nil)], keys: [key])
    }

    /// Picking a theme also drops 'show-app-icons' from the file: the window of a previous version of Inlay wrote
    /// that key, which is ignored with a warning now. See: parseMenuBar
    func setTheme(_ theme: MenuBarTheme) {
        write(
            [
                ConfigEdit(path: SettingsKey.menuBarTheme.path, value: .string(theme.rawValue)),
                ConfigEdit(path: TomlKeyPath(["menu-bar"], "show-app-icons"), value: nil),
            ],
            keys: [.menuBarTheme],
        )
    }

    /// Shows the value in the window without writing it. See: commit
    func preview(_ key: SettingsKey, _ value: TomlValue) {
        if self.value(key) != value { pending[key] = value }
    }

    /// Writes the previewed value of the key, if there is one. An empty text removes a key that has no default
    func commit(_ key: SettingsKey) {
        commitTasks.removeValue(forKey: key)?.cancel()
        guard let value = pending[key] else { return }
        if value == .string(""), key.defaultValue == .string("") {
            reset(key)
        } else {
            set(key, value)
        }
    }

    /// For the controls that change their value many times in a row and can't tell when they are done (the color picker):
    /// the value is shown right away, and written once it stops changing
    func setDebounced(_ key: SettingsKey, _ value: TomlValue) {
        guard self.value(key) != value else { return }
        pending[key] = value
        commitTasks[key]?.cancel()
        commitTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: Self.commitDelay)
            if !Task.isCancelled { self?.commit(key) }
        }
    }

    private func write(_ edits: [ConfigEdit], keys: [SettingsKey]) {
        for key in keys {
            commitTasks.removeValue(forKey: key)?.cancel()
            pending[key] = nil
        }
        guard unavailableReason == nil, target != nil else { return }
        // The file is read again right before it is patched. The text that the window holds may be old: the user
        // edits the file in an editor while the window is open, and without 'auto-reload-config' nothing tells
        // the window about it. Patching the old text would write the changes of the user away
        let current: ConfigEditor.Target
        switch loadTarget() {
            case .success(let fresh): current = fresh
            case .failure(let error):
                errorMessage = error.message
                refresh()
                return
        }
        let patched: String
        switch ConfigEditor.patch(current.text, edits) {
            case .success(let text): patched = text
            case .failure(let error):
                errorMessage = error.message
                refresh()
                return
        }
        switch ConfigEditor.write(patched, to: current) {
            case .success:
                errorMessage = nil
                if patched != current.text {
                    undoStack.append(SettingsChange(edits: edits, before: current.text, after: patched))
                    if undoStack.count > Self.maxUndo { undoStack.removeFirst() }
                    redoStack = []
                }
                refresh()
                reloadConfigAfterEdit()
            case .failure(let error):
                errorMessage = error.message
                refresh()
        }
    }

    private static let maxUndo = 50

    // MARK: - Undo

    /// Puts the file back as it was before the last change of the window. Nothing happens if the file was changed
    /// since, by hand or by another program: undoing would write those changes away
    func undo() { step(from: \.undoStack, to: \.redoStack, undoing: true) }

    func redo() { step(from: \.redoStack, to: \.undoStack, undoing: false) }

    private func step(from: ReferenceWritableKeyPath<SettingsModel, [SettingsChange]>, to: ReferenceWritableKeyPath<SettingsModel, [SettingsChange]>, undoing: Bool) {
        guard let change = self[keyPath: from].last, unavailableReason == nil else { return }
        let current: ConfigEditor.Target
        switch loadTarget() {
            case .success(let fresh): current = fresh
            case .failure(let error):
                errorMessage = error.message
                return
        }
        let (expected, text) = undoing ? (change.after, change.before) : (change.before, change.after)
        guard current.text == expected else {
            errorMessage = Strings.Settings.cantUndoChangedFile
            undoStack = []
            redoStack = []
            return
        }
        switch ConfigEditor.write(text, to: current) {
            case .success:
                errorMessage = nil
                self[keyPath: from].removeLast()
                self[keyPath: to].append(change)
                refresh()
                reloadConfigAfterEdit()
            case .failure(let error):
                errorMessage = error.message
        }
    }

    // MARK: - Export

    /// The config with every key that applies, and the comments of the user. See: ConfigEditor.exportText
    var exportText: String? {
        guard let target else { return nil }
        return ConfigEditor.exportText(target)
    }

    /// Unlike the "Reload config" of the menu, it also runs while Inlay is paused: the file has just been written by Inlay itself
    private func reloadConfigAfterEdit() {
        if !reloadsConfig { return }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, .forceRun) {
                _ = await reloadConfig_nonCancellable(notice: .never)
            }
        }
    }
}

/// The parts of the Themes tab of the settings window, one at a time
enum ThemesSection: Hashable, Sendable {
    /// The palettes: where the colors come from
    case palette
    /// The shape of the workspace indicator, and its options
    case indicator
    /// Every color that a palette gives: the indicator and the borders, theme or the user's own
    case colors
}

/// The pages of the settings window, in the order of the sidebar
enum SettingsPageID: String, CaseIterable, Hashable, Sendable {
    case general, themes, tiling, gaps, borders, animations, workspaces, shortcuts

    var title: String {
        switch self {
            case .general: Strings.Settings.general
            case .themes: Strings.Settings.themes
            case .tiling: Strings.Settings.tiling
            case .gaps: Strings.Settings.gaps
            case .borders: Strings.Settings.borders
            case .animations: Strings.Settings.animations
            case .workspaces: Strings.Settings.workspacesPage
            case .shortcuts: Strings.Settings.shortcuts
        }
    }

    var symbol: String {
        switch self {
            case .general: "gearshape"
            case .themes: "paintpalette"
            case .tiling: "rectangle.split.2x1"
            case .gaps: "rectangle.split.3x1"
            case .borders: "rectangle.dashed"
            case .animations: "wand.and.stars"
            case .workspaces: "square.grid.2x2"
            case .shortcuts: "keyboard"
        }
    }

    /// The color of the square behind the symbol, like in System Settings
    var tint: Rgba {
        switch self {
            case .general: Rgba(hex: "#8E8E93").orDie()
            case .themes: Rgba(hex: "#BF5AF2").orDie()
            case .tiling: Rgba(hex: "#0A84FF").orDie()
            case .gaps: Rgba(hex: "#30B0C7").orDie()
            case .borders: Rgba(hex: "#5E5CE6").orDie()
            case .animations: Rgba(hex: "#FF9F0A").orDie()
            case .workspaces: Rgba(hex: "#30D158").orDie()
            case .shortcuts: Rgba(hex: "#636366").orDie()
        }
    }

    /// The group of the sidebar the page is in. nil: the top one, without a title
    var group: String? {
        switch self {
            case .general, .themes: nil
            case .tiling, .gaps, .borders, .animations: Strings.Settings.windowsGroup
            case .workspaces, .shortcuts: Strings.Settings.workflowGroup
        }
    }
}

/// A change that the window wrote to the config file: the whole text before and after it, so that it can be undone
struct SettingsChange: Equatable, Sendable {
    var edits: [ConfigEdit]
    var before: String
    var after: String

    /// "[borders] width: 4 → 6"
    var summary: String {
        guard let first = edits.first else { return "" }
        let key = SettingsKey(first.path.table, first.path.key, default: .bool(false)).label
        func literal(_ text: String) -> String {
            TomlPatcher.Document(text).valueText(of: first.path) ?? Strings.Settings.defaultValueShort
        }
        let more = edits.count > 1 ? " +\(edits.count - 1)" : ""
        return "\(key): \(literal(before)) → \(literal(after))\(more)"
    }
}

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
            palette: palette,
        )
    }

    var palette: ThemePalette { ThemePalette(rawValue: string(.themePalette)) ?? ThemeConfig().palette }

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

    /// Writes the previewed value of the key, if there is one
    func commit(_ key: SettingsKey) {
        commitTasks.removeValue(forKey: key)?.cancel()
        if let value = pending[key] { set(key, value) }
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
        switch ConfigEditor.apply(edits, to: current) {
            case .success:
                errorMessage = nil
                refresh()
                reloadConfigAfterEdit()
            case .failure(let error):
                errorMessage = error.message
                refresh()
        }
    }

    /// Unlike the "Reload config" of the menu, it also runs while Inlay is paused: the file has just been written by Inlay itself
    private func reloadConfigAfterEdit() {
        if !reloadsConfig { return }
        Task.startUnstructured { @MainActor in
            try await runLightSession(.menuBarButton, .forceRun) {
                _ = await reloadConfig_nonCancellable()
            }
        }
    }
}

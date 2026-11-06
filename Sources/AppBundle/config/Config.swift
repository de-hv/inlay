import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: configFileName)
}

/// The config that a new install gets: a short inlay.lua, with what is the user's own. The rest of the config is the
/// built-in one (builtInConfigUrl), under it
var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "inlay", withExtension: "lua")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}

let builtInConfigFileName = "builtin-config.lua"

/// The config of Inlay: the base that the config of the user goes over (see: mergedConfig), and the config in use
/// when the user has none
var builtInConfigUrl: URL {
    // Only when it is needed: getDefaultConfigUrlFromProject() stops the app on a Mac without the sources of Inlay
    func fromProject() -> URL { getDefaultConfigUrlFromProject().deletingLastPathComponent().appending(component: builtInConfigFileName) }
    if isUnitTest { return fromProject() }
    return Bundle.main.url(forResource: "builtin-config", withExtension: "lua") ?? fromProject()
}

/// The table of the built-in config, to put the config of the user over it
@MainActor var builtInConfigTable: OrderedJson.JsonDict { LuaConfigLoader.load(file: builtInConfigUrl).table }

@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(LuaConfigLoader.load(file: builtInConfigUrl))
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = builtInConfigUrl

struct Config: ConvenienceMutable {
    var afterStartupCommand: Shell<any Command> = .empty
    var enableNormalizationFlattenContainers: Bool = true
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = true
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var persistentWorkspaces: OrderedSet<String> = []
    /// 'workspaces' and 'workspace_keys' become the keys that they make before the config is parsed. See: expandWorkspaces
    var _workspaces: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value
    /// The names of 'workspaces': the menu of the menu bar item shows them
    var workspaceNames: [String: String] = [:]
    /// 'built_in_config = false': the config of the user doesn't go over the built-in one. See: mergedConfig
    var _builtInConfig: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()
    var focusFollowsMouse: FocusFollowsMouse = FocusFollowsMouse()
    var tiling: TilingConfig = TilingConfig()
    var menuBar: MenuBarConfig = MenuBarConfig()
    var borders: BordersConfig = BordersConfig()
    var animations: AnimationsConfig = AnimationsConfig()
    /// 'theme' goes into 'borders' and 'menu_bar' before they are parsed. See: ThemeResolver
    var _theme: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value
    /// The colors of the light theme of `theme = { dark = …, light = … }`. nil: the same in both appearances
    var lightAppearance: AppearanceColors? = nil
    /// [notifications] and [settings] are tables of the past: they are accepted and ignored. See: parseObsolete
    var _notifications: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value
    var _settings: Void { get { () } set {} } // swiftlint:disable:this unused_setter_value

    var onFocusChanged: Shell<any Command> = .empty
    // var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: Shell<any Command> = .empty

    var gaps: Gaps = .zero
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var onModeChanged: Shell<any Command> = .empty
}

struct FocusFollowsMouse: ConvenienceMutable {
    var enabled: Bool = false
}

struct TilingConfig: ConvenienceMutable, Equatable {
    var newWindowPlacement: NewWindowPlacement = .dwindle
    /// The fraction of its space that the split window keeps, when newWindowPlacement is dwindle
    var splitRatio: CGFloat = 0.5
    /// How the windows that are already open when Inlay starts are arranged
    var startupLayout: StartupLayout = .grid
    /// Which window a new window splits, when newWindowPlacement is dwindle
    var splitTarget: SplitTarget = .focused
    /// The size, in points, under which the resize command and the mouse don't shrink a tiling window.
    /// See: TilingContainer.minimumResizeWeights
    var minWindowSize: CGFloat = 100

    static let splitRatioRange: ClosedRange<CGFloat> = 0.1 ... 0.9
    static let minWindowSizeRange = 20 ... 500
}

/// The window that a new tiling window splits in two
enum SplitTarget: String, CaseIterable {
    /// The focused window. If it isn't a tiling window of the workspace, the most recent tiling window of the workspace
    case focused
    /// The tiling window under the mouse cursor, like Hyprland does. If there is none, the same as `focused`
    case cursor
}

/// Where a new tiling window is placed
enum NewWindowPlacement: String, CaseIterable {
    /// The new window splits the most recent tiling window of the workspace in two, like the dwindle layout of Hyprland
    case dwindle
    /// AeroSpace behavior. The new window becomes the next sibling of the most recent window,
    /// and all the siblings share the space
    case afterFocused = "after-focused"
}

/// How the tiling windows that already exist when Inlay starts to manage the windows are arranged, in every workspace.
/// See: StartupArrangement
enum StartupLayout: String, CaseIterable {
    /// A balanced grid: ceil(sqrt(n)) columns, and the windows of the last row share its width
    case grid
    /// One row. All the windows get the same width
    case row
    /// No arrangement of their own: the windows are placed one after another, like new windows (newWindowPlacement)
    case dwindle
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}

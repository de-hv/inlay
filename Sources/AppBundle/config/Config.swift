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
    return projectRoot.appending(component: "docs/config-examples/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: ConvenienceMutable {
    var configVersion: ConfigVersion = ._1
    var _afterLoginCommand: [any Command] = []
    var afterStartupCommand: Shell<any Command> = .empty
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var _accordionPadding: Void = ()
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()
    var focusFollowsMouse: FocusFollowsMouse = FocusFollowsMouse()
    var tiling: TilingConfig = TilingConfig()
    var menuBar: MenuBarConfig = MenuBarConfig()
    var borders: BordersConfig = BordersConfig()

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

enum ConfigVersion: Int, Comparable, CaseIterable, Sendable, CustomStringConvertible {
    case _1 = 1
    case _2 = 2

    static let max = allCases.max().orDie()
    static let min = allCases.min().orDie()
    static func < (lhs: ConfigVersion, rhs: ConfigVersion) -> Bool { lhs.rawValue < rhs.rawValue }

    var description: String { rawValue.description }
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}

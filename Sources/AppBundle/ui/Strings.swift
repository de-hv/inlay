import Common

/// The texts of the menu bar item, its menu and the settings window, in one place so they can be localized later.
/// The interface is in English for now, like the CLI
enum Strings {
    enum Menu {
        static let workspaces = "Workspaces"
        static let empty = "Empty"
        static let focusedWindow = "Focused Window"
        static let moveTo = "Move to"
        static let floating = "Floating"
        static let fullscreen = "Fullscreen"
        static let layout = "Layout"
        static let horizontal = "Horizontal"
        static let vertical = "Vertical"
        static let balanceSizes = "Balance Sizes"
        static let resetLayout = "Reset Layout"
        static let bindingMode = "Binding Mode"
        static let reloadConfig = "Reload Config"
        static let openConfig = "Open \(configFileName)…"
        static let pause = "Pause \(inlayAppName)"
        static let resume = "Resume \(inlayAppName)"
        static let settings = "Settings…"
        static let quit = "Quit \(inlayAppName)"
        static let configWarnings = "Config contains warnings…"
        static let needsAccessibility = "\(inlayAppName) requires accessibility permission to move windows"
        static let paused = "\(inlayAppName) is paused"
        static let copyVersionToolTip = "Click to copy the version"
        static func apps(_ count: Int) -> String { "\(count) apps" }
        static var version: String { "\(inlayAppName) \(inlayAppVersion) (\(gitShortHash)) · based on AeroSpace" }
        static var versionToCopy: String { "\(inlayAppName) v\(inlayAppVersion) \(gitHash)" }
    }

    enum Item {
        static func accessibilityDescription(_ snapshot: MenuBarSnapshot) -> String {
            switch snapshot.status {
                case .running: "\(inlayAppName): workspace \(snapshot.focusedWorkspace)"
                case .paused: Menu.paused
                case .needsAccessibility: Menu.needsAccessibility
            }
        }
    }

    enum Settings {
        static let windowTitle = "\(inlayAppName) Settings"
        static let general = "General"
        static let menuBar = "Menu Bar"
        static let borders = "Borders"
        static let reset = "Reset"

        // General
        static let startup = "Startup"
        static let startAtLogin = "Open at login"
        static let startAtLoginDetail = "\(inlayAppName) starts with your session and arranges the open windows."
        static let tiling = "Tiling"
        static let placement = "New windows"
        static let placementDwindleDetail = "Dwindle: the new window splits the focused one along its longer side."
        static let placementAfterFocusedDetail = "After focused: the new window is added next to the focused one, and the windows of the container share the space."
        static let dwindle = "Dwindle"
        static let afterFocused = "After Focused"
        static let startupLayout = "Windows already open"
        static let startupGridDetail = "Grid: when \(inlayAppName) starts, the windows of every workspace are arranged in a balanced grid."
        static let startupRowDetail = "Row: when \(inlayAppName) starts, the windows of every workspace are arranged side by side."
        static let startupDwindleDetail = "Dwindle: when \(inlayAppName) starts, the windows are placed one after another, like new windows."
        static let grid = "Grid"
        static let row = "Row"
        static let configuration = "Configuration"
        static let file = "File"
        static let showInFinder = "Show in Finder"
        static let open = "Open"
        static let autoReload = "Reload on save"
        static let autoReloadDetail = "Apply the changes as soon as the file changes on disk."
        static let status = "Status"
        static let reloadNow = "Reload Now"
        static let notLoadedYet = "Not loaded yet"
        static let builtInConfig = "Built-in config. The first change creates"
        static let permissions = "Permissions"
        static let accessibilityGranted = "Accessibility: granted"
        static let accessibilityMissing = "Accessibility: not granted"
        static let accessibilityDetail = "Needed to read, move and resize windows. It's the only permission \(inlayAppName) asks for."
        static let openSystemSettings = "Open System Settings"
        static let footer = "Every control writes its key to the config file, and the config is reloaded."
        static func loaded(_ ago: String, _ errors: Int, _ warnings: Int) -> String {
            let problems = switch (errors, warnings) {
                case (0, 0): "no errors or warnings"
                default: "\(errors) error(s), \(warnings) warning(s)"
            }
            return "Loaded \(ago) · \(problems)"
        }
        static func notApplied(_ ago: String, _ errors: Int) -> String {
            "Failed to load \(ago) · \(errors) error(s). The previous config stays in effect"
        }

        // Menu Bar
        static let livePreview = "Live preview"
        static let theme = "Theme"
        static let options = "Options"
        static let showItem = "Show the menu bar item"
        static let showItemDetail = "Without it, use the key bindings and the CLI. Open \(inlayAppName) again from Applications to get back here."
        static let showAppIcons = "Show app icons"
        static let showAppIconsDetail = "The icons of the apps of every workspace, next to its name."
        static let dimEmpty = "Dim empty workspaces"
        static let dimEmptyDetail = "Workspaces without windows are drawn fainter."
        static let showMode = "Show the binding mode"
        static let showModeDetail = "A badge with its initial when the mode isn't main."
        static let colors = "Colors"
        static let accent = "Accent"
        static let accentDetail = "The mode badge."
        static let focused = "Focused"
        static let occupied = "With windows"
        static let emptyColor = "Empty"
        static let colorsFooter = "“auto” follows the menu bar: white on a dark one, black on a light one. “Reset” removes the key from the config file."

        // Borders
        static let windowBorders = "Window Borders"
        static let showBorders = "Show borders"
        static let width = "Width"
        static let cornerRadius = "Corner radius"
        static let cornerRadiusDetail = "It should be close to the radius of the macOS windows."
        static let glow = "Glow"
        static let glowDetail = "A halo of the color of the border around the focused window."
        static let glowRadius = "Glow radius"
        static let activeWindow = "Active window"
        static let inactiveWindows = "Inactive windows"
        static let floatingWindow = "Focused floating window"
        static let active = "Active"
        static let inactive = "Inactive"
        static let floatingPreview = "Floating"
        static func points(_ value: Int) -> String { "\(value) pt" }

        // Why a control is disabled
        static let definedByHand = "Defined by hand in the config file"
        static let needsAccessibility = "Grant the accessibility permission to change the settings."
        static let ambiguousConfig = "Several config files found. Keep only one of them."
        static func configHasErrors(_ file: String) -> String { "\(file) has errors. Fix them to change the settings from here." }
        static func writeFailed(_ reason: String) -> String { "Can't change the config file: \(reason)" }
    }
}

let configFileName = "inlay.toml"

import Common

/// The texts of the menu bar item, its menu and the settings window, in one place so they can be localized later.
/// The interface is in English for now, like the CLI
enum Strings {
    enum Menu {
        static let workspaces = "Workspaces"
        static let empty = "Empty"
        static let floating = "Float Focused Window"
        static let reloadConfig = "Reload Config"
        static let openConfig = "Open \(configFileName)…"
        static let pause = "Pause \(inlayAppName)"
        static let resume = "Resume \(inlayAppName)"
        static let settings = "Settings…"
        static let quit = "Quit \(inlayAppName)"
        /// The item that shows the errors and the warnings of the config, and the key bindings that macOS refused.
        /// nil if the last load had none
        static func configProblems(_ load: ConfigLoadStatus?) -> String? {
            switch (load?.errorCount ?? 0, load?.warningCount ?? 0) {
                case (0, 0): nil
                case (0, _): "Config contains warnings…"
                default: "Config contains errors…"
            }
        }
        static let needsAccessibility = "\(inlayAppName) requires accessibility permission to move windows"
        static let paused = "\(inlayAppName) is paused"
        static let copyVersionToolTip = "Click to copy the version"
        static var version: String { "\(inlayAppName) \(inlayAppVersion)" }
        static var versionToCopy: String { "\(inlayAppName) v\(inlayAppVersion) \(gitHash)" }
    }

    enum Item {
        static let toolTip = "Right-click to open the \(inlayAppName) menu"
        static let accessibilityHelp = "Opens the \(inlayAppName) menu"
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
        static let gaps = "Gaps"
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
        static let splitTarget = "Window to split"
        static let splitTargetFocusedDetail = "Focused: a new window splits the focused window."
        static let splitTargetCursorDetail = "Cursor: a new window splits the window under the mouse cursor. Without one there, the focused window."
        static let splitTargetNotDwindleDetail = "Only for Dwindle."
        static let focusedWindow = "Focused"
        static let cursor = "Cursor"
        static let minWindowSize = "Minimum window size"
        static let minWindowSizeDetail = "Resizing with the keyboard or the mouse doesn't make a window smaller than this."
        static let grid = "Grid"
        static let animations = "Animations"
        static let animate = "Animate the windows"
        static let animateDetail = "The windows slide to their place when a window opens or closes, and when you move one with swap or move."
        static let duration = "Duration"
        static let durationDetail = "Shorter is snappier. 0 turns the animations off. With Reduce Motion on, nothing is animated."
        static func milliseconds(_ value: Int) -> String { "\(value) ms" }
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
        static let dimEmpty = "Dim empty workspaces"
        static let dimEmptyDetail = "Workspaces without windows are drawn fainter."
        static let showMode = "Show the binding mode"
        static let showModeDetail = "Its initial in the marker of the focused workspace, when the mode isn't main."
        static let colors = "Colors"
        static let accent = "Accent"
        static let accentDetail = "The marker of a binding mode. “auto”: the same as Focused."
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
        static let squareCorners = "Square corners"
        static let squareCornersDetail = "The border fills the rounded corners of the windows, so they look square. Off: the border follows the corners."
        static let squareCornersRadiusDetail = "The radius of the macOS windows, or a bit more: with less, what is behind a window shows in its corners."
        static let glow = "Glow"
        static let glowDetail = "A halo of the color of the border around the focused window."
        static let glowRadius = "Glow radius"
        static let activeWindow = "Active window"
        static let inactiveWindows = "Inactive windows"
        static let floatingWindow = "Focused floating window"
        static let modeColors = "Mode Colors"
        static let modeColorsFooter = "The border of the focused window while a binding mode is active. It wins over the active and the floating colors. “Reset” removes the color of the mode. The main mode has no color of its own: it is the active color."
        static let noModes = "The config defines no binding mode besides main."
        static let notSet = "not set"
        static let active = "Active"
        static let inactive = "Inactive"
        static let floatingPreview = "Floating"
        static func points(_ value: Int) -> String { "\(value) pt" }

        // Gaps
        static let innerGaps = "Inner Gaps"
        static let outerGaps = "Outer Gaps"
        static let horizontal = "Horizontal"
        static let horizontalGapDetail = "Between two windows side by side."
        static let vertical = "Vertical"
        static let verticalGapDetail = "Between two windows one above the other."
        static let top = "Top"
        static let topGapDetail = "Below the menu bar."
        static let bottom = "Bottom"
        static let left = "Left"
        static let right = "Right"
        static let innerGapsFooter = "The borders are drawn in the gaps, outside of the windows: with inner gaps less than twice the width of the border, the borders of two windows touch."
        static let outerGapsFooter = "Between the windows and the edges of the screen. With outer gaps less than the width of the border, the edge of the screen cuts the border."
        static let actualSize = "Actual size"

        // Why a control is disabled
        static let definedByHand = "Defined by hand in the config file"
        static let needsAccessibility = "Grant the accessibility permission to change the settings."
        static let ambiguousConfig = "Several config files found. Keep only one of them."
        static func configHasErrors(_ file: String) -> String { "\(file) has errors. Fix them to change the settings from here." }
        static func writeFailed(_ reason: String) -> String { "Can't change the config file: \(reason)" }
    }
}

let configFileName = "inlay.toml"

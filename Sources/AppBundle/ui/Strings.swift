import Common

/// The texts of the menu bar item, its menu and the settings window, in one place so they can be localized later.
/// The interface is in English for now, like the CLI
enum Strings {
    enum Menu {
        static func workspaceAndApp(_ workspace: String, _ app: String?) -> String {
            "Workspace \(workspace)" + (app.map { " · \($0)" } ?? "")
        }
        static func reloaded(_ ago: String) -> String { "Config reloaded \(ago)" }
        static let window = "Window"
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
        static let grantAccessibility = "Grant Accessibility Permission…"
        static let paused = "\(inlayAppName) is paused"
        static let noFocusedWindow = "No focused window"
        static func layout(_ layout: MenuBarCard.WindowLayout) -> String {
            switch layout {
                case .tiling: "Tile the Focused Window"
                case .floating: "Float the Focused Window"
                case .fullscreen: "Make the Focused Window Fullscreen"
            }
        }
        static func layoutShort(_ layout: MenuBarCard.WindowLayout) -> String {
            switch layout {
                case .tiling: "Tiling"
                case .floating: "Floating"
                case .fullscreen: "Fullscreen"
            }
        }
        static let arrangeWorkspace = "Arrange Workspace"
        static func arrange(_ arrangement: WorkspaceArrangement) -> String {
            switch arrangement {
                case .dwindle: "Arrange the Workspace in Dwindle"
                case .grid: "Arrange the Workspace in a Grid"
                case .row: "Arrange the Workspace in a Row"
            }
        }
        static func arrangeShort(_ arrangement: WorkspaceArrangement) -> String {
            switch arrangement {
                case .dwindle: "Dwindle"
                case .grid: "Grid"
                case .row: "Row"
            }
        }
        static func modeHelp(_ mode: String, _ exitKey: String?) -> String {
            "Binding mode: \(mode)" + (exitKey.map { ". \($0) goes back to main" } ?? "")
        }
        static var version: String { "\(inlayAppName) \(inlayAppVersion)" }
    }

    enum Item {
        static let toolTip = "Click to open the \(inlayAppName) menu"
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
        static let menuBarPage = "Menu Bar"
        static let bordersPage = "Borders"
        static let windowsPage = "Windows"
        static let keyboard = "Keyboard"
        static let workspaceIndicator = "Workspace Indicator"
        static let style = "Style"
        static let borderColors = "Border Colors"
        static let indicatorColors = "Indicator Colors"
        static let indicatorColorsFooter = "'auto' draws the item in the color of the menu bar text, so it follows the light and the dark menu bar. A fixed color stays the same over both."
        static let activeWorkspaceColor = "Active workspace"
        static let inactiveWorkspaceColor = "Inactive workspaces (with windows)"
        static let emptyWorkspaceColor = "Empty workspaces"
        static let defaultValue = "default"
        static let gaps = "Gaps"
        static let reset = "Reset"

        // General
        static let startup = "Startup"
        static let startAtLogin = "Open at login"
        static let startAtLoginDetail = "\(inlayAppName) starts with your session and arranges the open windows."
        static let tiling = "Tiling"
        static let placement = "Placement"
        static let newWindows = "New Windows"
        static let arrangement = "Arrangement"
        static let workspaces = "Workspaces"
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
        static let animateDetail = "The windows slide to their place when a window opens or closes, when you move one with swap or move, and in and out of fullscreen."
        static let workspaceSwitch = "Switching workspaces"
        static let workspaceSwitchHorizontalDetail = "Horizontal: the windows slide sideways on every screen. With a screen on one side, in and out by the other side."
        static let workspaceSwitchVerticalDetail = "Vertical: the windows slide through the bottom of every screen. Not on a screen with another one below it."
        static let workspaceSwitchAutoDetail = "Auto: sideways, or through the bottom on a screen with another one on its left or on its right."
        static let workspaceSwitchOffDetail = "Off: the windows switch at once."
        static let auto = "Auto"
        static let off = "Off"
        static let duration = "Duration"
        static let durationDetail = "Shorter is snappier. 0 turns the animations off. With Reduce Motion on, nothing is animated."
        static func milliseconds(_ value: Int) -> String { "\(value) ms" }
        static let row = "Row"
        static let configuration = "Configuration"
        static let file = "File"
        static let showInFinder = "Show in Finder"
        static let open = "Open"
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

        // Appearance
        static let livePreview = "Live preview"
        static let dimEmpty = "Dim empty workspaces"
        static let dimEmptyDetail = "Workspaces without windows are drawn fainter."
        static let showMode = "Show the binding mode"
        static let showModeDetail = "Its initial in the marker of the focused workspace, when the mode isn't main."
        static let accent = "Binding mode"
        static let accentDetail = "The marker of the focused workspace while a binding mode (resize, service) is active."

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
        static let singleWindowBorder = "Border"
        static let singleWindowBorderDetail = "Off: the window fills the screen, without a border."
        static let singleWindowGap = "Gap"
        static let singleWindowGapDetail = "Between the window and the edges of the screen. Never less than the width of the border."
        static let singleWindowFooter = "A tiling window alone in its workspace, and a window in fullscreen, look the same: this border, in its colors, and this gap around the window."
        static let activeWindow = "Active window"
        static let inactiveWindows = "Inactive windows"
        static let floatingWindow = "Focused floating window"
        static let modeColors = "Mode Colors"
        static let modeColorsFooter = "The border of the focused window while a binding mode is active. It wins over the active and the floating colors. “Remove” takes the color away from the mode. The main mode has no color of its own: it is the active color."
        static let noModes = "The config defines no binding mode besides main."

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
        static let singleWindow = "Single Window and Fullscreen"

        static let defaultValueShort = "default"
        static let cantUndoChangedFile = "\(configFileName) changed since the last change of this window: undoing would write those changes away."
        static let copyKey = "Click to copy the line of the config"
        static let pointsUnit = "pt"
        static let millisecondsUnit = "ms"

        // The config folder. See: ConfigFolderLink
        static let configFolder = "Config folder"
        static let configFolderDetail = "It can be a link to a folder of yours, a dotfiles repo for example: Inlay reads and writes the inlay.toml in it."
        static func configFolderDotfile(_ dotfile: String) -> String { "Your config is ~/\(dotfile): a config folder would be a second config. To use one, move that file into a folder as inlay.toml and link it." }
        static let linkFolder = "Link to a Folder…"
        static let linkPrompt = "Link"
        static let linkPanelMessage = "Pick the folder of your config, or the inlay.toml in it"
        static let unlink = "Unlink"
        static let cancel = "Cancel"
        static func linkTitle(_ dir: String, _ folder: String) -> String { "Link \(dir) to \(folder)?" }
        static func linkDetail(_ folder: String, hasRealFolder: Bool) -> String {
            "Inlay will read and write \(folder)/inlay.toml. Nothing else of that folder is touched."
                + (hasRealFolder ? " Your current config folder isn't deleted: it is renamed, as a backup." : "")
        }
        static func noConfigInFolderTitle(_ folder: String) -> String { "\(folder) has no inlay.toml" }
        static func noConfigInFolderDetail(hasRealFolder: Bool) -> String {
            "It gets one before it is linked: a copy of the config you use now, or the default config of \(inlayAppName)."
                + (hasRealFolder ? " Your current config folder isn't deleted: it is renamed, as a backup." : "")
        }
        static let copyMyConfig = "Copy My Config"
        static let useDefaultConfig = "Use the Default Config"
        static func linkedTitle(_ dir: String, _ folder: String) -> String { "\(dir) is now a link to \(folder)" }
        static func backupKept(_ backup: String) -> String { "Your previous config folder wasn't deleted: it is now \(backup)" }
        static func unlinkTitle(_ dir: String) -> String { "Make \(dir) a folder of its own?" }
        static func unlinkDetail(_ folder: String) -> String {
            "It gets a copy of \(folder)/inlay.toml, and Inlay reads and writes that copy. \(folder) isn't touched."
        }
        static let cantLink = "The config folder can't be linked there"
        static func notAConfig(_ file: String) -> String { "\(file) isn't an inlay.toml. Pick the folder of your config, or the inlay.toml in it." }
        static func notAFolder(_ path: String) -> String { "\(path) isn't an existing folder." }
        static let isTheConfigFolder = "That is the config folder itself: it can't be a link to itself."
        static func alreadyLinked(_ folder: String) -> String { "The config folder is already a link to \(folder). Nothing was changed." }

        // General
        static let export = "Export complete config"
        static let exportDetail = "A copy of your config with your comments, plus every key you left out with the value that applies. Your file isn't touched."
        static let exportButton = "Export…"
        static let exportFileName = "inlay-complete.toml"
        static func exportHeader(_ date: String) -> String {
            "# Exported from \(inlayAppName) \(inlayAppVersion) on \(date).\n" +
                "# Your config with its comments, plus every key it left out, with the value that applies.\n\n"
        }
        static func exportFailed(_ reason: String) -> String { "Can't export the config: \(reason)" }

        // Tiling
        static let splitRatio = "Split ratio"
        static let splitRatioDetail = "How much of its space the split window keeps. 50%: half and half."

        // Labels
        static let remove = "Remove"
        static let labels = "Labels"
        static let labelsFooter = "Only the labels theme uses them: a symbol per workspace, and the name in the focused one. A workspace without a symbol shows its name. Symbols are SF Symbols names."
        static func labelPlaceholder(_ workspace: String) -> String { "Name (\(workspace))" }
        static let symbolPlaceholder = "SF Symbol"
        static func unknownSymbol(_ name: String) -> String { "There is no SF Symbol named '\(name)'" }
        static let suggestedSymbols = "Suggested symbols"
        static let noPersistentWorkspaces = "The config has no persistent workspaces to name."
        static let perMonitor = "Group by monitor"
        static let perMonitorDetail = "The workspaces of each monitor together, from left to right, and a hollow marker on the one another monitor shows."

        // Borders
        static let usesActiveColor = "Uses the active color"
        static let setColor = "Set Color…"

        // Keyboard
        static let editRules = "Rules and key bindings"
        static let editRulesDetail = "The rules that send the apps to their workspace, and the key bindings, are edited in the file."

        // Shortcuts
        static let shortcuts = "Shortcuts"
        static let filterShortcuts = "Filter"
        static let noShortcuts = "The config has no key bindings."
        static let noMatchingShortcuts = "No key binding matches the filter."
        static let shortcutsFooter = "The key bindings of the config, with the comment written after each one. They are edited in the file."

        // Why a control is disabled
        static let definedByHand = "Defined by hand in the config file"
        static let needsAccessibility = "Grant the accessibility permission to change the settings."
        static let ambiguousConfig = "Several config files found. Keep only one of them."
        static func configHasErrors(_ file: String) -> String { "\(file) has errors. Fix them to change the settings from here." }
        static func writeFailed(_ reason: String) -> String { "Can't change the config file: \(reason)" }
    }
}

let configFileName = "inlay.toml"

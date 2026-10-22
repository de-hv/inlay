import Common

/// The texts of the menu bar item, its menu and the settings window, in one place so they can be localized later.
/// The interface is in English for now, like the CLI
enum Strings {
    enum Menu {
        static func workspace(_ name: String) -> String { "Workspace \(name)" }
        static let noWindows = "No windows"
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
        static let on = "On"
        static let off = "Off"

        /// The label at the top of the card
        enum Status {
            static let running = "Tiling on"
            static let paused = "Paused"
            static let needsAccessibility = "No permission"
        }

        /// The short labels of the row of buttons of the card. Their tooltips are the whole names
        enum Tile {
            static let reload = "Reload"
            static let config = "Config"
            static let pause = "Pause"
            static let resume = "Resume"
            static let settings = "Settings"
            static let quit = "Quit"
        }
        static var version: String { "\(inlayAppName) \(inlayAppVersion)" }
        static var versionToCopy: String { "\(inlayAppName) v\(inlayAppVersion) \(gitHash)" }
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

    /// The theme as a whole: palette, wallpaper and hooks. See: ThemeController, ThemeCommand
    enum Theme {
        static func missingWallpaper(_ palette: String) -> String { "The wallpaper of \(palette) doesn't exist" }
        static func missingWallpaperDetail(_ path: String) -> String { "\(path) can't be found. Choose another one for the theme, or keep the wallpaper that is on the screen." }
        static let chooseWallpaper = "Choose…"
        static let keepWallpaper = "Keep Current"
        static func chooseWallpaperMessage(_ palette: String) -> String { "The wallpaper of \(palette). It is written in \(configFileName)." }
        static func paletteSet(_ palette: String) -> String { "Palette: \(palette)" }
        static func manualColorsNote(_ keys: [String]) -> String {
            "Colors written by hand win over the palette: \(keys.joined(separator: ", ")). 'inlay theme set <palette> --reset-colors' removes them."
        }
    }

    /// The notice that tells that the config was reloaded. See: ReloadNoticePanel
    enum Notice {
        static func reloaded(_ fileName: String) -> String { "\(fileName) reloaded" }
        static let noChanges = "No setting changed"
        static let added = "added"
        static let removed = "removed"
        static func more(_ count: Int) -> String { "+\(count) more" }
        static func warnings(_ count: Int) -> String { count == 1 ? "1 warning: see the menu" : "\(count) warnings: see the menu" }
    }

    enum Settings {
        static let windowTitle = "\(inlayAppName) Settings"
        static let general = "General"
        static let menuBar = "Menu Bar"
        static let borders = "Borders"
        static let themes = "Themes"
        static let workspaceIndicator = "Workspace Indicator"
        static let palette = "Palette"
        static let paletteFooter = "A palette colors the menu bar item and the borders, with a light and a dark variant that follow the appearance of the system. It gives every color you haven't set yourself in Colors."
        static let paletteSection = "Palette"
        static let indicatorSection = "Indicator"
        static let colorsSection = "Colors"
        static let madeForYou = "Made for You"
        static let palettes = "Palettes"
        static let systemPalette = "System"
        static let materialFromWallpaper = "Material · Wallpaper"
        static let materialFromColor = "Material · Color"
        static let borderColors = "Border Colors"
        static let indicatorInThemes = "The shape of the indicator, its options and its colors are in Themes."
        static let indicatorShapeFooter = "The shape of the item in the menu bar. Its colors are in Colors."
        static let colorsInThemes = "The colors of the indicator and of the borders are in Themes › Colors, next to the palette that gives them."
        static let noThemeTitle = "No theme"
        static func themeTitle(_ palette: String) -> String { "Theme: \(palette)" }
        static let themeInUseDetail = "Every color comes from the palette."
        static func seedFromWallpaperDetail(_ hex: String?) -> String {
            "The main color of the wallpaper of the main screen, like matugen" + (hex.map { ": \($0)." } ?? ". It is read when the config loads.")
        }
        static let indicatorColors = "Indicator Colors"
        static let indicatorColorsFooter = "Each color starts as the one of the theme. Changing one makes it yours: the theme no longer applies to it, until “Use Theme”."
        static let activeWorkspaceColor = "Active workspace"
        static let inactiveWorkspaceColor = "Inactive workspaces (with windows)"
        static let emptyWorkspaceColor = "Empty workspaces"
        static let themeBadge = "Theme"
        static let customBadge = "Custom"
        static let custom = "Custom"
        static let useTheme = "Use Theme"
        static let keepCustom = "Keep Custom Colors"
        static let noThemeInUse = "The colors of the system, and the ones you set."
        static func customInUse(_ colors: [String], base: String) -> String {
            "Custom colors: \(colors.joined(separator: ", ")). No theme applies to them; the rest come from \(base)."
        }
        static func useOnlyTheme(_ palette: String) -> String { "Use \(palette) for Every Color" }
        static func baseOf(_ palette: String) -> String { "\(palette) · base" }
        static func replaceCustomTitle(_ palette: String) -> String { "Use the \(palette) theme?" }
        static func replaceCustomDetail(_ colors: [String]) -> String {
            "Your custom colors (\(colors.joined(separator: ", "))) are removed from \(configFileName), so that the theme gives every color."
        }
        /// The name of a color that a palette gives, as the user knows it
        static func colorName(_ key: SettingsKey) -> String {
            switch key {
                case .menuBarFocused: "active workspace"
                case .menuBarOccupied: "inactive workspaces"
                case .menuBarEmpty: "empty workspaces"
                case .menuBarAccent: "binding mode"
                case .bordersActiveColor: "active border"
                case .bordersInactiveColor: "inactive borders"
                case .bordersFloatingColor: "floating border"
                default: key.label
            }
        }
        static let seed = "Seed"
        static let seedDetail = "Material You is made from this color, the way matugen makes it from a wallpaper. 'system-accent' follows the accent color of macOS."
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
        static let windows = "Windows"
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
        static let hideWhenSingle = "Hide with a single window"
        static let hideWhenSingleDetail = "No border around the only tiling window of a workspace, also with gaps around it. Smart gaps remove it anyway."
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
        static let singleWindow = "Single Window"
        static let smartGaps = "Smart gaps"
        static let smartGapsDetail = "The only tiling window of a workspace takes the whole screen, without outer gaps nor border."

        // Why a control is disabled
        static let definedByHand = "Defined by hand in the config file"
        static let needsAccessibility = "Grant the accessibility permission to change the settings."
        static let ambiguousConfig = "Several config files found. Keep only one of them."
        static func configHasErrors(_ file: String) -> String { "\(file) has errors. Fix them to change the settings from here." }
        static func writeFailed(_ reason: String) -> String { "Can't change the config file: \(reason)" }
    }
}

let configFileName = "inlay.toml"

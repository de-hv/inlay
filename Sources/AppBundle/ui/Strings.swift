import Common

/// The texts of the menu bar item and its menu, in one place so they can be localized later.
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
}

let configFileName = "inlay.toml"

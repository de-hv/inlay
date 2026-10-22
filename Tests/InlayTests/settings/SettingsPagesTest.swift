@testable import AppBundle
import AppKit
import Common
import Foundation
import Testing

extension InlayTests {
    /// The Workspaces and Shortcuts pages, the undo of the window, and the export of the config
    @Suite @MainActor final class SettingsPagesTest {
        private let directory: URL
        private let file: URL

        init() throws {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
            directory = FileManager.default.temporaryDirectory.appending(path: "inlay-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            file = directory.appending(path: "inlay.toml")
        }

        deinit {
            _ = try? FileManager.default.removeItem(at: directory)
        }

        private var text: String? { try? String(contentsOf: file, encoding: .utf8) }

        private func model(_ text: String) throws -> SettingsModel {
            try text.write(to: file, atomically: true, encoding: .utf8)
            let file = file
            let model = SettingsModel(loadTarget: {
                Result { try String(contentsOf: file, encoding: .utf8) }
                    .map { .init(url: file, text: $0, exists: true) }
                    .mapError { .unreadable($0.localizedDescription) }
            }, reloadsConfig: false)
            model.refresh()
            return model
        }

        private let config = """
            config-version = 2
            persistent-workspaces = ["1", "2"]

            [mode.main.binding]
                cmd-alt-ctrl-j = ['workspace 1', 'mode main'] # terminals
                cmd-alt-shift-j = ['layout tiling', 'move-node-to-workspace 1']
                cmd-alt-ctrl-u = 'workspace 3'
                cmd-alt-ctrl-m = 'mode service'

            [mode.service.binding]
                esc = ['reload-config', 'mode main']

            [[on-window-detected]]
                if.app-id = 'com.example.term' # Term (the terminal)
                run = ['layout tiling', 'move-node-to-workspace 1']

            [[on-window-detected]]
                if.app-id = 'com.example.calc'
                run = 'layout floating'

            """

        @Test func testWorkspaces() throws {
            let model = try model(config)
            let summary = WorkspaceSummaries.make(root: model.rawRoot)
            assertEquals(summary.workspaces, [
                WorkspaceSummary(name: "1", isPersistent: true, apps: ["com.example.term"], goKey: "cmd-alt-ctrl-j", moveKey: "cmd-alt-shift-j"),
                WorkspaceSummary(name: "2", isPersistent: true),
                WorkspaceSummary(name: "3", isPersistent: false, goKey: "cmd-alt-ctrl-u"),
            ])
            assertEquals(summary.floatingApps, ["com.example.calc"])
            // The comment after the id names an app that isn't installed
            assertEquals(appDisplayName("com.example.term", in: model.fileDocument), "Term")
            assertEquals(appDisplayName("com.example.calc", in: model.fileDocument), "calc")
            assertEquals(WorkspaceSummaries.target(of: "move-node-to-workspace --focus-follows-window 4", command: "move-node-to-workspace"), "4")
            assertEquals(WorkspaceSummaries.target(of: "workspace next", command: "workspace"), nil)

            // Persistent: the array of the file, in one line
            assertEquals(model.unavailableReason, nil)
            assertEquals(parseConfig(config).errors.map { $0.description(.error) }, [])
            model.set(.persistentWorkspaces, .strings(["1", "2", "3"]))
            assertEquals(model.errorMessage, nil)
            assertEquals(text?.contains("\npersistent-workspaces = [\"1\", \"2\", \"3\"]\n"), true)
            assertEquals(model.strings(.persistentWorkspaces), ["1", "2", "3"])
        }

        @Test func testShortcuts() throws {
            let model = try model(config)
            let modes = ShortcutEntries.make(model.fileDocument, root: model.rawRoot)
            assertEquals(modes.map(\.mode), ["main", "service"])
            assertEquals(modes[0].entries.first, ShortcutEntry(key: "cmd-alt-ctrl-j", commands: ["workspace 1", "mode main"], comment: "terminals"))
            assertEquals(modes[1].entries, [ShortcutEntry(key: "esc", commands: ["reload-config", "mode main"], comment: nil)])
            assertEquals(prettyKeyNotation("cmd-alt-ctrl-j"), "⌃⌥⌘J")
            assertEquals(prettyKeyNotation("cmd-alt-shift-left"), "⌥⇧⌘←")
            assertEquals(prettyKeyNotation("alt-comma"), "⌥,")
            assertEquals(prettyKeyNotation("esc"), "⎋")
        }

        @Test func testUndoAndRedo() throws {
            let model = try model("[borders]\nwidth = 4 # the border\n")
            model.set(.bordersWidth, .int(6))
            model.set(.bordersGlow, .bool(true))
            assertEquals(model.undoStack.map(\.summary), ["[borders] width: 4 → 6", "[borders] glow: default → true"])
            model.undo()
            assertEquals(text, "[borders]\nwidth = 6 # the border\n")
            model.undo()
            assertEquals(text, "[borders]\nwidth = 4 # the border\n")
            assertEquals(model.undoStack, [])
            model.redo()
            assertEquals(model.int(.bordersWidth), 6)
            // Changed by hand since: undoing would write that change away
            try "[borders]\nwidth = 9\n".write(to: file, atomically: true, encoding: .utf8)
            model.undo()
            assertEquals(text, "[borders]\nwidth = 9\n")
            assertEquals(model.errorMessage, Strings.Settings.cantUndoChangedFile)
            assertEquals(model.undoStack, [])
        }

        /// An empty text removes a key without a default: the labels of the 'labels' theme
        @Test func testEmptyLabelRemovesTheKey() throws {
            let model = try model("[menu-bar]\ntheme = 'labels'\n")
            model.setDebounced(.menuBarLabel("1"), .string("Terminals"))
            model.commit(.menuBarLabel("1"))
            assertEquals(model.menuBarConfig.labels, ["1": "Terminals"])
            assertEquals(text?.contains("[menu-bar.labels]\n1 = 'Terminals'"), true)
            model.setDebounced(.menuBarLabel("1"), .string(""))
            model.commit(.menuBarLabel("1"))
            assertEquals(model.menuBarConfig.labels, [:])
            assertEquals(text?.contains("1 = "), false)
        }

        @Test func testExport() throws {
            let model = try model("# My config\n[borders]\n    width = 6 # thin\n")
            let exported = try #require(model.exportText)
            // The comments and the values of the user stay
            assertEquals(exported.contains("# My config\n[borders]\n    width = 6 # thin\n"), true)
            // Every key left out is there, with the value that applies
            assertEquals(TomlPatcher.decodedValue(exported, SettingsKey.bordersGlow.path) as? Bool, false)
            assertEquals(TomlPatcher.decodedValue(exported, SettingsKey.menuBarTheme.path) as? String, "liquid")
            assertEquals(TomlPatcher.decodedValue(exported, SettingsKey.splitRatio.path) as? Double, 0.5)
            assertEquals(parseConfig(exported).errors.map { $0.description(.error) }, [])
            // The file itself isn't touched
            assertEquals(text, "# My config\n[borders]\n    width = 6 # thin\n")
        }

        @Test func testSearch() {
            assertEquals(SettingsSearch.results("glow").map(\.title), [Strings.Settings.glow, Strings.Settings.glowRadius])
            assertEquals(SettingsSearch.results("corner-radius").map(\.page), [.borders])
            assertEquals(SettingsSearch.results("labels").first?.themesSection, .indicator)
            assertEquals(SettingsSearch.results(""), [])
        }
    }
}

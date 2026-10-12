@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// The windows that are already open when Inlay starts to manage the windows go to the workspaces of their
    /// 'on-window-detected' rules, and then every workspace is arranged. With the rules of inlay.toml, the config
    /// that Inlay ships with.
    ///
    /// The windows are registered by the same code as the real ones (Window.afterRegistration), and the rest of the
    /// refresh session is the real one too. Only the part that asks macOS for the windows is missing
    @Suite @MainActor struct StartupRulesTest {
        private static let ghostty = FakeApp("com.mitchellh.ghostty")
        private static let zed = FakeApp("dev.zed.Zed")
        private static let chrome = FakeApp("com.google.Chrome")
        private static let slack = FakeApp("com.tinyspeck.slackmacgap")
        private static let claude = FakeApp("com.anthropic.claudefordesktop")
        private static let finder = FakeApp("com.apple.finder")
        /// Apps that inlay.toml knows nothing about
        private static let notes = FakeApp("com.example.notes")
        private static let player = FakeApp("com.example.player")

        init() {
            setUpWorkspacesForTests()
            // The workspaces and the rules of inlay.toml, which setUpWorkspacesForTests drops
            config.persistentWorkspaces = defaultConfig.persistentWorkspaces
            config.onWindowDetected = defaultConfig.onWindowDetected
            // Otherwise normalizeLayoutReason asks the real app of the window whether it is hidden
            config.automaticallyUnhideMacosHiddenApps = true
            check(Workspace.get(byName: "1").focusWorkspace())
            Workspace.garbageCollectUnusedWorkspaces()
            assertEquals(Workspace.all.map(\.name), ["1", "2", "3", "4", "5", "6"])
            assertEquals(config.onWindowDetected.count, 29)
        }

        // MARK: - The rules of inlay.toml

        /// An app with a workspace, an app without one, and a dialog
        @Test func testAssignedApp_unassignedApp_andDialog() async throws {
            try await open(1, Self.zed)
            try await open(2, Self.notes)
            try await open(3, Self.notes, type: .dialog)
            assertEquals(tiling("2"), [1])
            // No rule for the app: workspace 6
            assertEquals(tiling("6"), [2])
            // The dialog floats where it was opened
            assertEquals(floating("1"), [3])
            assertEquals(tiling("1"), [])
            // The focus stays where it was, like it does for the apps with a workspace
            assertEquals(focus.workspace.name, "1")
        }

        @Test func testEveryAppWithAWorkspace() async throws {
            let apps = [
                ("com.mitchellh.ghostty", "1"), ("dev.zed.Zed", "2"), ("com.microsoft.VSCode", "2"),
                ("com.google.Chrome", "3"), ("app.zen-browser.zen", "3"),
                ("com.tinyspeck.slackmacgap", "4"), ("com.microsoft.teams2", "4"), ("ru.keepcoder.Telegram", "4"), ("net.whatsapp.WhatsApp", "4"),
                ("com.anthropic.claudefordesktop", "5"),
            ]
            for (index, (app, workspace)) in apps.enumerated() {
                let id = UInt32(index + 1)
                try await open(id, FakeApp(app))
                assertEquals(window(id).nodeWorkspace?.name, workspace, additionalMsg: app)
                assertEquals(window(id).isFloating, false, additionalMsg: app)
            }
            assertEquals(tiling("6"), [])
        }

        /// The catch-all rule is the last one, and only for the tiling windows: it takes nothing from the rules above it
        @Test func testWhatDoesNotGoToWorkspace6() async throws {
            check(Workspace.get(byName: "3").focusWorkspace())
            // The apps that float
            try await open(1, Self.finder)
            try await open(2, FakeApp("com.apple.systempreferences"))
            // The settings window of any app, by its title
            try await open(3, Self.notes, title: "Notes Settings")
            // The panel to open a file: it belongs to the app, and the rule of the app would tile it in workspace 2
            try await open(4, Self.zed, title: "Open")
            // Dialogs, of an app without a workspace: an alert, and one that Inlay finds in another workspace
            try await open(5, Self.player, type: .dialog)
            try await open(6, Self.player, type: .dialog, in: Workspace.get(byName: "5"))
            // A popup (a menu, a tooltip) never gets to the rules
            try await open(7, Self.player, type: .popup)

            assertEquals(floating("3"), [1, 2, 3, 4, 5])
            assertEquals(floating("5"), [6])
            assertEquals(macosPopupWindowsContainer.children.map { ($0 as! Window).windowId }, [7])
            for workspace in Workspace.all { assertEquals(tiling(workspace.name), [], additionalMsg: workspace.name) }

            // And the dialog of an app with a workspace is the business of the rule of the app, as before
            try await open(8, Self.chrome, type: .dialog, in: Workspace.get(byName: "5"))
            assertEquals(tiling("3"), [8])
        }

        /// A window that the user moves out of workspace 6 stays where it is put: the rules run once per window
        @Test func testAWindowMovedOutOfWorkspace6Stays() async throws {
            try await open(1, Self.notes)
            assertEquals(tiling("6"), [1])
            assertEquals(await parseCommand("move-node-to-workspace --window-id 1 2").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            try await restOfTheSession()
            assertEquals(tiling("2"), [1])
            assertEquals(tiling("6"), [])
        }

        // MARK: - (a) All the windows that are already open

        /// Not a grid with all of them in the workspace that is on the screen: every window in the workspace of its app,
        /// and then a grid per workspace
        @Test func testStartup_everyWindowGoesToItsWorkspace_thenTheGrid() async throws {
            let open: [(UInt32, FakeApp)] = [
                (1, Self.ghostty), (2, Self.chrome), (3, Self.zed), (4, Self.claude), (5, Self.slack), (6, Self.notes),
                (7, Self.ghostty), (8, Self.chrome), (9, Self.ghostty), (10, Self.player), (11, Self.chrome), (12, Self.finder),
                (13, Self.chrome), (14, Self.chrome),
            ]
            try await $refreshSessionEvent.withValue(.startup) {
                assertEquals(isStartup, true)
                StartupArrangement.begin()
                for (id, app) in open { try await self.open(id, app) }
                try await restOfTheSession()
            }
            assertEquals(Workspace.get(byName: "1").rootTilingContainer.layoutDescription, .v_tiles([.h_tiles([.window(1), .window(7)]), .window(9)]))
            assertEquals(Workspace.get(byName: "2").rootTilingContainer.layoutDescription, .h_tiles([.window(3)]))
            assertEquals(
                Workspace.get(byName: "3").rootTilingContainer.layoutDescription,
                .v_tiles([.h_tiles([.window(2), .window(8), .window(11)]), .h_tiles([.window(13), .window(14)])]),
            )
            assertEquals(tiling("4"), [5])
            assertEquals(tiling("5"), [4])
            assertEquals(Workspace.get(byName: "6").rootTilingContainer.layoutDescription, .h_tiles([.window(6), .window(10)]))
            assertEquals(floating("1"), [12])
            // Nothing is left behind in the workspace that was on the screen, but its own windows
            assertEquals(Workspace.all.flatMap(\.allLeafWindowsRecursive).count, open.count)
        }

        /// The session that finds a window doesn't have to be the one of the startup: every window gets its rules,
        /// whichever session registers it
        @Test func testTheRulesDoNotDependOnTheSessionThatFindsTheWindow() async throws {
            assertEquals(isStartup, false)
            StartupArrangement.begin()
            try await open(1, Self.ghostty)
            try await $refreshSessionEvent.withValue(.ax("AXFocusedWindowChanged")) { try await open(2, Self.chrome) }
            try await $refreshSessionEvent.withValue(.globalObserver("didActivateApplication")) { try await open(3, Self.notes) }
            try await $refreshSessionEvent.withValue(.startup) { try await open(4, Self.zed) }
            try await restOfTheSession()
            try await open(5, Self.claude) // A new window, long after the startup
            assertEquals(Workspace.all.map { tiling($0.name) }, [[1], [4], [2], [], [5], [3]])
        }

        // MARK: - (b) The built-in config is loaded before the config of the user

        /// Inlay loads the built-in config first, and then the config of the user. Both are loaded before the first
        /// window is registered, so the rules that run are the ones of the user. This is also the order when the
        /// Accessibility permission is granted after Inlay was opened: nothing is loaded or registered until then
        @Test func testTheRulesOfTheUserRunNotTheOnesOfTheBuiltInConfig() async throws {
            let user = try temporaryConfig(
                rules: """
                [[on-window-detected]]
                if.app-id = 'com.mitchellh.ghostty'
                run = 'move-node-to-workspace 4'
                """,
            )
            defer { ServerState.shared.lastConfigLoad = nil }
            assertEquals(await reloadConfig_nonCancellable(forceConfigUrl: user).isOk, true)
            assertEquals(config.onWindowDetected.count, 1)
            StartupArrangement.begin()
            try await open(1, Self.ghostty) // Workspace 1 in inlay.toml
            try await open(2, Self.notes) // Workspace 6 in inlay.toml
            try await restOfTheSession()
            assertEquals(tiling("4"), [1])
            assertEquals(tiling("1"), [2])
            assertEquals(tiling("6"), [])
        }

        // MARK: - (c) reload-config

        /// Reloading the config runs no rule: the windows stay where they are, also the ones that the user moved away
        /// from the workspace of their app, and with rules that are new. The new rules are for the next windows
        @Test func testReloadConfigDoesNotRunTheRules() async throws {
            StartupArrangement.begin()
            try await open(1, Self.ghostty)
            try await open(2, Self.chrome)
            try await open(3, Self.notes)
            try await restOfTheSession()
            // The user moves the browser next to the terminal
            assertEquals(await parseCommand("move-node-to-workspace --window-id 2 1").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(Workspace.all.map { tiling($0.name) }, [[1, 2], [], [], [], [], [3]])

            let edited = try temporaryConfig(
                rules: """
                [[on-window-detected]]
                if = 'true'
                run = 'move-node-to-workspace 5'
                """,
            )
            defer { ServerState.shared.lastConfigLoad = nil }
            let command = ReloadConfigCommand(args: ReloadConfigCmdArgs(rawArgs: []))
            assertEquals(await reloadConfig_nonCancellable(args: command.args, forceConfigUrl: edited).isOk, true)
            assertEquals(config.onWindowDetected.count, 1)
            // The refresh session that follows the command
            try await restOfTheSession()
            assertEquals(Workspace.all.map { tiling($0.name) }, [[1, 2], [], [], [], [], [3]])

            try await open(4, Self.ghostty)
            assertEquals(tiling("5"), [4])
            // Running them again is something the user asks for
            assertEquals(await parseCommand("run-callback on-window-detected --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(Workspace.all.map { tiling($0.name) }, [[1], [], [], [], [2, 4], [3]])
        }

        // MARK: - (d) startup-layout comes after the rules

        /// The layout is 'row' in the config of the user: it is the one in effect when the windows are arranged
        @Test func testStartupLayoutOfTheUser() async throws {
            config.tiling.startupLayout = .row
            StartupArrangement.begin()
            for id in 1 ... 5 as ClosedRange<UInt32> { try await open(id, Self.chrome) }
            try await open(6, Self.ghostty)
            try await restOfTheSession()
            assertEquals(Workspace.get(byName: "3").rootTilingContainer.layoutDescription, .h_tiles((1 ... 5).map { .window($0) }))
            assertEquals(tiling("1"), [6])
        }

        /// A minimized window is still a window of its app: when it comes back, it comes back to the workspace of the rule
        @Test func testStartup_minimizedWindow() async throws {
            StartupArrangement.begin()
            try await open(1, Self.ghostty)
            try await open(2, Self.chrome, minimized: true)
            try await open(3, Self.notes, minimized: true)
            try await restOfTheSession()
            assertEquals(macosMinimizedWindowsContainer.children.map { ($0 as! Window).windowId }.sorted(), [2, 3])
            assertEquals(Workspace.all.map { tiling($0.name) }, [[1], [], [], [], [], []])
            window(2).isMacosMinimizedForTest = false
            window(3).isMacosMinimizedForTest = false
            try await restOfTheSession()
            assertEquals(Workspace.all.map { tiling($0.name) }, [[1], [], [2], [], [], [3]])
        }

        // MARK: - Helpers

        /// What MacWindow.getOrRegister does with a window that it finds: it is placed in the workspace where it is,
        /// by its type, and then registered
        private func open(
            _ id: UInt32,
            _ app: FakeApp,
            title: String? = nil,
            type: AxUiElementWindowType = .window,
            in workspace: Workspace? = nil,
            minimized: Bool = false,
            titleGate: AwaitableOneTimeBroadcastLatch? = nil,
        ) async throws {
            let workspace = workspace ?? focus.workspace
            let window = switch type {
                case .window: TestWindow.newTiling(id: id, workspace: workspace, app: app)
                case .dialog: TestWindow.new(id: id, parent: workspace.floatingWindowsContainer, app: app)
                case .popup: TestWindow.new(id: id, parent: macosPopupWindowsContainer, app: app)
            }
            window.detectedType = type
            window.titleForTest = title ?? "\(app.rawAppBundleId ?? "") — window \(id)"
            window.titleGateForTest = titleGate
            window.isMacosMinimizedForTest = minimized
            try await window.afterRegistration()
        }

        /// What a complete refresh session does once it has gone through all the windows. See: runHeavyCompleteRefreshSession
        private func restOfTheSession() async throws {
            Workspace.garbageCollectUnusedWorkspaces()
            try await normalizeLayoutReason()
            StartupArrangement.finish()
            for workspace in Workspace.all { workspace.normalizeContainers() }
        }

        /// A config file with six workspaces and these rules
        private func temporaryConfig(rules: String) throws -> URL {
            let text = """
                config-version = 2
                persistent-workspaces = ['1', '2', '3', '4', '5', '6']
                automatically-unhide-macos-hidden-apps = true # See: init

                """ + rules
            let url = FileManager.default.temporaryDirectory.appending(path: "inlay-startup-rules-\(UUID().uuidString).toml")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        private func window(_ id: UInt32, orNil: Bool) -> TestWindow? {
            let outsideOfTheWorkspaces = (macosMinimizedWindowsContainer.children + macosPopupWindowsContainer.children).filterIsInstance(of: Window.self)
            return (Workspace.all.flatMap(\.allLeafWindowsRecursive) + outsideOfTheWorkspaces).first { $0.windowId == id } as? TestWindow
        }

        private func window(_ id: UInt32) -> TestWindow { window(id, orNil: false).orDie("No window \(id)") }

        private func tiling(_ workspace: String) -> [UInt32] {
            Workspace.get(byName: workspace).rootTilingContainer.allLeafWindowsRecursive.map(\.windowId).sorted()
        }

        private func floating(_ workspace: String) -> [UInt32] {
            Workspace.get(byName: workspace).floatingWindows.map(\.windowId).sorted()
        }
    }
}

/// An app with a bundle id of its own, for the rules that match the windows by their app
private final class FakeApp: AbstractApp {
    let pid: Int32
    let rawAppBundleId: String?
    let name: String?
    let execPath: String? = nil
    let bundlePath: String? = nil

    @MainActor private static var lastPid: Int32 = 1000

    @MainActor
    init(_ bundleId: String) {
        Self.lastPid += 1
        pid = Self.lastPid
        rawAppBundleId = bundleId
        name = bundleId.split(separator: ".").last.map(String.init)
    }

    @MainActor func getFocusedWindow(_ cm: CancellationMode) -> Window? { nil }
}

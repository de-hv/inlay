@testable import AppBundle
import AppKit
import Common
import Foundation
import SwiftUI
import Testing

extension InlayTests {
    @Suite @MainActor final class SettingsModelTest {
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

        /// A model over the file of the test. Without a file, the text is used as the built-in config
        private func model(_ text: String? = nil, builtIn: String = "[mode.main.binding]\n") throws -> SettingsModel {
            if let text { try text.write(to: file, atomically: true, encoding: .utf8) }
            let file = file
            let model = SettingsModel {
                switch try? String(contentsOf: file, encoding: .utf8) {
                    case let text?: .success(.init(url: file, text: text, exists: true))
                    case nil: .success(.init(url: file, text: builtIn, exists: false))
                }
            }
            model.refresh()
            return model
        }

        @Test func testDefaults() throws {
            let model = try model("[mode.main.binding]\n")
            assertEquals(model.unavailableReason, nil)
            assertEquals(model.bool(.startAtLogin), false)
            assertEquals(model.string(.newWindowPlacement), "dwindle")
            assertEquals(model.string(.startupLayout), "grid")
            assertEquals(model.string(.splitTarget), "focused")
            assertEquals(model.int(.minWindowSize), 100)
            assertEquals(model.string(.menuBarTheme), "chips")
            assertEquals(model.bool(.menuBarEnabled), true)
            assertEquals(model.color(.menuBarAccent), .auto)
            assertEquals(model.color(.menuBarFocused), .auto)
            assertEquals(model.int(.bordersWidth), 4)
            assertEquals(model.isSet(.menuBarTheme), false)
            assertEquals(model.disabledReason(.menuBarTheme), nil)
            // The same as an empty [menu-bar] table
            assertEquals(model.menuBarConfig, MenuBarConfig())
        }

        @Test func testReadsTheFile() throws {
            let model = try model(
                """
                start-at-login = true
                [menu-bar]
                theme = 'square'
                show-mode = true
                [menu-bar.colors]
                focused = '#D19A66'
                [mode.main.binding]

                """,
            )
            assertEquals(model.bool(.startAtLogin), true)
            assertEquals(model.isSet(.menuBarTheme), true)
            assertEquals(model.isSet(.menuBarDimEmpty), false)
            let expected = MenuBarConfig(theme: .square, showMode: true, colors: MenuBarColors(focused: .rgba(Rgba(hex: "#D19A66").orDie())))
            assertEquals(model.menuBarConfig, expected)
        }

        /// A config that the window of a previous version wrote: the theme and the key of the app icons, which are gone.
        /// The window shows 'chips', every control works, and picking a theme leaves the file without them
        @Test func testAConfigWithTheAppIconsOfThePast() throws {
            let model = try model("config-version = 2\n[menu-bar]\ntheme = 'chips-icons'\nshow-app-icons = true\n[mode.main.binding]\n")
            assertEquals(model.unavailableReason, nil)
            assertEquals(model.menuBarTheme, .chips)
            assertEquals(model.menuBarConfig, MenuBarConfig())
            assertEquals(model.disabledReason(.menuBarTheme), nil)
            // Another control: the file is edited as it is
            model.set(.menuBarShowMode, .bool(true))
            assertEquals(model.errorMessage, nil)
            assertEquals(text, "config-version = 2\n[menu-bar]\ntheme = 'chips-icons'\nshow-app-icons = true\nshow-mode = true\n[mode.main.binding]\n")
            model.setTheme(.chips)
            assertEquals(model.errorMessage, nil)
            assertEquals(text, "config-version = 2\n[menu-bar]\ntheme = 'chips'\nshow-mode = true\n[mode.main.binding]\n")
            assertEquals(parseConfig(text ?? "").warnings, [])
        }

        @Test func testSetAndReset() throws {
            let model = try model("# My config\n[mode.main.binding]\n")
            model.set(.menuBarTheme, .string("square"))
            assertEquals(model.errorMessage, nil)
            assertEquals(text, "# My config\n[mode.main.binding]\n\n[menu-bar]\ntheme = 'square'\n")
            assertEquals(model.menuBarTheme, .square)
            assertEquals(model.isSet(.menuBarTheme), true)

            model.set(.startAtLogin, .bool(true))
            assertEquals(text, "start-at-login = true\n\n# My config\n[mode.main.binding]\n\n[menu-bar]\ntheme = 'square'\n")

            model.reset(.menuBarTheme)
            assertEquals(text, "start-at-login = true\n\n# My config\n[mode.main.binding]\n\n[menu-bar]\n")
            assertEquals(model.menuBarTheme, .chips)
            assertEquals(model.isSet(.menuBarTheme), false)
        }

        // MARK: - [borders.mode-colors]

        @Test func testColorableModesAreTheModesOfTheConfigButMain() throws {
            assertEquals(try model("[mode.main.binding]\n").colorableModes, [])
            let model = try model(
                """
                [mode.service.binding]
                esc = 'mode main'
                [mode.main.binding]
                alt-r = 'mode resize'
                [mode.resize.binding]
                esc = 'mode main'
                [mode.'my mode'.binding]
                esc = 'mode main'

                """,
            )
            assertEquals(model.unavailableReason, nil)
            assertEquals(model.colorableModes, ["my mode", "resize", "service"])
            // A mode without a color: nothing to reset, and the row shows the active color
            let resize = SettingsKey.bordersModeColor("resize")
            assertEquals(resize.label, "[borders.mode-colors] resize")
            assertEquals(model.isSet(resize), false)
            assertEquals(model.string(resize), "")
            assertEquals(model.disabledReason(resize), nil)
        }

        @Test func testSetAndResetAModeColor() throws {
            let config = "[borders]\n    width = 6\n\n# The modes\n[mode.main.binding]\n[mode.resize.binding]\n[mode.'my mode'.binding]\n"
            let model = try model(config)
            let resize = SettingsKey.bordersModeColor("resize"), myMode = SettingsKey.bordersModeColor("my mode")

            // The table doesn't exist: it is added after its parent
            model.set(resize, .string("#30D158"))
            assertEquals(model.errorMessage, nil)
            assertEquals(
                text,
                "[borders]\n    width = 6\n\n    [borders.mode-colors]\n        resize = '#30D158'\n\n# The modes\n[mode.main.binding]\n[mode.resize.binding]\n[mode.'my mode'.binding]\n",
            )
            assertEquals(model.isSet(resize), true)
            assertEquals(model.color(resize), .rgba(Rgba(hex: "#30D158").orDie()))
            // The name of a mode is a key like any other: quoted if it has to be
            model.set(myMode, .string("system-accent"))
            assertEquals(text?.contains("        resize = '#30D158'\n        'my mode' = 'system-accent'\n\n# The modes"), true)
            let parsed = parseConfig(text ?? "")
            assertEquals(parsed.errors, [])
            assertEquals(parsed.config.borders.modeColors, ["resize": .rgba(Rgba(hex: "#30D158").orDie()), "my mode": .systemAccent])
            assertEquals(parsed.config.borders.width, 6)

            // "Reset" removes the key. The mode keeps the normal colors again
            model.reset(resize)
            assertEquals(model.isSet(resize), false)
            assertEquals(parseConfig(text ?? "").config.borders.modeColors, ["my mode": .systemAccent])
            model.reset(myMode)
            assertEquals(parseConfig(text ?? "").config.borders.modeColors, [:])
            assertEquals(text, "[borders]\n    width = 6\n\n    [borders.mode-colors]\n\n# The modes\n[mode.main.binding]\n[mode.resize.binding]\n[mode.'my mode'.binding]\n")

            // The color picker: shown right away, written once it stops changing
            model.setDebounced(resize, .string("#FF453A"))
            assertEquals(model.color(resize), .rgba(Rgba(hex: "#FF453A").orDie()))
            assertEquals(model.isSet(resize), true)
            assertEquals(text?.contains("FF453A"), false)
            model.commit(resize)
            assertEquals(text?.contains("    [borders.mode-colors]\n    resize = '#FF453A'\n"), true)

            // Something that isn't a color is refused, and nothing is written
            let before = text
            model.set(resize, .string("green"))
            assertEquals(model.errorMessage?.contains("Can't parse color 'green'"), true)
            assertEquals(text, before)
        }

        @Test func testModeColorsDefinedByHand() throws {
            let model = try model("borders.mode-colors = { resize = '#30D158' }\n[mode.main.binding]\n[mode.resize.binding]\n")
            assertEquals(model.disabledReason(.bordersModeColor("resize")), "Defined by hand in the config file")
            // In the table of the built-in config, with its examples commented out
            let builtIn = try String(contentsOf: projectRoot.appending(path: "inlay.toml"), encoding: .utf8)
            let withTable = try self.model(builtIn)
            assertEquals(withTable.colorableModes, ["resize", "service"])
            withTable.set(.bordersModeColor("service"), .string("#FF453A"))
            assertEquals(withTable.errorMessage, nil)
            assertEquals(text?.contains("    [borders.mode-colors]\n    service = '#FF453A'\n        # resize = '#30D158'\n"), true)
            assertEquals(parseConfig(text ?? "").config.borders.modeColors, ["service": .rgba(Rgba(hex: "#FF453A").orDie())])
        }

        @Test func testSetTheme() throws {
            let model = try model("[menu-bar]\ntheme = 'chips'\n[mode.main.binding]\n")
            model.setTheme(.minimal)
            assertEquals(text, "[menu-bar]\ntheme = 'minimal'\n[mode.main.binding]\n")
            assertEquals(model.menuBarTheme, .minimal)
        }

        @Test func testFirstChangeCreatesTheFile() throws {
            let model = try model(builtIn: "# The built-in config\n[mode.main.binding]\n")
            assertEquals(model.target?.exists, false)
            assertEquals(FileManager.default.fileExists(atPath: file.path), false)
            // Looking at the settings doesn't create it
            _ = model.menuBarConfig
            assertEquals(FileManager.default.fileExists(atPath: file.path), false)
            model.set(.menuBarDimEmpty, .bool(false))
            assertEquals(text, "# The built-in config\n[mode.main.binding]\n\n[menu-bar]\ndim-empty-workspaces = false\n")
            assertEquals(model.target?.exists, true)
        }

        /// Regression: the window used to patch the text it had read when it was opened
        @Test func testChangesMadeOutsideOfTheWindowAreKept() throws {
            let model = try model("# My config\n[menu-bar]\ntheme = 'chips'\n[mode.main.binding]\n")
            // The user edits the file in an editor while the window is open. Nothing reloads the config
            let edited = "# My config, edited\nstart-at-login = true\n[menu-bar]\ntheme = 'minimal'\n[mode.main.binding]\nalt-h = 'focus left'\n"
            try edited.write(to: file, atomically: true, encoding: .utf8)
            assertEquals(model.menuBarTheme, .chips) // The window still shows what it read

            model.set(.menuBarShowMode, .bool(true))
            assertEquals(model.errorMessage, nil)
            assertEquals(text, "# My config, edited\nstart-at-login = true\n[menu-bar]\ntheme = 'minimal'\nshow-mode = true\n[mode.main.binding]\nalt-h = 'focus left'\n")
            // And the window has caught up
            assertEquals(model.menuBarTheme, .minimal)
            assertEquals(model.bool(.startAtLogin), true)

            // The same for a value that was being previewed
            try "[menu-bar]\n# A new comment\ntheme = 'square'\n[mode.main.binding]\n".write(to: file, atomically: true, encoding: .utf8)
            model.preview(.menuBarFocused, .string("#FF0000"))
            model.commit(.menuBarFocused)
            assertEquals(text, "[menu-bar]\n# A new comment\ntheme = 'square'\n\n[menu-bar.colors]\nfocused = '#FF0000'\n\n[mode.main.binding]\n")
        }

        @Test func testFileBrokenOutsideOfTheWindowIsNotWritten() throws {
            let model = try model("[menu-bar]\ntheme = 'chips'\n[mode.main.binding]\n")
            // Half-way through an edit in the editor: not valid TOML, and then a config with an error
            for broken in ["[menu-bar\ntheme = 'chips'\n", "[menu-bar]\ntheme = 'chips'\nunknown-key = 1\n[mode.main.binding]\n"] {
                try broken.write(to: file, atomically: true, encoding: .utf8)
                model.set(.menuBarShowMode, .bool(true))
                assertEquals(text, broken)
                assertNotNil(model.errorMessage)
            }
        }

        @Test func testPreviewAndCommit() throws {
            let original = "[borders]\nwidth = 4\n"
            // The [borders] table isn't a part of the config yet: only the preview can be tested
            let model = try model(original)
            model.preview(.bordersWidth, .int(9))
            assertEquals(model.int(.bordersWidth), 9)
            assertEquals(text, original)
            model.preview(.bordersWidth, .int(4))
            assertEquals(model.int(.bordersWidth), 4)

            let menuBar = try self.model("[mode.main.binding]\n")
            menuBar.preview(.menuBarFocused, .string("#FF0000"))
            assertEquals(menuBar.menuBarConfig.colors.focused, .rgba(Rgba(red: 1, green: 0, blue: 0)))
            assertEquals(menuBar.isSet(.menuBarFocused), true)
            assertEquals(text, "[mode.main.binding]\n")
            menuBar.commit(.menuBarFocused)
            assertEquals(text, "[mode.main.binding]\n\n[menu-bar.colors]\nfocused = '#FF0000'\n")
            // Nothing left to commit
            menuBar.commit(.menuBarFocused)
            assertEquals(text, "[mode.main.binding]\n\n[menu-bar.colors]\nfocused = '#FF0000'\n")
        }

        @Test func testSetDebounced() async throws {
            let model = try model("[mode.main.binding]\n")
            model.setDebounced(.menuBarFocused, .string("#FF0000"))
            model.setDebounced(.menuBarFocused, .string("#00FF00"))
            // Shown right away, written later, and only the last value
            assertEquals(model.string(.menuBarFocused), "#00FF00")
            assertEquals(text, "[mode.main.binding]\n")
            try await Task.sleep(for: .milliseconds(700))
            assertEquals(text, "[mode.main.binding]\n\n[menu-bar.colors]\nfocused = '#00FF00'\n")
            // The value it already has isn't a change
            model.setDebounced(.menuBarFocused, .string("#00FF00"))
            assertEquals(model.string(.menuBarFocused), "#00FF00")
        }

        @Test func testKeysDefinedByHand() throws {
            let original = "menu-bar.theme = 'square'\ntiling = { new-window-placement = 'dwindle' }\n[mode.main.binding]\n"
            let model = try model(original)
            assertEquals(model.unavailableReason, nil)
            // Shown, but not editable
            assertEquals(model.menuBarTheme, .square)
            assertEquals(model.disabledReason(.menuBarTheme), "Defined by hand in the config file")
            assertEquals(model.disabledReason(.menuBarShowMode), "Defined by hand in the config file")
            assertEquals(model.disabledReason(.newWindowPlacement), "Defined by hand in the config file")
            assertEquals(model.disabledReason(.startAtLogin), nil)
            // Even if something tries
            model.set(.menuBarTheme, .string("chips"))
            assertEquals(text, original)
            assertEquals(model.errorMessage, "Defined by hand in the config file")
        }

        @Test func testConfigWithErrors() throws {
            let original = "unknown = 1\n[mode.main.binding]\n"
            let model = try model(original)
            assertEquals(model.unavailableReason, "inlay.toml has errors. Fix them to change the settings from here.")
            assertEquals(model.disabledReason(.menuBarTheme), model.unavailableReason)
            model.set(.menuBarTheme, .string("square"))
            assertEquals(text, original)

            let broken = try self.model("[menu-bar\n")
            assertEquals(broken.unavailableReason, "inlay.toml has errors. Fix them to change the settings from here.")
            assertEquals(broken.menuBarConfig, MenuBarConfig())
        }

        @Test func testNeedsAccessibility() throws {
            ServerState.shared.axPermissionStatus = .waiting
            defer { ServerState.shared.axPermissionStatus = .granted }
            let model = try model("[mode.main.binding]\n")
            assertEquals(model.isAccessibilityGranted, false)
            assertEquals(model.unavailableReason, "Grant the accessibility permission to change the settings.")
            model.set(.menuBarTheme, .string("square"))
            assertEquals(text, "[mode.main.binding]\n")
        }

        @Test func testInvalidValueIsNotWritten() throws {
            let model = try model("[mode.main.binding]\n")
            model.set(.menuBarTheme, .string("pills"))
            assertEquals(text, "[mode.main.binding]\n")
            assertEquals(model.errorMessage?.contains("Can't parse menu bar theme 'pills'"), true)
            assertEquals(model.menuBarTheme, .chips)
            // The next change that works clears the error
            model.set(.menuBarTheme, .string("minimal"))
            assertEquals(model.errorMessage, nil)
        }

        /// Draws every tab of the settings window off screen. With INLAY_RENDER_DIR, the tabs are also written there as PNG files
        @Test func testRenderTabs() throws {
            _ = NSApplication.shared
            let model = try model(
                """
                [menu-bar]
                theme = 'chips'
                show-mode = true
                [menu-bar.colors]
                focused = '#D19A66'
                [borders]
                glow = true
                [borders.mode-colors]
                resize = '#30D158'
                [mode.main.binding]
                [mode.resize.binding]
                [mode.service.binding]

                """,
            )
            ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now.addingTimeInterval(-120), url: file, errorCount: 0, warningCount: 0, isApplied: true)
            defer { ServerState.shared.lastConfigLoad = nil }
            model.refresh()
            let tabs: [(String, AnyView)] = [
                ("general", AnyView(GeneralSettingsView(model: model))),
                ("menu-bar", AnyView(MenuBarSettingsView(model: model))),
                ("borders", AnyView(BordersSettingsView(model: model))),
            ]
            for (name, view) in tabs {
                let hosting = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = hosting
                let size = hosting.fittingSize
                assertEquals(size.width, 600, additionalMsg: name)
                assertEquals(size.height > 200, true, additionalMsg: name)
                window.setContentSize(size)
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: .now.addingTimeInterval(0.2))
                let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                if let directory = ProcessInfo.processInfo.environment["INLAY_RENDER_DIR"] {
                    try bitmap.representation(using: .png, properties: [:])?.write(to: URL(filePath: directory).appending(path: "settings-\(name).png"))
                }
            }
        }
    }
}

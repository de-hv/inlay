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
            assertEquals(model.string(.menuBarTheme), "chips")
            assertEquals(model.bool(.menuBarEnabled), true)
            assertEquals(model.color(.menuBarAccent), .systemAccent)
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
                theme = 'chips-icons'
                show-mode = true
                [menu-bar.colors]
                focused = '#D19A66'
                [mode.main.binding]

                """,
            )
            assertEquals(model.bool(.startAtLogin), true)
            assertEquals(model.isSet(.menuBarTheme), true)
            assertEquals(model.isSet(.menuBarShowAppIcons), false)
            let expected = MenuBarConfig(theme: .chipsIcons, showMode: true, colors: MenuBarColors(focused: .rgba(Rgba(hex: "#D19A66").orDie())))
            assertEquals(model.menuBarConfig, expected)
            // The theme decides about the icons
            assertEquals(model.menuBarConfig.effectiveShowAppIcons, true)
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

        @Test func testSetThemeLetsTheThemeDecideAboutIcons() throws {
            let model = try model("[menu-bar]\ntheme = 'chips'\nshow-app-icons = false\n[mode.main.binding]\n")
            model.setTheme(.chipsIcons)
            assertEquals(text, "[menu-bar]\ntheme = 'chips-icons'\n[mode.main.binding]\n")
            assertEquals(model.menuBarConfig.effectiveShowAppIcons, true)
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
                [mode.main.binding]

                """,
            )
            ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now.addingTimeInterval(-120), url: file, errorCount: 0, warningCount: 0, isApplied: true)
            defer { ServerState.shared.lastConfigLoad = nil }
            model.refresh()
            let icons = AppIconCache()
            let tabs: [(String, AnyView)] = [
                ("general", AnyView(GeneralSettingsView(model: model))),
                ("menu-bar", AnyView(MenuBarSettingsView(model: model, icons: icons))),
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

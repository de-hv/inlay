@testable import AppBundle
import Common
import Foundation
import HotKey
import Testing

extension InlayTests {
    /// Editing the config file by hand reloads the config ('auto-reload-config'), which is what brings the new values
    /// to the settings window, the menu bar item and the borders. See: ConfigAutoReload, FileWatcher
    @Suite @MainActor final class ConfigAutoReloadTest {
        private let directory: URL
        private var events = 0

        init() throws {
            setUpWorkspacesForTests()
            // The real path: /var is a link to /private/var, and a link in the way would be watched as one more
            directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "inlay-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.removeItem(at: directory)
        }

        private func watch(_ url: URL) -> FileWatcher {
            FileWatcher(url: url) { [weak self] in self?.events += 1 }
        }

        /// Waits until the watcher has reported something, and arms it again, like ConfigAutoReload does
        private func expectEvent(_ watcher: FileWatcher, _ what: String, sourceLocation: SourceLocation = #_sourceLocation) async throws {
            for _ in 0 ..< 200 where events == 0 { try await Task.sleep(for: .milliseconds(10)) }
            assertEquals(events > 0, true, additionalMsg: what, sourceLocation: sourceLocation)
            try await Task.sleep(for: .milliseconds(50)) // The rest of the events of the same save
            watcher.arm()
            events = 0
        }

        // MARK: - What counts as a change

        @Test func testNeedsReload() {
            assertEquals(ConfigAutoReload.needsReload(loadedText: "a = 1\n", currentText: "a = 2\n"), true)
            // Another file of the directory was saved, or the same contents were saved again,
            // or it is the file that the settings window has just written and loaded
            assertEquals(ConfigAutoReload.needsReload(loadedText: "a = 1\n", currentText: "a = 1\n"), false)
            // The file is being replaced, or it is gone: the config in effect stays
            assertEquals(ConfigAutoReload.needsReload(loadedText: "a = 1\n", currentText: nil), false)
            // The file couldn't be read when Inlay started, and now it can
            assertEquals(ConfigAutoReload.needsReload(loadedText: nil, currentText: "a = 1\n"), true)
            assertEquals(ConfigAutoReload.needsReload(loadedText: nil, currentText: nil), false)
        }

        /// No reload loop: what the settings window writes is what the watcher finds, so it doesn't reload again
        @Test func testTheSettingsWindowWritesAndTheWatcherAgrees() throws {
            let file = directory.appending(path: "inlay.toml")
            let before = "[menu-bar]\ntheme = 'chips'\n[mode.main.binding]\n"
            try before.write(to: file, atomically: true, encoding: .utf8)
            let target = ConfigEditor.Target(url: file, text: before, exists: true)
            let edit = ConfigEdit(path: TomlKeyPath(["menu-bar"], "theme"), value: .string("square"))
            assertEquals(ConfigEditor.apply([edit], to: target).errorOrNil, nil)
            let written = try String(contentsOf: file, encoding: .utf8)
            assertEquals(written, "[menu-bar]\ntheme = 'square'\n[mode.main.binding]\n")
            // ConfigEditor told ConfigAutoReload what it wrote
            config.autoReloadConfig = false
            ConfigAutoReload.sync(url: file, text: before)
            assertEquals(ConfigAutoReload.needsReload(currentText: written), true)
            ConfigAutoReload.didWrite(written)
            assertEquals(ConfigAutoReload.needsReload(currentText: written), false)
            // And a change made by hand afterwards is still a change
            assertEquals(ConfigAutoReload.needsReload(currentText: written + "# by hand\n"), true)
        }

        // MARK: - The watcher, with real files

        @Test func testWriteInPlace() async throws {
            let file = directory.appending(path: "inlay.toml")
            try "a = 1\n".write(to: file, atomically: false, encoding: .utf8)
            let watcher = watch(file)
            try "a = 2\n".write(to: file, atomically: false, encoding: .utf8)
            try await expectEvent(watcher, "first write")
            try "a = 3\n".write(to: file, atomically: false, encoding: .utf8)
            try await expectEvent(watcher, "second write")
        }

        /// The save of most editors: a new file is written and renamed over the old one
        @Test func testAtomicSave_severalTimes() async throws {
            let file = directory.appending(path: "inlay.toml")
            try "a = 1\n".write(to: file, atomically: true, encoding: .utf8)
            let watcher = watch(file)
            for value in 2 ... 4 {
                try "a = \(value)\n".write(to: file, atomically: true, encoding: .utf8)
                try await expectEvent(watcher, "save \(value)")
            }
        }

        /// The watcher isn't armed again between two saves: a config with errors isn't applied, but the next save is seen
        @Test func testAtomicSave_seenWithoutArmingAgain() async throws {
            let file = directory.appending(path: "inlay.toml")
            try "a = 1\n".write(to: file, atomically: true, encoding: .utf8)
            let watcher = watch(file)
            try "a = [\n".write(to: file, atomically: true, encoding: .utf8)
            for _ in 0 ..< 200 where events == 0 { try await Task.sleep(for: .milliseconds(10)) }
            assertEquals(events > 0, true)
            try await Task.sleep(for: .milliseconds(50))
            events = 0
            try "a = 2\n".write(to: file, atomically: true, encoding: .utf8)
            try await expectEvent(watcher, "the save after the broken one")
        }

        /// ~/.config/inlay/inlay.toml -> ~/.dotfiles/inlay/inlay.toml, edited in the dotfiles directory
        @Test func testSymlinkToAnotherDirectory() async throws {
            let dotfiles = directory.appending(path: "dotfiles")
            let configDirectory = directory.appending(path: "config")
            try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
            let real = dotfiles.appending(path: "mine.toml")
            let link = configDirectory.appending(path: "inlay.toml")
            try "a = 1\n".write(to: real, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let watcher = watch(link)

            try "a = 2\n".write(to: real, atomically: false, encoding: .utf8)
            try await expectEvent(watcher, "write in place")
            try "a = 3\n".write(to: real, atomically: true, encoding: .utf8)
            try await expectEvent(watcher, "atomic save")
            try "a = 4\n".write(to: real, atomically: true, encoding: .utf8)
            try await expectEvent(watcher, "atomic save, again")
            assertEquals(try String(contentsOf: link, encoding: .utf8), "a = 4\n")

            // The link is pointed to another file
            let other = dotfiles.appending(path: "other.toml")
            try "a = 5\n".write(to: other, atomically: true, encoding: .utf8)
            try await expectEvent(watcher, "a new file next to the config") // Reported, and needsReload says no
            try FileManager.default.removeItem(at: link)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: other)
            try await expectEvent(watcher, "the link changed")
            try "a = 6\n".write(to: other, atomically: false, encoding: .utf8)
            try await expectEvent(watcher, "the new target")
        }

        /// The file is deleted and created again, and a file that doesn't exist yet is created
        @Test func testFileThatAppears() async throws {
            let file = directory.appending(path: "inlay.toml")
            let watcher = watch(file)
            try "a = 1\n".write(to: file, atomically: false, encoding: .utf8)
            try await expectEvent(watcher, "created")
            try FileManager.default.removeItem(at: file)
            try await expectEvent(watcher, "deleted")
            try "a = 2\n".write(to: file, atomically: false, encoding: .utf8)
            try await expectEvent(watcher, "created again")
        }

        @Test func testCancel() async throws {
            let file = directory.appending(path: "inlay.toml")
            try "a = 1\n".write(to: file, atomically: false, encoding: .utf8)
            let watcher = watch(file)
            watcher.cancel()
            try "a = 2\n".write(to: file, atomically: true, encoding: .utf8)
            try await Task.sleep(for: .milliseconds(300))
            assertEquals(events, 0)
        }

        // MARK: - Key bindings that macOS refuses

        @Test func testHotkeyRegistrationWarnings() {
            let modes = parseConfig(
                """
                [mode.main.binding]
                    cmd-alt-ctrl-left = 'focus left'
                    alt-b = 'focus right'
                    alt-a = 'focus up'
                [mode.resize.binding]
                    esc = 'mode main'
                """,
            ).config.modes
            assertEquals(hotkeyRegistrationWarnings(modes) { _ in true }, [])
            let refused = hotkeyRegistrationWarnings(modes) { $0.keyCode != .leftArrow }
            assertEquals(
                refused.map { $0.description(.warning) },
                ["[WARNING] mode.main.binding.cmd-alt-ctrl-left: macOS refused to register this key binding, so it doesn't work. Another app may have taken the same keys"],
            )
            // Sorted by mode and by key
            assertEquals(
                hotkeyRegistrationWarnings(modes) { _ in false }.map(\.backtrace.description),
                ["mode.main.binding.alt-a", "mode.main.binding.alt-b", "mode.main.binding.cmd-alt-ctrl-left", "mode.resize.binding.esc"],
            )
        }

        /// The menu of the menu bar item says so, with the errors first
        @Test func testConfigProblemsMenuItem() {
            func load(_ errors: Int, _ warnings: Int) -> ConfigLoadStatus {
                ConfigLoadStatus(date: .now, url: configUrl, errorCount: errors, warningCount: warnings, isApplied: true)
            }
            assertEquals(Strings.Menu.configProblems(nil), nil)
            assertEquals(Strings.Menu.configProblems(load(0, 0)), nil)
            assertEquals(Strings.Menu.configProblems(load(0, 2)), "Config contains warnings…")
            assertEquals(Strings.Menu.configProblems(load(1, 0)), "Config contains errors…")
            assertEquals(Strings.Menu.configProblems(load(1, 2)), "Config contains errors…")
        }
    }
}

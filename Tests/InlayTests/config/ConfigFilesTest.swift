@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor final class ConfigFilesTest {
        private let directory: URL

        init() throws {
            setUpWorkspacesForTests()
            directory = FileManager.default.temporaryDirectory.appending(path: "inlay-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.removeItem(at: directory)
        }

        private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

        private func isSymlink(_ url: URL) -> Bool {
            (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
        }

        // MARK: - AtomicFileWriter

        @Test func testWriteNewFileAndDirectories() throws {
            let file = directory.appending(path: "a/b/inlay.toml")
            try AtomicFileWriter.write("x = 1\n", to: file)
            assertEquals(read(file), "x = 1\n")
            try AtomicFileWriter.write("x = 2\n", to: file)
            assertEquals(read(file), "x = 2\n")
            // No temporary files are left behind
            assertEquals(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path), ["inlay.toml"])
        }

        @Test func testWriteKeepsPermissions() throws {
            let file = directory.appending(path: "inlay.toml")
            try AtomicFileWriter.write("x = 1\n", to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try AtomicFileWriter.write("x = 2\n", to: file)
            let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
            assertEquals(permissions, 0o600)
        }

        @Test func testWriteThroughSymlink() throws {
            // The config is a link to a file of a dotfiles repo
            let dotfiles = directory.appending(path: "dotfiles")
            try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
            let real = dotfiles.appending(path: "inlay.toml")
            try "x = 1\n".write(to: real, atomically: true, encoding: .utf8)
            let link = directory.appending(path: "inlay.toml")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            try AtomicFileWriter.write("x = 2\n", to: link)
            assertEquals(read(real), "x = 2\n")
            assertEquals(isSymlink(link), true)
            assertEquals(isSymlink(real), false)
            assertEquals(read(link), "x = 2\n")
            assertEquals(try FileManager.default.contentsOfDirectory(atPath: dotfiles.path), ["inlay.toml"])
        }

        /// ~/.config/inlay -> ~/.dotfiles/inlay, the way install.sh links a config folder: `config --use <file>`
        /// writes the file inside of the folder of the user, and the link of the folder stays
        @Test func testWriteInALinkedFolder() throws {
            let dotfiles = directory.appending(path: "dotfiles/inlay")
            try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
            let real = dotfiles.appending(path: "inlay.toml")
            let before = "# Mine\n[menu-bar]\ntheme = 'chips'\n[mode.main.binding]\n"
            try before.write(to: real, atomically: true, encoding: .utf8)
            let folder = directory.appending(path: "inlay")
            try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: dotfiles)
            let config = folder.appending(path: "inlay.toml")

            try AtomicFileWriter.write("# Mine\n[menu-bar]\ntheme = 'square'\n[mode.main.binding]\n", to: config)
            assertEquals(read(real), "# Mine\n[menu-bar]\ntheme = 'square'\n[mode.main.binding]\n")
            assertEquals(read(config), read(real))
            assertEquals(isSymlink(folder), true)
            assertEquals(isSymlink(config), false)
            assertEquals(isSymlink(real), false)
            // No temporary file is left in the folder of the user
            assertEquals(try FileManager.default.contentsOfDirectory(atPath: dotfiles.path), ["inlay.toml"])
        }

        @Test func testWriteThroughRelativeSymlinkChain() throws {
            let dotfiles = directory.appending(path: "dotfiles/config")
            try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
            let real = dotfiles.appending(path: "real.toml")
            try "x = 1\n".write(to: real, atomically: true, encoding: .utf8)
            // config/inlay.toml -> ../middle.toml -> dotfiles/config/real.toml
            let config = directory.appending(path: "config")
            try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
            let middle = directory.appending(path: "middle.toml")
            try FileManager.default.createSymbolicLink(atPath: middle.path, withDestinationPath: "dotfiles/config/real.toml")
            let link = config.appending(path: "inlay.toml")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../middle.toml")

            assertEquals(try AtomicFileWriter.resolveSymlinks(link).path, real.standardizedFileURL.path)
            try AtomicFileWriter.write("x = 2\n", to: link)
            assertEquals(read(real), "x = 2\n")
            assertEquals(isSymlink(link), true)
            assertEquals(isSymlink(middle), true)
            assertEquals(isSymlink(real), false)
        }

        @Test func testWriteThroughDanglingSymlink() throws {
            let link = directory.appending(path: "inlay.toml")
            try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing/real.toml")
            try AtomicFileWriter.write("x = 1\n", to: link)
            assertEquals(isSymlink(link), true)
            assertEquals(read(directory.appending(path: "missing/real.toml")), "x = 1\n")
        }

        @Test func testSymlinkLoop() throws {
            let a = directory.appending(path: "a.toml")
            let b = directory.appending(path: "b.toml")
            try FileManager.default.createSymbolicLink(atPath: a.path, withDestinationPath: "b.toml")
            try FileManager.default.createSymbolicLink(atPath: b.path, withDestinationPath: "a.toml")
            do {
                try AtomicFileWriter.write("x = 1\n", to: a)
                Issue.record("Must fail")
            } catch {
                assertEquals(error, .tooManySymlinks)
            }
        }

        // MARK: - ConfigFiles

        /// Nothing is changed: these fail before anything is written
        @Test func testUseFailsWithoutWriting() throws {
            let missing = directory.appending(path: "missing.toml")
            assertEquals(ConfigFiles.use(missing).errorOrNil, .notFound(missing))
            let broken = directory.appending(path: "broken.toml")
            try "[menu-bar]\ntheme = 'bubbles'\n".write(to: broken, atomically: true, encoding: .utf8)
            assertEquals(ConfigFiles.use(broken).okOrNil, nil)
            if case .invalidConfig(let errors) = ConfigFiles.use(broken).errorOrNil {
                assertEquals(errors.count, 1)
            } else if case .ambiguousConfig = ConfigFiles.use(broken).errorOrNil {
                // The machine that runs the tests has two configs: nothing to check here
            } else {
                Issue.record("A config with errors must not be used")
            }
        }

        @Test func testExportAddsTheMissingKeys() {
            let shipped = "start-at-login = true\n[menu-bar]\n    theme = 'liquid'\n    show-mode = true\n[mode.main.binding]\n    alt-h = 'focus left'\n"
            let text = "# Mine\n[menu-bar]\n    theme = 'capsule'\n"
            let exported = ConfigFiles.exportText(text, shipped: shipped, date: Date(timeIntervalSince1970: 0))
            let config = parseConfig(exported)
            assertEquals(config.errors, [])
            // The value of the user stays, the missing keys are added, and the key bindings are the user's own
            assertEquals(config.config.menuBar.theme, .capsule)
            assertEquals(config.config.menuBar.showMode, true)
            assertEquals(config.config.startAtLogin, true)
            assertEquals(exported.contains("# Mine\n"), true)
            assertEquals(exported.contains("alt-h"), false)
            assertEquals(exported.hasPrefix("# Exported from"), true)
        }

        @Test func testTildePath() {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            assertEquals((home + "/.config/inlay").tildePath, "~/.config/inlay")
            assertEquals("/tmp/inlay".tildePath, "/tmp/inlay")
        }
    }
}

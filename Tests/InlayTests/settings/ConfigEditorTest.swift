@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor final class ConfigEditorTest {
        private let directory: URL
        private let theme = ConfigEdit(path: TomlKeyPath(["menu-bar"], "theme"), value: .string("square"))

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

        // MARK: - ConfigEditor

        @Test func testPatchValidatesTheConfig() {
            let text = "[menu-bar]\ntheme = 'chips'\n"
            assertEquals(ConfigEditor.patch(text, [theme]).okOrNil, "[menu-bar]\ntheme = 'square'\n")
            // A value the config doesn't accept is never written
            let pills = ConfigEdit(path: theme.path, value: .string("pills"))
            assertEquals(
                ConfigEditor.patch(text, [pills]).errorOrNil,
                .invalidConfig("[ERROR] menu-bar.theme: Can't parse menu bar theme 'pills'. Possible values: (chips|chips-icons|square|minimal)"),
            )
            let color = ConfigEdit(path: TomlKeyPath(["menu-bar", "colors"], "focused"), value: .string("#12345"))
            assertEquals(ConfigEditor.patch(text, [color]).okOrNil, nil)
            // A key the config doesn't know
            let unknown = ConfigEdit(path: TomlKeyPath(["menu-bar"], "them"), value: .string("chips"))
            assertEquals(ConfigEditor.patch(text, [unknown]).errorOrNil, .invalidConfig("[ERROR] menu-bar.them: Unknown key"))
            // A config that already has errors isn't edited
            assertEquals(ConfigEditor.patch("unknown-key = 1\n" + text, [theme]).errorOrNil, .invalidConfig("[ERROR] unknown-key: Unknown top-level key"))
            assertEquals(ConfigEditor.patch("menu-bar.theme = 'chips'\n", [theme]).errorOrNil, .patch(.unsupported(.dottedKey)))
        }

        @Test func testPatchSeveralEdits() {
            let text = "[menu-bar]\ntheme = 'chips'\nshow-app-icons = false\n"
            let edits = [theme, ConfigEdit(path: TomlKeyPath(["menu-bar"], "show-app-icons"), value: nil)]
            assertEquals(ConfigEditor.patch(text, edits).okOrNil, "[menu-bar]\ntheme = 'square'\n")
            // All or nothing
            let bad = ConfigEdit(path: TomlKeyPath(["menu-bar"], "enabled"), value: .string("yes"))
            assertEquals(ConfigEditor.patch(text, [theme, bad]).okOrNil, nil)
        }

        @Test func testPatchTheBuiltInConfig() throws {
            let text = try String(contentsOf: defaultConfigUrl, encoding: .utf8)
            let patched = ConfigEditor.patch(text, [
                theme,
                ConfigEdit(path: TomlKeyPath(["menu-bar", "colors"], "focused"), value: .string("#D19A66")),
                ConfigEdit(path: TomlKeyPath(["tiling"], "new-window-placement"), value: .string("after-focused")),
                ConfigEdit(path: TomlKeyPath([], "start-at-login"), value: .bool(true)),
                ConfigEdit(path: TomlKeyPath(["menu-bar"], "show-app-icons"), value: .bool(true)),
            ]).okOrNil ?? ""
            let config = parseConfig(patched)
            assertEquals(config.errors, [])
            assertEquals(config.config.menuBar.theme, .square)
            assertEquals(config.config.menuBar.showAppIcons, true)
            assertEquals(config.config.menuBar.colors.focused, .rgba(Rgba(hex: "#D19A66").orDie()))
            assertEquals(config.config.tiling.newWindowPlacement, .afterFocused)
            assertEquals(config.config.startAtLogin, true)
            // The comments are still there, and nothing else has changed
            assertEquals(patched.split(separator: "\n").count, text.split(separator: "\n").count + 1)
            assertEquals(patched.contains("    # chips|chips-icons|square|minimal\n    theme = 'square'\n"), true)
            assertEquals(patched.contains("        focused = '#D19A66'\n"), true)
        }

        @Test func testApply() throws {
            let file = directory.appending(path: "inlay.toml")
            // The user has no config yet: the file is created from the built-in config
            let builtIn = "# The built-in config\n[menu-bar]\ntheme = 'chips'\n"
            assertEquals(ConfigEditor.apply([theme], to: .init(url: file, text: builtIn, exists: false)).errorOrNil, nil)
            assertEquals(read(file), "# The built-in config\n[menu-bar]\ntheme = 'square'\n")
            // Created even if the edit changes nothing
            let other = directory.appending(path: "other.toml")
            let noop = ConfigEdit(path: theme.path, value: .string("chips"))
            assertEquals(ConfigEditor.apply([noop], to: .init(url: other, text: builtIn, exists: false)).errorOrNil, nil)
            assertEquals(read(other), builtIn)

            // A failed edit doesn't touch the file
            let bad = ConfigEdit(path: theme.path, value: .string("pills"))
            assertEquals(ConfigEditor.apply([bad], to: .init(url: file, text: read(file) ?? "", exists: true)).okOrNil == nil, true)
            assertEquals(read(file), "# The built-in config\n[menu-bar]\ntheme = 'square'\n")
            assertEquals(ConfigEditor.apply([ConfigEdit(path: theme.path, value: nil)], to: .init(url: file, text: read(file) ?? "", exists: true)).errorOrNil, nil)
            assertEquals(read(file), "# The built-in config\n[menu-bar]\n")
        }
    }
}

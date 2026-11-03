@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// The config folder as a link to a folder of the user, for `inlay config --use`: the rules of install.sh
    @Suite struct ConfigFolderLinkTest {
        private let root: URL
        /// The config folder: ~/.config/inlay
        private let dir: URL
        /// A folder of the user: ~/.dotfiles/inlay
        private let dotfiles: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appending(path: "inlay-config-link-\(UUID().uuidString)")
            dir = root.appending(path: "config/inlay")
            dotfiles = root.appending(path: "dotfiles/inlay")
            try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        }

        private func write(_ text: String, _ url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

        private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

        /// A real config folder is renamed, not deleted, and the link takes its place
        @Test func testLinkARealFolder() throws {
            try write("mine", dir.appending(path: "inlay.lua"))
            try write("dotfiles", dotfiles.appending(path: "inlay.lua"))
            assertEquals(ConfigFolderLink.state(of: dir), .folder)

            let backup = try #require(try ConfigFolderLink.link(dir, to: dotfiles, writing: "unused", now: now))
            assertEquals(ConfigFolderLink.state(of: dir), .linked(dotfiles))
            assertEquals(read(dir.appending(path: "inlay.lua")), "dotfiles")
            assertEquals(read(backup.appending(path: "inlay.lua")), "mine")
            assertEquals(backup.lastPathComponent.hasPrefix("inlay.backup-"), true)
        }

        /// A folder without inlay.lua gets the config it is given
        @Test func testAFolderWithoutConfig() throws {
            assertEquals(ConfigFolderLink.hasConfig(dotfiles), false)
            assertNil(try ConfigFolderLink.link(dir, to: dotfiles, writing: "copied", now: now))
            assertEquals(read(dotfiles.appending(path: "inlay.lua")), "copied")
            assertEquals(read(dir.appending(path: "inlay.lua")), "copied")
        }

        /// Linking another folder only replaces the link: the folder it pointed to is not touched
        @Test func testLinkAnotherFolder() throws {
            try write("first", dotfiles.appending(path: "inlay.lua"))
            let other = root.appending(path: "other")
            try write("second", other.appending(path: "inlay.lua"))
            try ConfigFolderLink.link(dir, to: dotfiles, writing: nil, now: now)
            assertNil(try ConfigFolderLink.link(dir, to: other, writing: nil, now: now))
            assertEquals(ConfigFolderLink.state(of: dir), .linked(other))
            assertEquals(read(dotfiles.appending(path: "inlay.lua")), "first")
        }

        /// The folder, or the inlay.lua in it. Not another file, not the config folder itself
        @Test func testWhatCanBeLinked() throws {
            try write("dotfiles", dotfiles.appending(path: "inlay.lua"))
            try write("x", dotfiles.appending(path: "notes.txt"))
            assertEquals(ConfigFolderLink.folder(of: dotfiles, dir: dir), .success(dotfiles))
            assertEquals(ConfigFolderLink.folder(of: dotfiles.appending(path: "inlay.lua"), dir: dir), .success(dotfiles))
            assertEquals(ConfigFolderLink.folder(of: dotfiles.appending(path: "notes.txt"), dir: dir), .failure(.notAConfig(dotfiles.appending(path: "notes.txt"))))
            let missing = root.appending(path: "missing")
            assertEquals(ConfigFolderLink.folder(of: missing, dir: dir), .failure(.notAFolder(missing)))

            try write("mine", dir.appending(path: "inlay.lua"))
            assertEquals(ConfigFolderLink.folder(of: dir, dir: dir), .failure(.isTheConfigFolder))
            try FileManager.default.removeItem(at: dir)
            try ConfigFolderLink.link(dir, to: dotfiles, writing: nil, now: now)
            assertEquals(ConfigFolderLink.folder(of: dotfiles, dir: dir), .failure(.alreadyLinked(dotfiles)))
        }

        /// Unlinked, the config folder is a real folder with a copy of the config it pointed to, which isn't touched:
        /// inlay.lua and its modules, not the other files of the folder
        @Test func testUnlink() throws {
            try write("dotfiles", dotfiles.appending(path: "inlay.lua"))
            try write("binds", dotfiles.appending(path: "binds.lua"))
            try write("x", dotfiles.appending(path: "notes.txt"))
            try ConfigFolderLink.link(dir, to: dotfiles, writing: nil, now: now)
            try ConfigFolderLink.unlink(dir)
            assertEquals(ConfigFolderLink.state(of: dir), .folder)
            assertEquals(read(dir.appending(path: "inlay.lua")), "dotfiles")
            assertEquals(read(dir.appending(path: "binds.lua")), "binds")
            assertNil(read(dir.appending(path: "notes.txt")))
            try write("changed", dir.appending(path: "inlay.lua"))
            assertEquals(read(dotfiles.appending(path: "inlay.lua")), "dotfiles")
        }

        /// The name of a backup that is taken gets a number
        @Test func testBackupNames() throws {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let first = ConfigFolderLink.backupUrl(dir, now: now)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            assertEquals(ConfigFolderLink.backupUrl(dir, now: now).path, first.path + "-2")
        }
    }
}

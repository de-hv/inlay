@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// The config of the user at startup, for an app that wasn't installed with install.sh (Homebrew)
    @Suite struct UserConfigSetupTest {
        private let root: URL
        /// ~/.config/inlay/inlay.toml
        private let target: URL

        init() {
            root = FileManager.default.temporaryDirectory.appending(path: "inlay-user-config-\(UUID().uuidString)")
            target = root.appending(path: "config/inlay/inlay.toml")
        }

        private func write(_ text: String, _ url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }

        private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

        private func hash(_ text: String) -> String { UserConfigSetup.sha256(Data(text.utf8)) }

        private var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }

        /// Without a config, the built-in one is copied where the user edits it
        @Test func testNoConfig_isCreated() {
            let outcome = UserConfigSetup.run(found: .noCustomConfigExists, builtIn: "built-in", knownHashes: [], target: target, now: now)
            assertEquals(outcome, .created(target))
            assertEquals(read(target), "built-in")
        }

        /// A default config of a previous version, never edited, is replaced, and kept as a backup
        @Test func testUneditedOldDefault_isReplaced() throws {
            try write("old default", target)
            let outcome = UserConfigSetup.run(found: .file(target), builtIn: "built-in", knownHashes: [hash("old default")], target: target, now: now)
            guard case .updated(let url, let backup) = outcome else { Issue.record("\(outcome)"); return }
            assertEquals(url, target)
            assertEquals(read(target), "built-in")
            assertEquals(read(backup), "old default")
            assertEquals(backup.lastPathComponent.hasPrefix("inlay.toml.backup-"), true)
        }

        /// A config that isn't in the list is the user's own
        @Test func testEditedConfig_isKept() throws {
            try write("mine", target)
            let outcome = UserConfigSetup.run(found: .file(target), builtIn: "built-in", knownHashes: [hash("old default")], target: target, now: now)
            assertEquals(outcome, .unchanged)
            assertEquals(read(target), "mine")
        }

        /// The config folder linked to a dotfiles folder is never written, even without an inlay.toml
        @Test func testLinkedFolder_isNeverWritten() throws {
            let dotfiles = root.appending(path: "dotfiles/inlay")
            try write("old default", dotfiles.appending(path: "inlay.toml"))
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent().deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target.deletingLastPathComponent(), withDestinationURL: dotfiles)

            let known: Set = [hash("old default")]
            assertEquals(UserConfigSetup.run(found: .file(target), builtIn: "built-in", knownHashes: known, target: target, now: now), .unchanged)
            assertEquals(read(dotfiles.appending(path: "inlay.toml")), "old default")

            try FileManager.default.removeItem(at: dotfiles.appending(path: "inlay.toml"))
            assertEquals(UserConfigSetup.run(found: .noCustomConfigExists, builtIn: "built-in", knownHashes: known, target: target, now: now), .unchanged)
            assertNil(read(dotfiles.appending(path: "inlay.toml")))
        }

        /// A linked inlay.toml is the user's own too
        @Test func testLinkedFile_isNeverWritten() throws {
            let file = root.appending(path: "dotfiles/inlay.toml")
            try write("old default", file)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: file)
            let outcome = UserConfigSetup.run(found: .file(target), builtIn: "built-in", knownHashes: [hash("old default")], target: target, now: now)
            assertEquals(outcome, .unchanged)
            assertEquals(read(file), "old default")
        }

        /// ~/.inlay.toml is left alone
        @Test func testDotfileConfig_isKept() throws {
            let dotfile = root.appending(path: ".inlay.toml")
            try write("old default", dotfile)
            let outcome = UserConfigSetup.run(found: .file(dotfile), builtIn: "built-in", knownHashes: [hash("old default")], target: target, now: now)
            assertEquals(outcome, .unchanged)
            assertEquals(read(dotfile), "old default")
            assertNil(read(target))
        }

        /// The list that the app reads is the one of the repo, and it has the built-in config
        @Test func testKnownHashes_haveTheBuiltInConfig() throws {
            let hashes = UserConfigSetup.knownDefaultConfigHashes(projectRoot.appending(path: "scripts/default-config-hashes.txt"))
            assertEquals(hashes.contains(UserConfigSetup.sha256(try Data(contentsOf: defaultConfigUrl))), true)
            assertEquals(hashes.allSatisfy { $0.count == 64 }, true)
        }
    }
}

@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// What install.sh and 'inlay uninstall' rely on: 'Inlay --check-config', and finding the files that ship with Inlay
    @Suite @MainActor final class CheckConfigTest {
        private let directory: URL

        init() throws {
            setUpWorkspacesForTests()
            directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "inlay-tests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        deinit {
            _ = try? FileManager.default.removeItem(at: directory)
        }

        private func file(_ name: String, _ text: String) throws -> URL {
            let url = directory.appending(path: name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        @Test func testBuiltInConfig() {
            let url = projectRoot.appending(path: "inlay.toml")
            let report = checkConfigFile(url)
            assertEquals(report.isOk, true)
            assertEquals(report.text, "'\(url.path)' has no errors or warnings")
        }

        @Test func testWarningsAreNotErrors() throws {
            let url = try file("warnings.toml", "config-version = 2\naccordion-padding = 30\n[mode.main.binding]\n")
            let report = checkConfigFile(url)
            assertEquals(report.isOk, true)
            assertEquals(
                report.text,
                """
                '\(url.path)': 0 error(s), 1 warning(s)
                [WARNING] accordion-padding: Inlay has no accordion layout: 'accordion-padding' is ignored. Please drop it from the config
                """,
            )
        }

        @Test func testErrors() throws {
            let url = try file("errors.toml", "config-version = 2\nnope = 1\n[borders]\nwidth = 99\n[mode.main.binding]\n")
            let report = checkConfigFile(url)
            assertEquals(report.isOk, false)
            assertEquals(
                report.text,
                """
                '\(url.path)': 2 error(s), 0 warning(s)
                [ERROR] borders.width: width must be in [1, 20] range
                [ERROR] nope: Unknown top-level key
                """,
            )
        }

        /// The config is a symbolic link to a file of the user, like the one that install.sh offers to create
        @Test func testSymlinkAndMissingFile() throws {
            let real = try file("mine.toml", "config-version = 2\n[mode.main.binding]\n")
            let link = directory.appending(path: "inlay.toml")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            assertEquals(checkConfigFile(link).isOk, true)
            try FileManager.default.removeItem(at: real)
            assertEquals(checkConfigFile(link).isOk, false)
            assertEquals(checkConfigFile(link).text, "Can't read '\(link.path)' as a UTF-8 text file")
        }

        // MARK: - The files that ship with Inlay

        @Test func testAppBundleOfExecutable() throws {
            let app = directory.appending(path: "Applications/Inlay.app")
            let cli = app.appending(path: "Contents/Resources/bin/inlay")
            try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: cli)
            assertEquals(appBundle(ofExecutable: cli.path)?.path, app.path)
            assertEquals(appBundle(ofExecutable: app.appending(path: "Contents/MacOS/Inlay").path)?.path, app.path)
            // The CLI is run through the link that install.sh creates in the PATH
            let link = directory.appending(path: "bin/inlay")
            try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cli)
            assertEquals(appBundle(ofExecutable: link.path)?.path, app.path)
            assertEquals(appBundle(ofExecutable: directory.appending(path: "bin/other").path), nil)
        }

        @Test func testShippedFile() throws {
            let app = directory.appending(path: "Inlay.app")
            let cli = app.appending(path: "Contents/Resources/bin/inlay")
            let script = app.appending(path: "Contents/Resources/scripts/uninstall.sh")
            for url in [cli, script] {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data().write(to: url)
            }
            // The file of the bundle wins over the one of the repo
            assertEquals(shippedFile(inResources: "scripts/uninstall.sh", inRepo: "scripts/uninstall.sh", executable: cli.path)?.path, script.path)
            // A binary that isn't in a bundle, and a bundle without the file: the file of the repo
            let repoScript = projectRoot.appending(path: "scripts/uninstall.sh").path
            assertEquals(shippedFile(inResources: "scripts/uninstall.sh", inRepo: "scripts/uninstall.sh", executable: "/usr/local/bin/inlay")?.path, repoScript)
            assertEquals(shippedFile(inResources: "scripts/lib.sh", inRepo: "scripts/lib.sh", executable: cli.path)?.path, projectRoot.appending(path: "scripts/lib.sh").path)
            assertEquals(shippedFile(inResources: "nope", inRepo: "nope", executable: cli.path), nil)
            // What the app and the CLI ship with
            for (inResources, inRepo) in [("config-reference.toml", "docs/config-reference.toml"), ("inlay.toml", "inlay.toml")] {
                assertEquals(shippedFile(inResources: inResources, inRepo: inRepo, executable: "/nowhere/inlay") != nil, true, additionalMsg: inRepo)
            }
        }
    }
}

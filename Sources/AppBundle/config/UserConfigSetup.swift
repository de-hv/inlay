import CryptoKit
import Foundation

/// The config of the user, ready before Inlay reads it at startup. scripts/install.sh does the same, but an app
/// installed in another way (Homebrew) never runs it:
/// - without a config, ~/.config/inlay/inlay.toml is created with the built-in config, for the user to edit or to
///   replace with `inlay config --use`;
/// - a config that is a default config of a previous version, never edited, is replaced by the built-in one, and
///   kept next to it as inlay.toml.backup-<date>.
/// A config reached through a symbolic link (a dotfiles folder) is the user's own: it is never written
enum UserConfigSetup {
    enum Outcome: Equatable {
        case created(URL)
        case updated(URL, backup: URL)
        case unchanged
    }

    @MainActor
    static func run() -> Outcome {
        if serverArgs.configLocation != nil || serverArgs.isReadOnly { return .unchanged }
        guard let builtIn = try? String(contentsOf: defaultConfigUrl, encoding: .utf8) else { return .unchanged }
        return run(found: findCustomConfigUrl(), builtIn: builtIn, knownHashes: knownDefaultConfigHashes())
    }

    static func run(found: ConfigFile, builtIn: String, knownHashes: Set<String>, target: URL = newUserConfigUrl, now: Date = .now) -> Outcome {
        let folder = target.deletingLastPathComponent()
        if case .linked = ConfigFolderLink.state(of: folder) { return .unchanged }
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: target.path)) != nil { return .unchanged }
        switch found {
            case .noCustomConfigExists:
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try Data(builtIn.utf8).write(to: target, options: .withoutOverwriting)
                } catch {
                    return .unchanged
                }
                return .created(target)
            case .file(let url):
                guard url.standardizedFileURL.path == target.standardizedFileURL.path,
                      let data = try? Data(contentsOf: target),
                      data != Data(builtIn.utf8),
                      knownHashes.contains(sha256(data))
                else { return .unchanged }
                let backup = ConfigFolderLink.backupUrl(target, now: now)
                do {
                    try data.write(to: backup, options: .withoutOverwriting)
                    try AtomicFileWriter.write(builtIn, to: target)
                } catch {
                    return .unchanged
                }
                return .updated(target, backup: backup)
            case .ambiguousConfigError:
                return .unchanged
        }
    }

    /// The SHA-256 of every default config that Inlay has shipped: scripts/default-config-hashes.txt, which
    /// scripts/build-app.sh copies into the app
    static func knownDefaultConfigHashes(_ list: URL? = defaultConfigHashesUrl) -> Set<String> {
        guard let list, let text = try? String(contentsOf: list, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").filter { !$0.hasPrefix("#") }.compactMap { $0.split(separator: " ").first.map(String.init) })
    }

    private static var defaultConfigHashesUrl: URL? {
        Bundle.main.url(forResource: "default-config-hashes", withExtension: "txt")
            // Debug builds that are not app bundles
            ?? defaultConfigUrl.deletingLastPathComponent().appending(path: "scripts/default-config-hashes.txt")
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

import Common
import Foundation

/// The config folder (~/.config/inlay) as a symbolic link to a folder of the user, a dotfiles repo for example: the
/// question that scripts/install.sh asks, for `inlay config --use <folder>`, with the same rules. Inlay reads the
/// inlay.toml of that folder; nothing else of it is touched. A real config folder is never deleted (it is renamed),
/// and the folder that a link points to is never written, but for the inlay.toml it is given when it has none
enum ConfigFolderLink {
    /// ${XDG_CONFIG_HOME}/inlay, ~/.config/inlay by default: the folder of the config that Inlay creates
    static var configFolder: URL { newUserConfigUrl.deletingLastPathComponent() }

    enum State: Equatable {
        /// There is no config folder
        case none
        /// A real folder
        case folder
        /// A link to a folder of the user
        case linked(URL)
    }

    enum LinkError: Error, Equatable {
        /// The user picked a file that isn't an inlay.toml
        case notAConfig(URL)
        case notAFolder(URL)
        /// The folder is the config folder itself
        case isTheConfigFolder
        /// The config folder is already a link to the folder
        case alreadyLinked(URL)
        case failed(String)
    }

    static func state(of dir: URL = configFolder) -> State {
        if let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: dir.path) {
            return .linked(plain(URL(filePath: destination, relativeTo: dir.deletingLastPathComponent())))
        }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory) && isDirectory.boolValue ? .folder : .none
    }

    /// The folder to link, from what the user picked: a folder, or the inlay.toml in it. Fails, saying why, if the
    /// config folder can't be linked to it
    static func folder(of picked: URL, dir: URL = configFolder) -> Result<URL, LinkError> {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: picked.path, isDirectory: &isDirectory)
        let folder: URL
        switch (exists, isDirectory.boolValue) {
            case (true, true): folder = plain(picked)
            case (true, false):
                guard picked.lastPathComponent == configFileName else { return .failure(.notAConfig(picked)) }
                folder = plain(picked.deletingLastPathComponent())
            case (false, _): return .failure(.notAFolder(picked))
        }
        if folder.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path {
            if case .linked = state(of: dir) { return .failure(.alreadyLinked(folder)) }
            return .failure(.isTheConfigFolder)
        }
        return .success(folder)
    }

    /// The path without '..' nor a slash at the end: the same folder is the same URL
    private static func plain(_ url: URL) -> URL {
        URL(filePath: url.standardizedFileURL.path, directoryHint: .notDirectory)
    }

    /// The folder has the inlay.toml that Inlay looks for
    static func hasConfig(_ folder: URL) -> Bool {
        let file = folder.appending(path: configFileName).path
        return FileManager.default.fileExists(atPath: file) || (try? FileManager.default.destinationOfSymbolicLink(atPath: file)) != nil
    }

    /// Makes the config folder a link to the folder. A previous link is replaced; a real config folder is renamed to
    /// <folder>.backup-<date>, which is returned.
    /// - Parameter config: the text of the inlay.toml that the folder gets if it has none
    @discardableResult
    static func link(_ dir: URL = configFolder, to folder: URL, writing config: String?, now: Date = .now) throws(LinkError) -> URL? {
        let fileManager = FileManager.default
        do {
            if let config, !hasConfig(folder) {
                try Data(config.utf8).write(to: folder.appending(path: configFileName), options: .withoutOverwriting)
            }
            var backup: URL? = nil
            switch state(of: dir) {
                case .linked:
                    // The link, not the folder it points to
                    try fileManager.removeItem(at: dir)
                case .folder:
                    let url = backupUrl(dir, now: now)
                    try fileManager.moveItem(at: dir, to: url)
                    backup = url
                case .none:
                    try fileManager.createDirectory(at: dir.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try fileManager.createSymbolicLink(at: dir, withDestinationURL: folder)
            return backup
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    /// The config folder becomes a real folder again, with a copy of the inlay.toml that it was linked to. The folder
    /// that it pointed to is not touched
    static func unlink(_ dir: URL = configFolder) throws(LinkError) {
        guard case .linked = state(of: dir) else { return }
        let fileManager = FileManager.default
        do {
            let text = try? String(contentsOf: dir.appending(path: configFileName), encoding: .utf8)
            try fileManager.removeItem(at: dir)
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            if let text {
                try Data(text.utf8).write(to: dir.appending(path: configFileName))
            }
        } catch {
            throw .failed(error.localizedDescription)
        }
    }

    /// <dir>.backup-20261012-153000, or with -2, -3… if it is taken. The name that install.sh gives
    static func backupUrl(_ dir: URL, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = dir.path + ".backup-" + formatter.string(from: now)
        var candidate = base
        var n = 1
        while FileManager.default.fileExists(atPath: candidate) || (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate)) != nil {
            n += 1
            candidate = "\(base)-\(n)"
        }
        return URL(filePath: candidate)
    }

    /// The folders where people keep the config of Inlay in a dotfiles repo, the ones that exist. The same as install.sh
    static var candidates: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let bases = [".dotfiles", "dotfiles", ".dots", "dots"].map { home.appending(path: $0) } + [configFolder.deletingLastPathComponent().appending(path: "dotfiles")]
        return bases.flatMap { base in ["inlay", ".config/inlay", "config/inlay"].map { base.appending(path: $0) } }.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}

import Common
import Foundation

/// Writes a text file in one step: the file has either the old contents or the new ones, never a part of them.
///
/// If the path is a symlink (a config that lives in a dotfiles repo), the file it points to is replaced, and the link stays
enum AtomicFileWriter {
    enum WriteError: Error, Equatable {
        case tooManySymlinks
        case io(String)
    }

    static func write(_ text: String, to url: URL) throws(WriteError) {
        let target = try resolveSymlinks(url)
        let directory = target.deletingLastPathComponent()
        let temporary = directory.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: temporary)
            // The new file takes the place of the old one, so it must look like it
            if let permissions = try? FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
            }
        } catch {
            _ = try? FileManager.default.removeItem(at: temporary)
            throw .io(error.localizedDescription)
        }
        if unsafe rename(temporary.path, target.path) != 0 {
            let reason = unsafe String(cString: strerror(errno))
            _ = try? FileManager.default.removeItem(at: temporary)
            throw .io(reason)
        }
    }

    /// The file at the end of a chain of symlinks. The last link may point to a file that doesn't exist yet
    static func resolveSymlinks(_ url: URL) throws(WriteError) -> URL {
        var current = url.standardizedFileURL
        for _ in 0 ..< 32 {
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { return current }
            // A relative link is relative to the directory of the link
            current = URL(filePath: destination, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        throw .tooManySymlinks
    }
}

/// What `inlay config --use` and `--unlink` do with the files of the config. Inlay has no window to
/// edit the config: the file is the only place where it is kept
enum ConfigFiles {
    enum UseError: Error, Equatable {
        /// Inlay was started with --config-path: that file is the config, whatever is done here
        case configPathFlag
        case ambiguousConfig([URL])
        case notFound(URL)
        case unreadable(String)
        /// The file has errors: it isn't used
        case invalidConfig([String])
        /// A config folder would be a second config next to ~/.inlay.lua
        case dotfileConfig(URL)
        case alreadyInUse(URL)
        case notLinked
        case link(ConfigFolderLink.LinkError)
        case write(AtomicFileWriter.WriteError)
    }

    /// `--use <path>`. A folder: ~/.config/inlay becomes a link to it, with the rules of ConfigFolderLink (a folder
    /// without inlay.lua gets a copy of the config in use). A file: its text replaces the config in use, which is
    /// kept next to it as <file>.backup-<date>. Returns what was done, for the user
    @MainActor
    static func use(_ path: URL, now: Date = .now) -> Result<String, UseError> {
        if serverArgs.configLocation != nil { return .failure(.configPathFlag) }
        let current: URL?
        switch findCustomConfigUrl() {
            case .ambiguousConfigError(let candidates): return .failure(.ambiguousConfig(candidates))
            case .file(let url): current = url
            case .noCustomConfigExists, .legacyConfig: current = nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory) else { return .failure(.notFound(path)) }
        return isDirectory.boolValue ? useFolder(path, current: current, now: now) : useFile(path, current: current, now: now)
    }

    @MainActor
    private static func useFolder(_ path: URL, current: URL?, now: Date) -> Result<String, UseError> {
        if let current, current.deletingLastPathComponent().path != ConfigFolderLink.configFolder.path {
            return .failure(.dotfileConfig(current))
        }
        let folder: URL
        switch ConfigFolderLink.folder(of: path) {
            case .success(let url): folder = url
            case .failure(.alreadyLinked(let url)): return .failure(.alreadyInUse(url))
            case .failure(let error): return .failure(.link(error))
        }
        let hadConfig = ConfigFolderLink.hasConfig(folder)
        let text = (current ?? defaultConfigUrl).readText()
        let backup: URL?
        do {
            backup = try ConfigFolderLink.link(to: folder, writing: text, now: now)
        } catch {
            return .failure(.link(error))
        }
        var lines = ["\(ConfigFolderLink.configFolder.path.tildePath) -> \(folder.path.tildePath)"]
        if !hadConfig { lines.append("\(folder.appending(path: configFileName).path.tildePath) was created with a copy of the config in use") }
        if let backup { lines.append("The previous config folder is kept as \(backup.path.tildePath)") }
        return .success(lines.joined(separator: "\n"))
    }

    @MainActor
    private static func useFile(_ path: URL, current: URL?, now: Date) -> Result<String, UseError> {
        guard let text = path.readText() else { return .failure(.unreadable(path.path)) }
        // With the modules of its folder: the copy has none
        let errors = parseConfig(LuaConfigLoader.load(file: path)).errors
        if !errors.isEmpty { return .failure(.invalidConfig(errors.map { $0.description(.error) })) }
        let target = current ?? newUserConfigUrl
        let resolved = (try? AtomicFileWriter.resolveSymlinks(target)) ?? target
        if resolved.path == ((try? AtomicFileWriter.resolveSymlinks(path)) ?? path).path { return .failure(.alreadyInUse(target)) }
        var lines = ["\(target.path.tildePath) has the text of \(path.path.tildePath)"]
        do {
            if let old = current?.readText() {
                let backup = ConfigFolderLink.backupUrl(resolved, now: now)
                try AtomicFileWriter.write(old, to: backup)
                lines.append("The previous config is kept as \(backup.path.tildePath)")
            }
            try AtomicFileWriter.write(text, to: target)
        } catch {
            return .failure(.write(error))
        }
        return .success(lines.joined(separator: "\n"))
    }

    /// `--unlink`: ~/.config/inlay becomes a folder of its own again, with a copy of the config it was linked to
    @MainActor
    static func unlink() -> Result<String, UseError> {
        guard case .linked(let folder) = ConfigFolderLink.state() else { return .failure(.notLinked) }
        do {
            try ConfigFolderLink.unlink()
        } catch {
            return .failure(.link(error))
        }
        return .success("\(ConfigFolderLink.configFolder.path.tildePath) is a folder again, with a copy of the .lua files of \(folder.path.tildePath)")
    }
}

extension ConfigFiles.UseError {
    var message: String {
        switch self {
            case .configPathFlag: "Inlay was started with --config-path: that file is the config"
            case .ambiguousConfig(let candidates):
                "There are \(candidates.count) configs: \(candidates.map(\.path.tildePath).joined(separator: ", ")). Keep only one"
            case .notFound(let url): "\(url.path.tildePath) doesn't exist"
            case .unreadable(let path): "Can't read \(path.tildePath) as a UTF-8 text file"
            case .invalidConfig(let errors): (["The file has errors, it isn't used:"] + errors).joined(separator: "\n")
            case .dotfileConfig(let url): "The config is \(url.path.tildePath): a config folder would be a second config. Move it into a folder first"
            case .alreadyInUse(let url): "\(url.path.tildePath) is already the config"
            case .notLinked: "\(ConfigFolderLink.configFolder.path.tildePath) isn't a link"
            case .link(.notAConfig(let url)): "\(url.path.tildePath) isn't an \(configFileName)"
            case .link(.notAFolder(let url)): "\(url.path.tildePath) isn't a folder"
            case .link(.isTheConfigFolder): "That is the config folder itself"
            case .link(.alreadyLinked(let url)): "\(url.path.tildePath) is already the config folder"
            case .link(.failed(let reason)): reason
            case .write(.tooManySymlinks): "Too many symbolic links"
            case .write(.io(let reason)): reason
        }
    }
}

extension URL {
    fileprivate func readText() -> String? { try? String(contentsOf: self, encoding: .utf8) }
}

extension String {
    /// The path with ~ for the home folder, as the user writes it
    var tildePath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return hasPrefix(home + "/") ? "~" + dropFirst(home.count) : self
    }
}

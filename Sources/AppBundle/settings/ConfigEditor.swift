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

/// One change of the config file: the new value of a key, or nil to remove the key
struct ConfigEdit: Equatable, Sendable {
    var path: TomlKeyPath
    var value: TomlValue?
}

/// Changes keys of the config file of the user, for the settings window.
/// The file is the only place where the settings are kept: the window doesn't store anything on its own
enum ConfigEditor {
    enum EditError: Error, Equatable {
        case ambiguousConfig
        case unreadable(String)
        case patch(TomlPatcher.PatchError)
        /// The config has errors after the change. Nothing is written
        case invalidConfig(String)
        case write(AtomicFileWriter.WriteError)
    }

    /// The file to edit, and its current text
    struct Target: Equatable {
        var url: URL
        var text: String
        /// false: the user has no config yet. The text is the built-in config, and the first change creates the file
        var exists: Bool
    }

    @MainActor
    static func target() -> Result<Target, EditError> {
        switch findCustomConfigUrl() {
            case .ambiguousConfigError: .failure(.ambiguousConfig)
            case .file(let url): read(url).map { Target(url: url, text: $0, exists: true) }
            case .noCustomConfigExists: read(defaultConfigUrl).map { Target(url: newUserConfigUrl, text: $0, exists: false) }
        }
    }

    private static func read(_ url: URL) -> Result<String, EditError> {
        Result { try String(contentsOf: url, encoding: .utf8) }.mapError { .unreadable($0.localizedDescription) }
    }

    /// The text with the edits applied. Fails, changing nothing, if the result isn't a config without errors
    @MainActor
    static func patch(_ text: String, _ edits: [ConfigEdit]) -> Result<String, EditError> {
        var result = text
        for edit in edits {
            do {
                result = switch edit.value {
                    case let value?: try TomlPatcher.set(result, edit.path, value)
                    case nil: try TomlPatcher.remove(result, edit.path)
                }
            } catch {
                return .failure(.patch(error))
            }
        }
        if let error = parseConfig(result).errors.first {
            return .failure(.invalidConfig(error.description(.error)))
        }
        return .success(result)
    }

    /// Patches the text of the target and writes it. The caller reloads the config afterwards
    @MainActor
    static func apply(_ edits: [ConfigEdit], to target: Target) -> Result<Void, EditError> {
        let text: String
        switch patch(target.text, edits) {
            case .success(let patched): text = patched
            case .failure(let error): return .failure(error)
        }
        if text == target.text && target.exists { return .success(()) }
        do {
            try AtomicFileWriter.write(text, to: target.url)
            ConfigAutoReload.didWrite(text)
            return .success(())
        } catch {
            return .failure(.write(error))
        }
    }
}

extension ConfigEditor.EditError {
    var message: String {
        switch self {
            case .ambiguousConfig: Strings.Settings.ambiguousConfig
            case .unreadable(let reason): Strings.Settings.writeFailed(reason)
            case .patch(.unsupported): Strings.Settings.definedByHand
            case .patch(.invalidToml(let reason)): Strings.Settings.writeFailed(reason)
            case .patch(.verificationFailed): Strings.Settings.writeFailed("the key didn't get the new value")
            case .invalidConfig(let reason): Strings.Settings.writeFailed(reason)
            case .write(.tooManySymlinks): Strings.Settings.writeFailed("too many symbolic links")
            case .write(.io(let reason)): Strings.Settings.writeFailed(reason)
        }
    }
}

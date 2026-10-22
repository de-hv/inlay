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
        switch patch(target.text, edits) {
            case .success(let text): write(text, to: target)
            case .failure(let error): .failure(error)
        }
    }

    /// Writes the whole text of the config. The caller reloads the config afterwards
    @MainActor
    static func write(_ text: String, to target: Target) -> Result<Void, EditError> {
        if text == target.text && target.exists { return .success(()) }
        do {
            try AtomicFileWriter.write(text, to: target.url)
            ConfigAutoReload.didWrite(text)
            return .success(())
        } catch {
            return .failure(.write(error))
        }
    }

    /// The config of the user, complete: its own text, with its comments, and every key that it leaves out with the
    /// value that applies, so that nothing is implicit. The keys come from the settings window and from the shipped
    /// config. The key bindings and the window rules are the user's own: none is added
    @MainActor
    static func exportText(_ target: Target, shipped: String? = try? String(contentsOf: defaultConfigUrl, encoding: .utf8)) -> String {
        var text = target.text
        func add(_ path: TomlKeyPath, _ value: TomlValue) {
            guard case .absent = TomlPatcher.locate(text, path), TomlPatcher.decodedValue(text, path) == nil else { return }
            if let patched = try? TomlPatcher.set(text, path, value) { text = patched }
        }
        for key in SettingsKey.all where key.defaultValue != .string("") {
            add(key.path, key.defaultValue)
        }
        if let shipped, let root = try? TomlPatcher.decode(shipped) {
            for (path, value) in scalars(root, table: []) { add(path, value) }
        }
        let header = Strings.Settings.exportHeader(Date.now.formatted(date: .abbreviated, time: .shortened))
        return header + text
    }

    /// The keys of a decoded document that the patcher can write, in a stable order. Not the key bindings, the window
    /// rules or the key mapping: they are the user's own
    private static func scalars(_ table: [String: Any], table path: [String]) -> [(TomlKeyPath, TomlValue)] {
        let skipped: Set = ["mode", "on-window-detected", "key-mapping", "workspace-to-monitor-force-assignment"]
        return table.keys.sorted().flatMap { key -> [(TomlKeyPath, TomlValue)] in
            if path.isEmpty && skipped.contains(key) { return [] }
            let value = table[key]
            if let sub = value as? [String: Any] { return scalars(sub, table: path + [key]) }
            let candidates: [TomlValue] = [.string(""), .bool(false), .int(0), .float(0), .strings([])]
            guard let scalar = candidates.lazy.compactMap({ TomlValue(value, like: $0) }).first else { return [] }
            return [(TomlKeyPath(path, key), scalar)]
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

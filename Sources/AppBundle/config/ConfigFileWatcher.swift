import Common
import Foundation

/// Tells when a file may have changed, however it is saved and wherever it really lives:
/// - written in place, or replaced by another file (the atomic save of most editors, and of the settings window);
/// - reached through symlinks (a config that lives in a dotfiles repo), also when a link is pointed somewhere else;
/// - deleted and created again.
///
/// The file itself is watched, and also the directory of the file and of every link that leads to it: a new file
/// that takes the place of the old one is only seen as a change of its directory. A directory of the path can be
/// a link too (~/.config/inlay -> ~/.dotfiles/inlay): then the directory that holds that link is watched as well,
/// so pointing the link to another directory is seen.
/// After an event the file may be a different one, so the watcher must be armed again. See: arm
@MainActor
final class FileWatcher {
    private let url: URL
    private let onEvent: @MainActor () -> Void
    private var sources: [any DispatchSourceFileSystemObject] = []

    init(url: URL, onEvent: @escaping @MainActor () -> Void) {
        self.url = url
        self.onEvent = onEvent
        arm()
    }

    /// Watches the file that the path leads to right now. Events of other files of the same directories are reported too
    func arm() {
        cancel()
        var paths: [String] = []
        var current = url.standardizedFileURL
        for _ in 0 ..< 32 { // The same limit as AtomicFileWriter.resolveSymlinks
            // Opened through the links of the path: it is the real directory that is watched
            paths.append(current.deletingLastPathComponent().path)
            paths += Self.directoriesOfLinkedAncestors(of: current)
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { break }
            current = URL(filePath: destination, relativeTo: current.deletingLastPathComponent()).standardizedFileURL
        }
        paths.append(current.path)
        var seen: Set<String> = []
        for path in paths where seen.insert(path).inserted {
            let descriptor = unsafe open(path, O_EVTONLY)
            if descriptor < 0 { continue } // It doesn't exist (yet). Its directory tells when it does
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .extend, .delete, .rename, .revoke, .link],
                queue: .main,
            )
            source.setEventHandler { [weak self] in MainActor.checkIsolated { self?.onEvent() } }
            source.setCancelHandler { close(descriptor) }
            source.activate()
            sources.append(source)
        }
    }

    /// The directories that hold a symlink among the ancestors of the file: for
    /// ~/.config/inlay/inlay.toml with ~/.config/inlay -> ~/.dotfiles/inlay, it is ~/.config
    static func directoriesOfLinkedAncestors(of file: URL) -> [String] {
        var result: [String] = []
        var ancestor = file.standardizedFileURL.deletingLastPathComponent()
        while ancestor.path != "/" {
            let parent = ancestor.deletingLastPathComponent()
            // Not the links of the system at the root (/var, /tmp, /etc): nobody points them somewhere else
            if parent.path != "/", (try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path)) != nil {
                result.append(parent.path)
            }
            ancestor = parent
        }
        return result
    }

    func cancel() {
        for source in sources { source.cancel() }
        sources = []
    }

    isolated deinit {
        cancel()
    }
}

/// Reloads the config when its file is saved. See: 'auto-reload-config' config option
@MainActor
enum ConfigAutoReload {
    private static var watcher: FileWatcher? = nil
    private static var debounceTask: Task<Void, any Error>? = nil
    /// The text of the config file when it was last loaded, or written by the settings window. nil if it couldn't be read
    private static var loadedText: String? = nil

    private static let debounceDelay: Duration = .milliseconds(200)

    /// The config was loaded, or at least tried, from the file. Called after every (re)load: the file to watch may be
    /// another one, and so may the 'auto-reload-config' option. A file that failed to load is still watched,
    /// so that fixing it loads it
    static func sync(url: URL, text: String?) {
        loadedText = text
        watcher?.cancel()
        watcher = nil
        debounceTask?.cancel()
        if !config.autoReloadConfig { return }
        watcher = FileWatcher(url: url) {
            debounceTask?.cancel()
            debounceTask = Task.startUnstructured {
                try await Task.sleep(for: debounceDelay)
                watcher?.arm() // The file may have been replaced by a new one
                guard needsReload(currentText: try? String(contentsOf: url, encoding: .utf8)) else { return }
                if let token: RunSessionGuard = .isServerEnabled {
                    try await runLightSession(.configAutoReload, token) {
                        _ = await reloadConfig_nonCancellable()
                    }
                }
            }
        }
    }

    /// The settings window has written the text to the config file, and it reloads the config on its own
    /// right after. Without this, the watcher would see the new file and reload the config a second time
    static func didWrite(_ text: String) {
        loadedText = text
    }

    /// An event of the watcher doesn't mean that the config is different: the watcher also reports the other files
    /// of the directory, the saves that change nothing, and the file that Inlay itself has just written and loaded.
    /// - Parameter currentText: nil if the file can't be read right now: it is in the middle of being saved, or it is
    ///   gone. The next event tells when it is back
    static func needsReload(currentText: String?) -> Bool {
        needsReload(loadedText: loadedText, currentText: currentText)
    }

    nonisolated static func needsReload(loadedText: String?, currentText: String?) -> Bool {
        guard let currentText else { return false }
        return currentText != loadedText
    }
}

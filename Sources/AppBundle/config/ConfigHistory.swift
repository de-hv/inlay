import Common
import Foundation
import Observation

/// A reload that changed the config: the keys that changed, and who changed them
struct ConfigHistoryEntry: Equatable, Sendable, Identifiable {
    enum Source: Equatable, Sendable {
        /// The settings window wrote the file, or undid a change of its own
        case settings
        /// The file was saved by hand, or by another program
        case file
    }

    var id: Int
    var date: Date
    var source: Source
    var changes: [ConfigChange]
}

/// The changes of the config since Inlay started, the last one at the end: what Settings › Changes lists.
/// Only kept in memory
@MainActor
@Observable
final class ConfigHistory {
    static let shared = ConfigHistory()

    private(set) var entries: [ConfigHistoryEntry] = []
    /// The text that the settings window wrote last. The reload that applies it is the window's change, whatever runs
    /// it first: the window itself or the watcher of the file. See: SettingsModel.write
    @ObservationIgnored var lastTextWrittenBySettings: String? = nil
    @ObservationIgnored private var nextId = 0

    static let maxEntries = 100

    /// Records what changed between the config that was applied and the new one. Nothing if only comments or the
    /// formatting changed, or if there is nothing to compare with (the first load)
    func record(from oldText: String?, to newText: String?, date: Date = .now) {
        guard let oldText, let newText, oldText != newText,
              let changes = ConfigDiff.changes(from: oldText, to: newText), !changes.isEmpty else { return }
        let source: ConfigHistoryEntry.Source = newText == lastTextWrittenBySettings ? .settings : .file
        entries.append(ConfigHistoryEntry(id: nextId, date: date, source: source, changes: changes))
        nextId += 1
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    func clear() {
        entries = []
    }
}

import AppKit
import Common
import SwiftUI

/// "cmd-alt-ctrl-j" -> "⌃⌥⌘J", in the order macOS shows the modifiers
func prettyKeyNotation(_ binding: String) -> String {
    let symbols: [String: String] = ["ctrl": "⌃", "alt": "⌥", "shift": "⇧", "cmd": "⌘"]
    let keys: [String: String] = [
        "left": "←", "right": "→", "up": "↑", "down": "↓", "enter": "↩", "esc": "⎋", "space": "Space", "tab": "⇥",
        "backspace": "⌫", "comma": ",", "period": ".", "slash": "/", "semicolon": ";", "minus": "-", "equal": "=",
        "leftSquareBracket": "[", "rightSquareBracket": "]", "quote": "'", "backtick": "`", "backslash": "\\",
    ]
    var parts = binding.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    // 'cmd-alt-minus' is written that way; a bare '-' would be an empty part
    let key = parts.popLast() ?? ""
    let modifiers = ["ctrl", "alt", "shift", "cmd"].filter(parts.contains).compactMap { symbols[$0] }.joined()
    return modifiers + (keys[key] ?? key.uppercased())
}

// MARK: - Keyboard

/// The key bindings of the config. Read only: they are edited in the file
struct KeyboardSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            ShortcutsSections(model: model)
            Section {
                LabeledContent {
                    Button(Strings.Settings.open) { openConfigInEditor() }
                } label: {
                    Text(Strings.Settings.editRules)
                    Text(Strings.Settings.editRulesDetail)
                }
            }
        }
    }
}

/// A key binding, as macOS shows one
private struct Keycap: View {
    let text: String
    var help: String = ""
    var isSecondary: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(isSecondary ? .secondary : .primary)
            .background(Color.secondary.opacity(isSecondary ? 0.08 : 0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5) }
            .help(help)
            .fixedSize()
    }
}

private func footnote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
}

// MARK: - Shortcuts

/// A key binding of the config, with the comment written after it
struct ShortcutEntry: Equatable {
    var key: String
    var commands: [String]
    var comment: String?
}

enum ShortcutEntries {
    /// The binding modes in the order of the file, and their bindings in the order of the file
    static func make(_ document: TomlPatcher.Document, root: [String: Any]) -> [(mode: String, entries: [ShortcutEntry])] {
        let modes = root["mode"] as? [String: Any] ?? [:]
        var result: [(mode: String, entries: [ShortcutEntry])] = []
        for entry in document.entries {
            guard let table = entry.table, table.count == 3, table[0] == "mode", table[2] == "binding", entry.key.count == 1 else { continue }
            let mode = table[1]
            let key = entry.key[0]
            let raw = ((modes[mode] as? [String: Any])?["binding"] as? [String: Any])?[key]
            let shortcut = ShortcutEntry(key: key, commands: commandList(raw), comment: document.trailingComment(of: entry))
            if let index = result.firstIndex(where: { $0.mode == mode }) {
                result[index].entries.append(shortcut)
            } else {
                result.append((mode, [shortcut]))
            }
        }
        return result
    }

    /// `run = 'a'` or `run = ['a', 'b']`
    static func commandList(_ raw: Any?) -> [String] {
        if let string = raw as? String { return [string] }
        return (raw as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

/// The key bindings of the config, mode by mode
private struct ShortcutsSections: View {
    let model: SettingsModel

    var body: some View {
        let modes = ShortcutEntries.make(model.fileDocument, root: model.rawRoot)
        let mode = modes.first { $0.mode == model.shortcutsMode } ?? modes.first
        let filter = model.shortcutsFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let entries = (mode?.entries ?? []).filter { entry in
            filter.isEmpty || ([entry.key, prettyKeyNotation(entry.key), entry.comment ?? ""] + entry.commands).contains { $0.lowercased().contains(filter) }
        }
        Group {
            Section {
                HStack(spacing: 10) {
                    Picker("", selection: Binding(get: { mode?.mode ?? mainModeId }, set: { model.shortcutsMode = $0 })) {
                        ForEach(modes.map(\.mode), id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Spacer(minLength: 8)
                    TextField("", text: Binding(get: { model.shortcutsFilter }, set: { model.shortcutsFilter = $0 }), prompt: Text(Strings.Settings.filterShortcuts))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 180)
                }
            }
            Section {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Keycap(text: prettyKeyNotation(entry.key), help: entry.key)
                            .frame(width: 92, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.commands.joined(separator: "  ·  "))
                                .font(.system(size: 11.5, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                            if let comment = entry.comment {
                                Text(comment).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                if entries.isEmpty {
                    Text(modes.isEmpty ? Strings.Settings.noShortcuts : Strings.Settings.noMatchingShortcuts).foregroundStyle(.secondary)
                }
            } header: {
                Text(mode.map { "[mode.\($0.mode).binding] · \(entries.count)" } ?? Strings.Settings.shortcuts)
                    .font(.system(size: 11, design: .monospaced))
            } footer: {
                footnote(Strings.Settings.shortcutsFooter)
            }
        }
    }
}

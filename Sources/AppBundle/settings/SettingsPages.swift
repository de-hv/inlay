import AppKit
import Common
import SwiftUI

// MARK: - Workspaces

/// A workspace as the config defines it: the apps that the window rules send to it, the key bindings that go to it,
/// and whether it is persistent. Read from the text of the config file
struct WorkspaceSummary: Equatable {
    var name: String
    var isPersistent: Bool
    /// The bundle ids of the apps that an `on-window-detected` rule sends here
    var apps: [String] = []
    /// The binding of the main mode that runs `workspace <name>`
    var goKey: String? = nil
    /// The binding of the main mode that moves the focused window here
    var moveKey: String? = nil
}

/// What the Workspaces page shows, from the decoded config file
enum WorkspaceSummaries {
    /// The persistent workspaces and the ones that the rules or the bindings name, in the natural order of their names:
    /// making one persistent or not doesn't move it
    static func make(root: [String: Any]) -> (workspaces: [WorkspaceSummary], floatingApps: [String]) {
        let persistent = (root[persistentWorkspacesKey] as? [Any])?.compactMap { $0 as? String } ?? []
        var apps: [String: [String]] = [:]
        var floating: [String] = []
        for rule in root["on-window-detected"] as? [[String: Any]] ?? [] {
            guard let appId = (rule["if"] as? [String: Any])?["app-id"] as? String else { continue }
            let commands = commandList(rule["run"])
            if let workspace = commands.lazy.compactMap({ target(of: $0, command: "move-node-to-workspace") }).first {
                apps[workspace, default: []].append(appId)
            } else if commands.contains(where: { $0.hasPrefix("layout floating") }) {
                floating.append(appId)
            }
        }
        var goKeys: [String: String] = [:]
        var moveKeys: [String: String] = [:]
        let bindings = ((root["mode"] as? [String: Any])?[mainModeId] as? [String: Any])?["binding"] as? [String: Any] ?? [:]
        for key in bindings.keys.sorted() {
            for command in commandList(bindings[key]) {
                if let workspace = target(of: command, command: "workspace"), goKeys[workspace] == nil { goKeys[workspace] = key }
                if let workspace = target(of: command, command: "move-node-to-workspace"), moveKeys[workspace] == nil { moveKeys[workspace] = key }
            }
        }
        let names = Set(persistent).union(apps.keys).union(goKeys.keys).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let workspaces = names.map { name in
            WorkspaceSummary(name: name, isPersistent: persistent.contains(name), apps: apps[name] ?? [], goKey: goKeys[name], moveKey: moveKeys[name])
        }
        return (workspaces, floating)
    }

    /// `run = 'a'` or `run = ['a', 'b']`
    static func commandList(_ raw: Any?) -> [String] {
        if let string = raw as? String { return [string] }
        return (raw as? [Any])?.compactMap { $0 as? String } ?? []
    }

    /// `workspace 3` -> "3". Flags are skipped: `move-node-to-workspace --focus-follows-window 3` -> "3"
    static func target(of command: String, command name: String) -> String? {
        let words = command.split(separator: " ").map(String.init)
        guard words.first == name else { return nil }
        let arguments = words.dropFirst().filter { !$0.hasPrefix("-") }
        // 'workspace next' and the like aren't a workspace
        guard arguments.count == 1, let target = arguments.first, !["next", "prev"].contains(target) else { return nil }
        return target
    }
}

/// The name of an app from its bundle id: the one of the app if it is installed, else the comment written after the
/// id in the config (`if.app-id = 'com.raycast.macos' # Raycast (its settings window)` -> "Raycast"), else the
/// name of a well-known app, else the last part of the id
@MainActor
func appDisplayName(_ bundleId: String, in document: TomlPatcher.Document? = nil) -> String {
    if let name = appNames[bundleId] { return name }
    let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
    let commented = document?.lines.lazy.compactMap { line -> String? in
        guard line.content.contains("'\(bundleId)'") || line.content.contains("\"\(bundleId)\""),
              let hash = line.content.firstIndex(of: "#") else { return nil }
        let comment = line.content[line.content.index(after: hash)...]
            .prefix { $0 != "(" && $0 != ":" }
            .trimmingCharacters(in: .whitespaces)
        return comment.isEmpty ? nil : comment
    }.first
    let name = installed ?? commented ?? knownAppNames[bundleId] ?? bundleId.split(separator: ".").last.map(String.init) ?? bundleId
    // The name of an installed app doesn't change: the others may get a comment later
    if installed != nil { appNames[bundleId] = name }
    return name
}

private let knownAppNames = [
    "com.tinyspeck.slackmacgap": "Slack",
    "com.microsoft.teams2": "Microsoft Teams",
    "com.raycast.macos": "Raycast",
    "com.1password.1password": "1Password",
    "cx.c3.theunarchiver": "The Unarchiver",
]

@MainActor private var appNames: [String: String] = [:]

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

/// The workspaces of the config: their apps, their key bindings, and the persistent ones. The apps are read only:
/// the rules that send them are edited in the file
struct WorkspacesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        let summary = WorkspaceSummaries.make(root: model.rawRoot)
        SettingsPage {
            ErrorBanner(model: model)
            Section {
                ForEach(summary.workspaces, id: \.name) { workspace in
                    row(workspace)
                }
                if summary.workspaces.isEmpty {
                    Text(Strings.Settings.noWorkspaces).foregroundStyle(.secondary)
                }
            } header: {
                Text(Strings.Settings.workspacesPage)
            } footer: {
                footnote(Strings.Settings.workspacesFooter)
            }
            if !summary.floatingApps.isEmpty {
                Section {
                    Text(summary.floatingApps.map { appDisplayName($0, in: model.fileDocument) }.joined(separator: " · "))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text(Strings.Settings.floatingApps)
                } footer: {
                    footnote(Strings.Settings.floatingAppsFooter)
                }
            }
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

    private func row(_ workspace: WorkspaceSummary) -> some View {
        let key = SettingsKey.persistentWorkspaces
        let label = model.menuBarTheme == .labels ? model.config.menuBar.labels[workspace.name] : nil
        return LabeledContent {
            HStack(spacing: 10) {
                if let go = workspace.goKey {
                    Keycap(text: prettyKeyNotation(go), help: Strings.Settings.goToWorkspaceKey(go))
                }
                if let move = workspace.moveKey {
                    Keycap(text: prettyKeyNotation(move), help: Strings.Settings.moveToWorkspaceKey(move), isSecondary: true)
                }
                Toggle("", isOn: Binding(get: { workspace.isPersistent }, set: { setPersistent(workspace.name, $0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.disabledReason(key) != nil)
                    .help(Strings.Settings.persistentHelp)
            }
        } label: {
            HStack(spacing: 8) {
                Text(workspace.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .frame(minWidth: 22, minHeight: 20)
                    .padding(.horizontal, 3)
                    .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    if let label { Text(label).font(.system(size: 13, weight: .medium)) }
                    Text(workspace.apps.isEmpty ? Strings.Settings.noAppsHere : workspace.apps.map { appDisplayName($0, in: model.fileDocument) }.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(workspace.apps.isEmpty ? .secondary : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onHover { model.hover(key, $0) }
        .settingsHighlight(model, workspace.name)
    }

    /// Adds the workspace to `persistent-workspaces`, in the order of the page, or removes it
    private func setPersistent(_ name: String, _ isOn: Bool) {
        let order = WorkspaceSummaries.make(root: model.rawRoot).workspaces.map(\.name)
        var names = model.strings(.persistentWorkspaces).filter { $0 != name }
        if isOn {
            names.append(name)
            names.sort { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
        }
        model.set(.persistentWorkspaces, .strings(names))
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
            let shortcut = ShortcutEntry(key: key, commands: WorkspaceSummaries.commandList(raw), comment: document.trailingComment(of: entry))
            if let index = result.firstIndex(where: { $0.mode == mode }) {
                result[index].entries.append(shortcut)
            } else {
                result.append((mode, [shortcut]))
            }
        }
        return result
    }
}

/// The key bindings of the config, mode by mode. Read only: they are edited in the file
struct ShortcutsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        let modes = ShortcutEntries.make(model.fileDocument, root: model.rawRoot)
        let mode = modes.first { $0.mode == model.shortcutsMode } ?? modes.first
        let filter = model.shortcutsFilter.trimmingCharacters(in: .whitespaces).lowercased()
        let entries = (mode?.entries ?? []).filter { entry in
            filter.isEmpty || ([entry.key, prettyKeyNotation(entry.key), entry.comment ?? ""] + entry.commands).contains { $0.lowercased().contains(filter) }
        }
        SettingsPage {
            ErrorBanner(model: model)
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
            Section {
                LabeledContent {
                    Button(Strings.Settings.open) { openConfigInEditor() }
                } label: {
                    Text(Strings.Settings.editShortcuts)
                }
            }
        }
    }
}

import AppKit
import Common
import SwiftUI

let settingsWidth: CGFloat = 600

/// The content of a tab: a form as tall as its rows. The window shows all of it, or scrolls it when the screen
/// is too small for that. See: SettingsPageController
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form(content: content)
            .formStyle(.grouped)
            // The form is a scroll view too, but it has nothing to scroll: it is as tall as its rows.
            // The mouse wheel is for the scroll view of the tab
            .scrollDisabled(true)
            .frame(width: settingsWidth)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A row of the settings: the title, what the key does (or why it can't be changed), the name of the key
/// in the config file, and the control
private struct SettingsRow<Control: View>: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey
    /// false: the header of the section already names the table of the key
    var showsTable: Bool = true
    @ViewBuilder let control: () -> Control

    var body: some View {
        let disabledReason = model.disabledReason(key)
        let showsKeysAlways = model.bool(.settingsShowKeys)
        LabeledContent {
            HStack(spacing: 10) {
                // The window and the file are the same thing: the row tells the key it writes, when asked to.
                // Always: in the row. On demand: a tag right before the control, over the row, so that nothing moves
                if showsKeysAlways {
                    KeyLabel(model: model, key: key, showsTable: showsTable)
                }
                control().disabled(disabledReason != nil)
            }
            .overlay(alignment: .leading) {
                if !showsKeysAlways && model.showsKey(key) {
                    // A frame without width, and the tag past its leading edge: no alignment guide, which would move
                    // the control, and no size, which would change the row
                    KeyLabel(model: model, key: key, showsTable: showsTable)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color(nsColor: .windowBackgroundColor)))
                        .overlay { Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 0.5) }
                        .fixedSize()
                        .frame(width: 0, alignment: .trailing)
                        .offset(x: -10)
                }
            }
        } label: {
            Text(title)
            if let text = disabledReason ?? detail { Text(text) }
        }
        .onHover { model.hover(key, $0) }
    }
}

/// The name of a key, next to its control. A click copies its line of the config: `width = 4`
private struct KeyLabel: View {
    let model: SettingsModel
    let key: SettingsKey
    var showsTable: Bool = true

    var body: some View {
        Button {
            "\(TomlPatcher.keyLiteral(key.path.key)) = \(model.value(key).literal)".copyToClipboard()
        } label: {
            Text(showsTable ? key.label : key.path.key)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
        .buttonStyle(.plain)
        .help(Strings.Settings.copyKey)
    }
}

private struct ToggleRow: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key) {
            Toggle("", isOn: Binding(get: { model.bool(key) }, set: { model.set(key, .bool($0)) }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A number. The slider shows its value while it is dragged, and writes it when it is released. The field next to it
/// takes an exact value, and its arrows go a step up or down
private struct SliderRow: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey
    let range: ClosedRange<Int>
    var step: Int = 1
    /// false: the header of the section already names the table of the key
    var showsTable: Bool = true
    var unit: String = Strings.Settings.pointsUnit

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key, showsTable: showsTable) {
            // No tick marks: a continuous slider, rounded to the step. A mark under it tells the default
            Slider(
                value: Binding(get: { Double(model.int(key)) }, set: { model.preview(key, .int(snap($0))) }),
                in: Double(range.lowerBound) ... Double(range.upperBound),
            ) { isEditing in
                if !isEditing { model.commit(key) }
            }
            .frame(width: 140)
            .overlay(alignment: .bottomLeading) { DefaultMark(fraction: defaultFraction) }
            NumberField(
                value: Binding(get: { model.int(key) }, set: { model.set(key, .int(clamp($0))) }),
                stepped: Binding(get: { model.int(key) }, set: { model.setDebounced(key, .int(clamp($0))) }),
                range: range,
                step: step,
                unit: unit,
            )
        }
    }

    private func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }
    private func snap(_ value: Double) -> Int { clamp(Int((value / Double(step)).rounded()) * step) }

    private var defaultFraction: Double? {
        guard case .int(let value) = key.defaultValue, range.upperBound > range.lowerBound else { return nil }
        return Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }
}

/// A fraction shown in percent: [tiling] split-ratio
private struct PercentSliderRow: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey
    let range: ClosedRange<Int>

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key) {
            Slider(
                value: Binding(get: { model.float(key) * 100 }, set: { model.preview(key, .float(Double(clamp(Int($0.rounded()))) / 100)) }),
                in: Double(range.lowerBound) ... Double(range.upperBound),
            ) { isEditing in
                if !isEditing { model.commit(key) }
            }
            .frame(width: 140)
            .overlay(alignment: .bottomLeading) { DefaultMark(fraction: 0.5) }
            NumberField(
                value: Binding(get: { percent }, set: { model.set(key, .float(Double(clamp($0)) / 100)) }),
                stepped: Binding(get: { percent }, set: { model.setDebounced(key, .float(Double(clamp($0)) / 100)) }),
                range: range,
                step: 5,
                unit: "%",
            )
        }
    }

    private var percent: Int { Int((model.float(key) * 100).rounded()) }
    private func clamp(_ value: Int) -> Int { min(max(value, range.lowerBound), range.upperBound) }
}

/// The default value, as a small mark under the track of a slider
private struct DefaultMark: View {
    let fraction: Double?
    /// The knob never reaches the ends of the track: half of its width is left on each side
    private static let inset: CGFloat = 10

    var body: some View {
        if let fraction {
            GeometryReader { geometry in
                Capsule()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 2, height: 4)
                    .offset(x: Self.inset + (geometry.size.width - 2 * Self.inset) * fraction - 1, y: geometry.size.height - 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// An exact value, typed or stepped. `value` is written when the field is done, `stepped` at every click of the arrows
private struct NumberField: View {
    let value: Binding<Int>
    let stepped: Binding<Int>
    let range: ClosedRange<Int>
    let step: Int
    let unit: String

    var body: some View {
        HStack(spacing: 3) {
            TextField("", value: value, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 46)
                .labelsHidden()
            Stepper("", value: stepped, in: range, step: step)
                .labelsHidden()
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
        }
    }
}

/// The value as text, a color well, the special values, and "Reset"
private struct ColorRow: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey
    let allowsAuto: Bool

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key, showsTable: false) {
            Text(model.string(key))
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 100, alignment: .trailing)
            ColorPicker("", selection: selection, supportsOpacity: true)
                .labelsHidden()
            Menu {
                if allowsAuto {
                    Button(ConfigColor.autoLiteral) { model.set(key, .string(ConfigColor.autoLiteral)) }
                }
                Button(ConfigColor.systemAccentLiteral) { model.set(key, .string(ConfigColor.systemAccentLiteral)) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            Button(Strings.Settings.reset) { model.reset(key) }
                .buttonStyle(.link)
                .disabled(!model.isSet(key))
        }
    }

    /// 'auto' as the color of the text of a dark menu bar
    private var rgba: Rgba { model.color(key).resolve(auto: .white, systemAccent: .systemAccent) }

    private var selection: Binding<Color> {
        Binding(
            get: { Color(nsColor: rgba.nsColor) },
            set: { color in
                let new = Rgba(NSColor(color))
                // The picker also sets the color it was given. That must not turn 'auto' into a fixed color
                if new.hex != rgba.hex { model.setDebounced(key, .string(new.hex)) }
            },
        )
    }
}

/// The color of a binding mode, [borders.mode-colors]. Without one, the mode uses the active color: the swatch
/// shows it striped, and "Set Color…" starts from it
private struct ModeColorRow: View {
    let model: SettingsModel
    let mode: String

    private var key: SettingsKey { .bordersModeColor(mode) }

    var body: some View {
        let isSet = model.isSet(key)
        SettingsRow(model: model, title: mode, detail: isSet ? model.string(key) : Strings.Settings.usesActiveColor, key: key, showsTable: false) {
            if isSet {
                ColorPicker("", selection: selection, supportsOpacity: true)
                    .labelsHidden()
                Button(Strings.Settings.remove) { model.reset(key) }
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(nsColor: inherited.nsColor).opacity(0.35))
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    }
                    .frame(width: 38, height: 20)
                    .accessibilityHidden(true)
                Button(Strings.Settings.setColor) { model.set(key, .string(inherited.hex)) }
            }
        }
    }

    /// The color of the active border
    private var inherited: Rgba {
        model.color(.bordersActiveColor).resolve(auto: .white, systemAccent: .systemAccent)
    }

    private var selection: Binding<Color> {
        Binding(
            get: { Color(nsColor: model.color(key).resolve(auto: .white, systemAccent: .systemAccent).nsColor) },
            set: { color in model.setDebounced(key, .string(Rgba(NSColor(color)).hex)) },
        )
    }
}

/// "Colors  [menu-bar.colors]": the title of a section whose rows only show the names of their keys
private func tableHeader(_ title: String, _ key: SettingsKey) -> some View {
    HStack(spacing: 8) {
        Text(title)
        Text("[\(key.path.table.joined(separator: "."))]")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
    }
}

private struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 9, height: 9)
    }
}

struct ErrorBanner: View {
    let model: SettingsModel
    var body: some View {
        if let message = model.errorMessage ?? model.unavailableReason {
            Section {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.multicolor)
            }
        }
    }
}

/// A key with a few possible values, as a segmented control
private func pickerRow(_ model: SettingsModel, _ title: String, detail: String, key: SettingsKey, options: [(value: String, title: String)]) -> some View {
    SettingsRow(model: model, title: title, detail: detail, key: key) {
        Picker("", selection: Binding(get: { model.string(key) }, set: { model.set(key, .string($0)) })) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            Section(Strings.Settings.startup) {
                ToggleRow(model: model, title: Strings.Settings.startAtLogin, detail: Strings.Settings.startAtLoginDetail, key: .startAtLogin)
            }
            Section(Strings.Settings.configuration) {
                LabeledContent {
                    Button(Strings.Settings.showInFinder) {
                        if let url = model.target?.url { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    }
                    .disabled(model.target?.exists != true)
                    Button(Strings.Settings.open) { openConfigInEditor() }
                } label: {
                    Text(Strings.Settings.file)
                    Text(filePath).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
                ConfigFolderRow(model: model)
                LabeledContent {
                    Button(Strings.Settings.reloadNow) { reloadConfigFromUi(warningsAsErrors: false) }
                        .disabled(!model.isAccessibilityGranted || model.isPaused)
                } label: {
                    Text(Strings.Settings.status)
                    HStack(spacing: 6) {
                        StatusDot(color: loadColor)
                        Text(loadStatus)
                    }
                }
                LabeledContent {
                    Button(Strings.Settings.exportButton) { export() }
                        .disabled(model.target == nil)
                } label: {
                    Text(Strings.Settings.export)
                    Text(Strings.Settings.exportDetail)
                }
            }
            Section(Strings.Settings.permissions) {
                LabeledContent {
                    Button(Strings.Settings.openSystemSettings) {
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility").map { _ = NSWorkspace.shared.open($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        StatusDot(color: model.isAccessibilityGranted ? .green : .red)
                        Text(model.isAccessibilityGranted ? Strings.Settings.accessibilityGranted : Strings.Settings.accessibilityMissing)
                    }
                    Text(Strings.Settings.accessibilityDetail)
                }
            }
            Section {} footer: {
                Text("\(Strings.Menu.version) · \(Strings.Settings.footer)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Asks where to save the complete config, and writes it there. The config of the user isn't touched
    private func export() {
        guard let text = model.exportText else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Strings.Settings.exportFileName
        panel.allowedContentTypes = [.init(filenameExtension: "toml") ?? .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            model.errorMessage = Strings.Settings.exportFailed(error.localizedDescription)
        }
    }

    private var filePath: String {
        guard let target = model.target else { return "–" }
        let path = (target.url.path as NSString).abbreviatingWithTildeInPath
        return target.exists ? path : "\(Strings.Settings.builtInConfig) \(path)"
    }

    private var loadStatus: String {
        guard let load = model.lastLoad else { return Strings.Settings.notLoadedYet }
        let ago = RelativeDateTimeFormatter().localizedString(for: load.date, relativeTo: .now)
        return load.isApplied
            ? Strings.Settings.loaded(ago, load.errorCount, load.warningCount)
            : Strings.Settings.notApplied(ago, load.errorCount)
    }

    private var loadColor: Color {
        guard let load = model.lastLoad else { return .gray }
        return switch true {
            case load.errorCount > 0: .red
            case load.warningCount > 0: .yellow
            default: .green
        }
    }
}

/// The config folder, and a link from it to a folder of the user: the question of install.sh. See: ConfigFolderLink
private struct ConfigFolderRow: View {
    let model: SettingsModel

    var body: some View {
        let dir = ConfigFolderLink.configFolder
        let state = ConfigFolderLink.state(of: dir)
        let usesDotfile = isDotfileConfig
        LabeledContent {
            if case .linked = state {
                Button(Strings.Settings.unlink) { unlink() }
            }
            Button(Strings.Settings.linkFolder) { link() }
        } label: {
            Text(Strings.Settings.configFolder)
            switch state {
                case .linked(let folder):
                    Text("\(pretty(dir)) → \(pretty(folder))").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                case .folder, .none:
                    Text(pretty(dir)).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
            }
            Text(usesDotfile ? Strings.Settings.configFolderDotfile(configDotfileName) : Strings.Settings.configFolderDetail)
        }
        .disabled(usesDotfile || model.unavailableReason != nil || model.target == nil)
    }

    /// The config in use is ~/.inlay.toml: a config folder would be a second config. install.sh skips the question too
    private var isDotfileConfig: Bool {
        model.target.map { $0.exists && $0.url.lastPathComponent == configDotfileName } ?? false
    }

    private func pretty(_ url: URL) -> String { (url.path as NSString).abbreviatingWithTildeInPath }

    private func link() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = Strings.Settings.linkPrompt
        panel.message = Strings.Settings.linkPanelMessage
        panel.directoryURL = ConfigFolderLink.candidates.first ?? FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let picked = panel.url else { return }
        let folder: URL
        switch ConfigFolderLink.folder(of: picked) {
            case .success(let url): folder = url
            case .failure(let error):
                show(error)
                return
        }
        // Which config the folder gets if it has none: the one in use, or the built-in one. Else, a confirmation
        var config: String? = nil
        let alert = NSAlert()
        if ConfigFolderLink.hasConfig(folder) {
            alert.messageText = Strings.Settings.linkTitle(pretty(ConfigFolderLink.configFolder), pretty(folder))
            alert.informativeText = Strings.Settings.linkDetail(pretty(folder), hasRealFolder: ConfigFolderLink.state() == .folder)
            alert.addButton(withTitle: Strings.Settings.linkPrompt)
            alert.addButton(withTitle: Strings.Settings.cancel)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        } else {
            alert.messageText = Strings.Settings.noConfigInFolderTitle(pretty(folder))
            alert.informativeText = Strings.Settings.noConfigInFolderDetail(hasRealFolder: ConfigFolderLink.state() == .folder)
            alert.addButton(withTitle: Strings.Settings.copyMyConfig)
            alert.addButton(withTitle: Strings.Settings.useDefaultConfig)
            alert.addButton(withTitle: Strings.Settings.cancel)
            switch alert.runModal() {
                case .alertFirstButtonReturn: config = model.target?.text
                case .alertSecondButtonReturn: config = try? String(contentsOf: defaultConfigUrl, encoding: .utf8)
                default: return
            }
        }
        do {
            let backup = try ConfigFolderLink.link(to: folder, writing: config)
            model.configFileDidMove()
            if let backup {
                let done = NSAlert()
                done.messageText = Strings.Settings.linkedTitle(pretty(ConfigFolderLink.configFolder), pretty(folder))
                done.informativeText = Strings.Settings.backupKept(pretty(backup))
                done.runModal()
            }
        } catch {
            show(error)
        }
    }

    private func unlink() {
        guard case .linked(let folder) = ConfigFolderLink.state() else { return }
        let alert = NSAlert()
        alert.messageText = Strings.Settings.unlinkTitle(pretty(ConfigFolderLink.configFolder))
        alert.informativeText = Strings.Settings.unlinkDetail(pretty(folder))
        alert.addButton(withTitle: Strings.Settings.unlink)
        alert.addButton(withTitle: Strings.Settings.cancel)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try ConfigFolderLink.unlink()
            model.configFileDidMove()
        } catch {
            show(error)
        }
    }

    private func show(_ error: ConfigFolderLink.LinkError) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = Strings.Settings.cantLink
        alert.informativeText = switch error {
            case .notAConfig(let url): Strings.Settings.notAConfig(pretty(url))
            case .notAFolder(let url): Strings.Settings.notAFolder(pretty(url))
            case .isTheConfigFolder: Strings.Settings.isTheConfigFolder
            case .alreadyLinked(let url): Strings.Settings.alreadyLinked(pretty(url))
            case .failed(let reason): reason
        }
        alert.runModal()
    }
}

// MARK: - Windows

/// How the windows are laid out: tiling, gaps and animations
struct WindowsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            TilingSections(model: model)
            GapsSections(model: model)
            AnimationsSections(model: model)
        }
    }
}

/// The [tiling] table
private struct TilingSections: View {
    let model: SettingsModel

    var body: some View {
        Group {
            Section(Strings.Settings.newWindows) {
                let isDwindle = model.string(.newWindowPlacement) == NewWindowPlacement.dwindle.rawValue
                pickerRow(
                    model,
                    Strings.Settings.placement,
                    detail: isDwindle ? Strings.Settings.placementDwindleDetail : Strings.Settings.placementAfterFocusedDetail,
                    key: .newWindowPlacement,
                    options: [
                        (NewWindowPlacement.dwindle.rawValue, Strings.Settings.dwindle),
                        (NewWindowPlacement.afterFocused.rawValue, Strings.Settings.afterFocused),
                    ],
                )
                pickerRow(
                    model,
                    Strings.Settings.splitTarget,
                    detail: splitTargetDetail(isDwindle: isDwindle),
                    key: .splitTarget,
                    options: [
                        (SplitTarget.focused.rawValue, Strings.Settings.focusedWindow),
                        (SplitTarget.cursor.rawValue, Strings.Settings.cursor),
                    ],
                )
                .disabled(!isDwindle)
                PercentSliderRow(
                    model: model,
                    title: Strings.Settings.splitRatio,
                    detail: Strings.Settings.splitRatioDetail,
                    key: .splitRatio,
                    range: 10 ... 90,
                )
                .disabled(!isDwindle)
            }
            Section(Strings.Settings.arrangement) {
                pickerRow(
                    model,
                    Strings.Settings.startupLayout,
                    detail: startupLayoutDetail,
                    key: .startupLayout,
                    options: [
                        (StartupLayout.grid.rawValue, Strings.Settings.grid),
                        (StartupLayout.row.rawValue, Strings.Settings.row),
                        (StartupLayout.dwindle.rawValue, Strings.Settings.dwindle),
                    ],
                )
                SliderRow(
                    model: model,
                    title: Strings.Settings.minWindowSize,
                    detail: Strings.Settings.minWindowSizeDetail,
                    key: .minWindowSize,
                    range: TilingConfig.minWindowSizeRange,
                    step: 10,
                )
            }
        }
    }

    private func splitTargetDetail(isDwindle: Bool) -> String {
        switch SplitTarget(rawValue: model.string(.splitTarget)) {
            case _ where !isDwindle: Strings.Settings.splitTargetNotDwindleDetail
            case .cursor: Strings.Settings.splitTargetCursorDetail
            case .focused, nil: Strings.Settings.splitTargetFocusedDetail
        }
    }

    private var startupLayoutDetail: String {
        switch StartupLayout(rawValue: model.string(.startupLayout)) {
            case .row: Strings.Settings.startupRowDetail
            case .dwindle: Strings.Settings.startupDwindleDetail
            case .grid, nil: Strings.Settings.startupGridDetail
        }
    }
}

/// The [animations] table
private struct AnimationsSections: View {
    let model: SettingsModel

    var body: some View {
        Group {
            Section(Strings.Settings.animations) {
                ToggleRow(model: model, title: Strings.Settings.animate, detail: Strings.Settings.animateDetail, key: .animationsEnabled)
                SliderRow(
                    model: model,
                    title: Strings.Settings.duration,
                    detail: Strings.Settings.durationDetail,
                    key: .animationsDuration,
                    range: AnimationsConfig.durationRange,
                    step: 10,
                    unit: Strings.Settings.millisecondsUnit,
                )
                .disabled(!model.bool(.animationsEnabled))
            }
            Section(Strings.Settings.workspaces) {
                pickerRow(
                    model,
                    Strings.Settings.workspaceSwitch,
                    detail: workspaceSwitchDetail,
                    key: .animationsWorkspaceSwitch,
                    options: [
                        (WorkspaceSwitch.horizontal.rawValue, Strings.Settings.horizontal),
                        (WorkspaceSwitch.vertical.rawValue, Strings.Settings.vertical),
                        (WorkspaceSwitch.auto.rawValue, Strings.Settings.auto),
                        (WorkspaceSwitch.off.rawValue, Strings.Settings.off),
                    ],
                )
                .disabled(!model.bool(.animationsEnabled))
            }
        }
    }

    private var workspaceSwitchDetail: String {
        switch WorkspaceSwitch(rawValue: model.string(.animationsWorkspaceSwitch)) {
            case .vertical: Strings.Settings.workspaceSwitchVerticalDetail
            case .auto: Strings.Settings.workspaceSwitchAutoDetail
            case .off: Strings.Settings.workspaceSwitchOffDetail
            case .horizontal, nil: Strings.Settings.workspaceSwitchHorizontalDetail
        }
    }
}

// MARK: - The menu bar item, drawn for the window

/// The item as Inlay draws it, for a dark or a light menu bar. See: MenuBarSamples.image
private struct MenuBarItemImage: View {
    let config: MenuBarConfig
    var snapshot: MenuBarSnapshot = MenuBarSamples.snapshot
    let isDarkBar: Bool
    let zoom: CGFloat

    var body: some View {
        if let image = MenuBarSamples.image(config, snapshot: snapshot, isDarkBar: isDarkBar, scale: 2 * max(1, zoom)) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * zoom, height: image.size.height * zoom)
        }
    }
}

/// A dark or a light menu bar, behind the item
private func menuBarBackground(_ isDarkBar: Bool) -> LinearGradient {
    let colors = isDarkBar
        ? [Color(red: 0.21, green: 0.24, blue: 0.33), Color(red: 0.27, green: 0.27, blue: 0.42)]
        : [Color(red: 0.93, green: 0.93, blue: 0.94), Color(red: 0.87, green: 0.87, blue: 0.89)]
    return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
}

/// The style of the indicator: a pop-up button whose items show each theme as Inlay draws it, over a small menu bar,
/// next to its name. The closed button shows the chosen one the same way. The thumbnails take the colors and the
/// options of the item
private struct MenuBarThemePopUp: NSViewRepresentable {
    let theme: MenuBarTheme
    let config: MenuBarConfig
    let select: (MenuBarTheme) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        button.imagePosition = .imageLeading
        button.setAccessibilityLabel(Strings.Settings.style)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.select = select
        let isDarkBar = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // The thumbnails only depend on the rest of the item and on the appearance: made again when one changes
        let thumbnails = Coordinator.Thumbnails(config: config.copy(\.theme, MenuBarConfig().theme), isDarkBar: isDarkBar)
        if context.coordinator.thumbnails != thumbnails {
            context.coordinator.thumbnails = thumbnails
            button.removeAllItems()
            for theme in MenuBarTheme.allCases {
                let title = theme == MenuBarConfig().theme ? "\(theme.rawValue) · \(Strings.Settings.defaultValue)" : theme.rawValue
                button.addItem(withTitle: title)
                button.lastItem?.image = MenuBarSamples.thumbnail(config.copy(\.theme, theme), isDarkBar: isDarkBar)
            }
        }
        button.selectItem(at: MenuBarTheme.allCases.firstIndex(of: theme) ?? 0)
    }

    @MainActor
    final class Coordinator: NSObject {
        struct Thumbnails: Equatable {
            var config: MenuBarConfig
            var isDarkBar: Bool
        }

        var select: ((MenuBarTheme) -> Void)?
        var thumbnails: Thumbnails?

        @objc func picked(_ sender: NSPopUpButton) {
            guard let theme = MenuBarTheme.allCases.getOrNil(atIndex: sender.indexOfSelectedItem) else { return }
            select?(theme)
        }
    }
}

// MARK: - Menu bar

/// The menu bar item: its theme, its options and its colors
struct MenuBarSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            Section {
                SettingsRow(model: model, title: Strings.Settings.style, key: .menuBarTheme) {
                    MenuBarThemePopUp(theme: model.menuBarTheme, config: model.menuBarConfig) { model.setTheme($0) }
                        .fixedSize()
                }
                // The item as Inlay draws it, with the colors below: over a dark and over a light menu bar
                HStack(spacing: 10) {
                    ForEach([true, false], id: \.self) { isDarkBar in
                        MenuBarItemImage(config: MenuBarSamples.withSampleLabels(model.menuBarConfig), isDarkBar: isDarkBar, zoom: 1.4)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(menuBarBackground(isDarkBar), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Strings.Settings.livePreview)
                ToggleRow(model: model, title: Strings.Settings.dimEmpty, detail: Strings.Settings.dimEmptyDetail, key: .menuBarDimEmpty)
                ToggleRow(model: model, title: Strings.Settings.showMode, detail: Strings.Settings.showModeDetail, key: .menuBarShowMode)
                ToggleRow(model: model, title: Strings.Settings.perMonitor, detail: Strings.Settings.perMonitorDetail, key: .menuBarPerMonitor)
            } header: {
                Text(Strings.Settings.workspaceIndicator)
            }
            if model.menuBarTheme == .labels {
                Section {
                    ForEach(model.labelWorkspaces, id: \.self) { workspace in
                        LabelRow(model: model, workspace: workspace)
                    }
                    if model.labelWorkspaces.isEmpty {
                        Text(Strings.Settings.noPersistentWorkspaces).foregroundStyle(.secondary)
                    }
                } header: {
                    HStack(spacing: 8) {
                        Text(Strings.Settings.labels)
                        Text("[menu-bar.labels] [menu-bar.symbols]")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    footnote(Strings.Settings.labelsFooter)
                }
            }
            Section {
                ToggleRow(model: model, title: Strings.Settings.systemColors, detail: Strings.Settings.systemColorsDetail, key: .menuBarSystemColors)
                // Overridden while the item takes the colors of the menu bar, but kept: they apply again when it's off
                Group {
                    ColorRow(model: model, title: Strings.Settings.activeWorkspaceColor, key: .menuBarFocused, allowsAuto: true)
                    ColorRow(model: model, title: Strings.Settings.inactiveWorkspaceColor, key: .menuBarOccupied, allowsAuto: true)
                    ColorRow(model: model, title: Strings.Settings.emptyWorkspaceColor, key: .menuBarEmpty, allowsAuto: true)
                    ColorRow(model: model, title: Strings.Settings.accent, detail: Strings.Settings.accentDetail, key: .menuBarAccent, allowsAuto: true)
                }
                .disabled(model.bool(.menuBarSystemColors))
            } header: {
                tableHeader(Strings.Settings.indicatorColors, SettingsKey.menuBarFocused)
            } footer: {
                footnote(Strings.Settings.indicatorColorsFooter)
            }
        }
    }
}

/// The borders of the windows: their shape, their colors, and the colors of the binding modes
struct BordersSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            BordersSections(model: model)
        }
    }
}

/// The name and the symbol of a workspace in the 'labels' theme. An empty field removes its key
private struct LabelRow: View {
    let model: SettingsModel
    let workspace: String

    /// Symbols that fit the usual workspaces
    private static let suggestions = [
        "terminal", "chevron.left.forwardslash.chevron.right", "globe", "bubble.left", "sparkles", "envelope", "music.note",
        "doc.text", "folder", "paintbrush", "gamecontroller", "film", "calendar", "checklist", "square.grid.2x2", "star",
    ]

    var body: some View {
        let labelKey = SettingsKey.menuBarLabel(workspace)
        let symbolKey = SettingsKey.menuBarSymbol(workspace)
        let symbol = model.string(symbolKey)
        let isValid = symbol.isEmpty || NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
        LabeledContent {
            HStack(spacing: 6) {
                TextField("", text: Binding(get: { model.string(labelKey) }, set: { model.setDebounced(labelKey, .string($0)) }), prompt: Text(Strings.Settings.labelPlaceholder(workspace)))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .frame(width: 130)
                    .disabled(model.disabledReason(labelKey) != nil)
                Image(systemName: symbol.isEmpty ? "square.dashed" : isValid ? symbol : "questionmark.square.dashed")
                    .frame(width: 20)
                    .foregroundStyle(symbol.isEmpty ? Color.secondary : isValid ? Color.primary : Color.orange)
                    .help(isValid ? symbol : Strings.Settings.unknownSymbol(symbol))
                TextField("", text: Binding(get: { symbol }, set: { model.setDebounced(symbolKey, .string($0)) }), prompt: Text(Strings.Settings.symbolPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(width: 170)
                    .disabled(model.disabledReason(symbolKey) != nil)
                Menu {
                    ForEach(Self.suggestions, id: \.self) { name in
                        Button { model.set(symbolKey, .string(name)) } label: { Label(name, systemImage: name) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help(Strings.Settings.suggestedSymbols)
            }
        } label: {
            Text(workspace).font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}

/// The [borders] table: the shape of the borders, their colors, and the colors of the binding modes
private struct BordersSections: View {
    let model: SettingsModel

    var body: some View {
        Group {
            Section {
                ToggleRow(model: model, title: Strings.Settings.showBorders, key: .bordersEnabled)
                SliderRow(model: model, title: Strings.Settings.width, key: .bordersWidth, range: BordersConfig.widthRange)
                ToggleRow(model: model, title: Strings.Settings.squareCorners, detail: Strings.Settings.squareCornersDetail, key: .bordersSquareCorners)
                SliderRow(
                    model: model,
                    title: Strings.Settings.cornerRadius,
                    detail: model.bool(.bordersSquareCorners) ? Strings.Settings.squareCornersRadiusDetail : Strings.Settings.cornerRadiusDetail,
                    key: .bordersCornerRadius,
                    range: BordersConfig.cornerRadiusRange,
                )
                ToggleRow(model: model, title: Strings.Settings.glow, detail: Strings.Settings.glowDetail, key: .bordersGlow)
                SliderRow(model: model, title: Strings.Settings.glowRadius, key: .bordersGlowRadius, range: BordersConfig.glowRadiusRange)
                    .disabled(!model.bool(.bordersGlow))
            } header: {
                Text(Strings.Settings.windowBorders)
            }
            Section {
                ToggleRow(model: model, title: Strings.Settings.singleWindowBorder, detail: Strings.Settings.singleWindowBorderDetail, key: .bordersSingleEnabled)
                SliderRow(model: model, title: Strings.Settings.width, key: .bordersSingleWidth, range: BordersConfig.widthRange, showsTable: false)
                    .disabled(!model.bool(.bordersSingleEnabled))
                SliderRow(model: model, title: Strings.Settings.singleWindowGap, detail: Strings.Settings.singleWindowGapDetail, key: .bordersSingleGap, range: SingleWindowBorder.gapRange, showsTable: false)
                    .disabled(!model.bool(.bordersSingleEnabled))
            } header: {
                tableHeader(Strings.Settings.singleWindow, SettingsKey.bordersSingleEnabled)
            } footer: {
                footnote(Strings.Settings.singleWindowFooter)
            }
            Section {
                ColorRow(model: model, title: Strings.Settings.activeWindow, key: .bordersActiveColor, allowsAuto: false)
                ColorRow(model: model, title: Strings.Settings.inactiveWindows, key: .bordersInactiveColor, allowsAuto: false)
                ColorRow(model: model, title: Strings.Settings.floatingWindow, key: .bordersFloatingColor, allowsAuto: false)
            } header: {
                tableHeader(Strings.Settings.borderColors, SettingsKey.bordersActiveColor)
            }
            Section {
                // One row per binding mode of the config file. See: SettingsModel.colorableModes
                ForEach(model.colorableModes, id: \.self) { mode in
                    ModeColorRow(model: model, mode: mode)
                }
                if model.colorableModes.isEmpty {
                    Text(Strings.Settings.noModes).foregroundStyle(.secondary)
                }
            } header: {
                tableHeader(Strings.Settings.modeColors, SettingsKey.bordersModeColor(""))
            } footer: {
                footnote(Strings.Settings.modeColorsFooter)
            }
        }
    }
}

/// The [gaps] table: the room between the windows, and between the windows and the edges of the screen
private struct GapsSections: View {
    let model: SettingsModel

    var body: some View {
        Group {
            Section {
                gapRow(Strings.Settings.horizontal, detail: Strings.Settings.horizontalGapDetail, .gapsInnerHorizontal)
                gapRow(Strings.Settings.vertical, detail: Strings.Settings.verticalGapDetail, .gapsInnerVertical)
            } header: {
                tableHeader(Strings.Settings.innerGaps, SettingsKey.gapsInnerHorizontal)
            } footer: {
                footnote(Strings.Settings.innerGapsFooter)
            }
            Section {
                gapRow(Strings.Settings.top, detail: Strings.Settings.topGapDetail, .gapsOuterTop)
                gapRow(Strings.Settings.bottom, .gapsOuterBottom)
                gapRow(Strings.Settings.left, .gapsOuterLeft)
                gapRow(Strings.Settings.right, .gapsOuterRight)
            } header: {
                tableHeader(Strings.Settings.outerGaps, SettingsKey.gapsOuterTop)
            } footer: {
                footnote(Strings.Settings.outerGapsFooter)
            }
        }
    }

    private func gapRow(_ title: String, detail: String? = nil, _ key: SettingsKey) -> some View {
        SliderRow(model: model, title: title, detail: detail, key: key, range: Gaps.settingsRange, showsTable: false)
    }
}

/// The note under a section
private func footnote(_ text: String) -> some View {
    Text(text)
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
}

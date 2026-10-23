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
        .settingsHighlight(model, title)
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

extension View {
    /// The row that a search of the sidebar led to stands out for a moment. See: SettingsModel.highlightedTitle
    @MainActor
    func settingsHighlight(_ model: SettingsModel, _ title: String) -> some View {
        background {
            if model.highlightedTitle == title {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(0.18))
                    .padding(-4)
            }
        }
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
    /// For a key without a default value: the key whose color is in effect while this one isn't set
    var fallback: SettingsKey? = nil

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key, showsTable: false) {
            if themeColor != nil {
                SourceBadge(isCustom: !isFromTheme)
            }
            Text(isFromTheme ? model.palette.title : isUnset ? Strings.Settings.notSet : model.string(key))
                .font(.system(size: 12, design: isFromTheme ? .default : .monospaced))
                .foregroundStyle(isFromTheme ? .secondary : .primary)
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
            if themeColor == nil {
                Button(Strings.Settings.reset) { model.reset(key) }
                    .buttonStyle(.link)
                    .disabled(!model.isSet(key))
            } else {
                // Only a color of the user's own can go back to the theme. The same width either way: the rows line up
                Button(Strings.Settings.useTheme) { model.reset(key) }
                    .buttonStyle(.link)
                    .opacity(isFromTheme ? 0 : 1)
                    .disabled(isFromTheme)
                    .accessibilityHidden(isFromTheme)
            }
        }
    }

    private var isUnset: Bool { fallback != nil && !model.isSet(key) }

    /// The color that the palette gives to the key. nil without a palette, or for a key that it doesn't color
    private var themeColor: Rgba? { model.paletteColor(key) }

    /// The palette gives the color: the user hasn't set one of their own
    private var isFromTheme: Bool { themeColor != nil && !model.manualColorKeys.contains(key) }

    /// The color of the palette, or 'auto' as the color of the text of a dark menu bar
    private var rgba: Rgba {
        if isFromTheme, let themeColor { return themeColor }
        return model.color(isUnset ? fallback ?? key : key).resolve(auto: .white, systemAccent: .systemAccent)
    }

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

    /// The color of the active border: the one of the palette, or the one of the config
    private var inherited: Rgba {
        model.paletteColor(.bordersActiveColor) ?? model.color(.bordersActiveColor).resolve(auto: .white, systemAccent: .systemAccent)
    }

    private var selection: Binding<Color> {
        Binding(
            get: { Color(nsColor: model.color(key).resolve(auto: .white, systemAccent: .systemAccent).nsColor) },
            set: { color in model.setDebounced(key, .string(Rgba(NSColor(color)).hex)) },
        )
    }
}

/// Where a color comes from: the theme (the palette), or the user ("Custom")
private struct SourceBadge: View {
    let isCustom: Bool

    var body: some View {
        Text(isCustom ? Strings.Settings.customBadge : Strings.Settings.themeBadge)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(isCustom ? Color.orange : Color.secondary)
            .background((isCustom ? Color.orange : Color.secondary).opacity(0.14), in: Capsule())
            .accessibilityLabel(isCustom ? Strings.Settings.customBadge : Strings.Settings.themeBadge)
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
                ToggleRow(model: model, title: Strings.Settings.autoReload, detail: Strings.Settings.autoReloadDetail, key: .autoReloadConfig)
                pickerRow(
                    model,
                    Strings.Settings.reloadNotice,
                    detail: Strings.Settings.reloadNoticeDetail,
                    key: .notificationsOnReload,
                    options: [
                        (ReloadNoticeStyle.diff.rawValue, Strings.Settings.reloadNoticeDiff),
                        (ReloadNoticeStyle.simple.rawValue, Strings.Settings.reloadNoticeSimple),
                        (ReloadNoticeStyle.off.rawValue, Strings.Settings.off),
                    ],
                )
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
                .settingsHighlight(model, Strings.Settings.export)
            }
            Section(Strings.Settings.menuBar) {
                ToggleRow(model: model, title: Strings.Settings.showItem, detail: Strings.Settings.showItemDetail, key: .menuBarEnabled)
            }
            Section(Strings.Settings.thisWindow) {
                ToggleRow(model: model, title: Strings.Settings.showKeys, detail: Strings.Settings.showKeysDetail, key: .settingsShowKeys)
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

// MARK: - Tiling

struct TilingSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
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

// MARK: - Animations

struct AnimationsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            Section(Strings.Settings.windows) {
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

// MARK: - Themes

/// The look of the item and of the borders: the style of the workspace indicator ([menu-bar] theme) and the palette
/// of colors ([theme] palette)
struct ThemesSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            // What it looks like, and where the colors come from: on top of every section
            Section {
                ThemePreview(model: model)
            }
            Section {
                Picker("", selection: Binding(get: { model.themesSection }, set: { section in
                    model.themesSection = section
                    // The page grows or shrinks under the picker: the new part is read from its top
                    NotificationCenter.default.post(name: .settingsPageScrollToTop, object: nil)
                })) {
                    Text(Strings.Settings.paletteSection).tag(ThemesSection.palette)
                    Text(Strings.Settings.indicatorSection).tag(ThemesSection.indicator)
                    Text(Strings.Settings.colorsSection).tag(ThemesSection.colors)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            switch model.themesSection {
                case .palette: paletteSection
                case .indicator: indicatorSection
                case .colors: colorsSection
            }
        }
        // A new form for each part: the scroll position of the form of the previous part doesn't carry over
        .id(model.themesSection)
    }

    // MARK: Palette

    @ViewBuilder
    private var paletteSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                PaletteTile(
                    model: model,
                    palette: .system,
                    title: Strings.Settings.systemPalette,
                    isSelected: model.palette == .system,
                    isBase: false,
                ) { pick(.system) }
                PaletteTile(
                    model: model,
                    palette: .material,
                    title: Strings.Settings.materialFromWallpaper,
                    isSelected: model.palette == .material && seedIsWallpaper && !model.hasCustomColors,
                    isBase: model.palette == .material && seedIsWallpaper && model.hasCustomColors,
                ) { pick(.material, seed: ThemeSeed.wallpaperLiteral) }
                PaletteTile(
                    model: model,
                    palette: .material,
                    title: Strings.Settings.materialFromColor,
                    isSelected: model.palette == .material && !seedIsWallpaper && !model.hasCustomColors,
                    isBase: model.palette == .material && !seedIsWallpaper && model.hasCustomColors,
                ) { pick(.material, seed: seedIsWallpaper ? MaterialPalette.baselineSeed.hex : nil) }
            }
            .disabled(model.disabledReason(.themePalette) != nil)
            if model.palette == .material {
                if seedIsWallpaper {
                    Text(Strings.Settings.seedFromWallpaperDetail(WallpaperSeed.shared.color?.hex))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ColorRow(model: model, title: Strings.Settings.seed, detail: Strings.Settings.seedDetail, key: .themeSeed, allowsAuto: false)
                }
            }
        } header: {
            Text(Strings.Settings.madeForYou)
        }
        Section {
            // Two rows at a time: the others scroll, inside of the section
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    TileGrid(items: ThemePalette.allCases.filter { $0 != .system && $0 != .material }, columns: 4) { palette in
                        PaletteTile(
                            model: model,
                            palette: palette,
                            title: palette.title,
                            isSelected: model.palette == palette && !model.hasCustomColors,
                            isBase: model.palette == palette && model.hasCustomColors,
                        ) { pick(palette) }
                        .id(palette)
                    }
                    .padding(.trailing, 10)
                }
                .scrollIndicators(.visible)
                .frame(height: 2 * PaletteTile.height + 8)
                // The palette in use is in sight when the part opens
                .onAppear { proxy.scrollTo(model.palette, anchor: .center) }
            }
            .disabled(model.disabledReason(.themePalette) != nil)
        } header: {
            tableHeader(Strings.Settings.palettes, SettingsKey.themePalette)
        } footer: {
            footnote(Strings.Settings.paletteFooter)
        }
    }

    private var seedIsWallpaper: Bool { model.string(.themeSeed) == ThemeSeed.wallpaperLiteral }

    // MARK: Indicator

    @ViewBuilder
    private var indicatorSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(MenuBarTheme.allCases, id: \.self) { theme in
                    styleButton(theme)
                }
            }
            .disabled(model.disabledReason(.menuBarTheme) != nil)
            if let reason = model.disabledReason(.menuBarTheme), model.unavailableReason == nil {
                Text(reason).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text(Strings.Settings.workspaceIndicator)
        } footer: {
            footnote(Strings.Settings.indicatorShapeFooter)
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
        Section(Strings.Settings.options) {
            ToggleRow(model: model, title: Strings.Settings.dimEmpty, detail: Strings.Settings.dimEmptyDetail, key: .menuBarDimEmpty)
            ToggleRow(model: model, title: Strings.Settings.showMode, detail: Strings.Settings.showModeDetail, key: .menuBarShowMode)
            ToggleRow(model: model, title: Strings.Settings.perMonitor, detail: Strings.Settings.perMonitorDetail, key: .menuBarPerMonitor)
        }
    }

    // MARK: Colors

    @ViewBuilder
    private var colorsSection: some View {
        Section {
            ColorRow(model: model, title: Strings.Settings.activeWorkspaceColor, key: .menuBarFocused, allowsAuto: true)
            ColorRow(model: model, title: Strings.Settings.inactiveWorkspaceColor, key: .menuBarOccupied, allowsAuto: true)
            ColorRow(model: model, title: Strings.Settings.emptyWorkspaceColor, key: .menuBarEmpty, allowsAuto: true)
            ColorRow(model: model, title: Strings.Settings.accent, detail: Strings.Settings.accentDetail, key: .menuBarAccent, allowsAuto: true)
        } header: {
            tableHeader(Strings.Settings.indicatorColors, SettingsKey.menuBarFocused)
        }
        Section {
            ColorRow(model: model, title: Strings.Settings.activeWindow, key: .bordersActiveColor, allowsAuto: false)
            ColorRow(model: model, title: Strings.Settings.inactiveWindows, key: .bordersInactiveColor, allowsAuto: false)
            ColorRow(model: model, title: Strings.Settings.floatingWindow, key: .bordersFloatingColor, allowsAuto: false)
        } header: {
            tableHeader(Strings.Settings.borderColors, SettingsKey.bordersActiveColor)
        } footer: {
            footnote(Strings.Settings.indicatorColorsFooter)
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Picking a theme while some colors are the user's own asks first: the theme takes them over
    /// - Parameter seed: also writes [theme] seed (Material You)
    private func pick(_ palette: ThemePalette, seed: String? = nil) {
        model.hoveredPalette = nil
        let manual = model.manualColorKeys
        guard palette != .system, !manual.isEmpty else {
            model.setPalette(palette, seed: seed, resettingColors: false)
            return
        }
        let alert = NSAlert()
        alert.messageText = Strings.Settings.replaceCustomTitle(palette.title)
        alert.informativeText = Strings.Settings.replaceCustomDetail(manual.map(Strings.Settings.colorName))
        alert.addButton(withTitle: Strings.Settings.useTheme)
        alert.addButton(withTitle: Strings.Settings.keepCustom)
        if alert.runModal() == .alertFirstButtonReturn {
            model.setPalette(palette, seed: seed, resettingColors: true)
        }
    }

    private func styleButton(_ theme: MenuBarTheme) -> some View {
        let isSelected = model.menuBarTheme == theme
        let config = MenuBarSamples.withSampleLabels(
            MenuBarConfig(theme: theme, labels: model.menuBarConfig.labels, symbols: model.menuBarConfig.symbols, palette: model.palette, paletteSeed: model.paletteSeed),
        )
        return Button {
            model.setTheme(theme)
        } label: {
            VStack(spacing: 6) {
                MenuBarItemImage(config: config, isDarkBar: true, zoom: 0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(menuBarBackground(true), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(theme == MenuBarConfig().theme ? "\(theme.rawValue) · \(Strings.Settings.defaultValue)" : theme.rawValue)
                    .font(.system(size: 11, design: .monospaced))
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Rows of tiles, all as wide. Not lazy: the rows after a lazy grid were reported out of their place once the page
/// was scrolled, and couldn't be clicked there. See: inspectSettingsWindow
private struct TileGrid<Item: Hashable, Tile: View>: View {
    let items: [Item]
    let columns: Int
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: columns)), id: \.self) { start in
                let row = Array(items[start ..< min(start + columns, items.count)])
                GridRow {
                    ForEach(row, id: \.self) { tile($0) }
                    ForEach(0 ..< columns - row.count, id: \.self) { _ in
                        Color.clear.frame(height: 1)
                    }
                }
            }
        }
    }
}

/// The colors of a palette, or of the config with a palette, in a variant: what the previews draw
@MainActor
private struct PreviewColors {
    var menuBar: MenuBarConfig
    var active: Rgba
    var inactive: Rgba
    var floating: Rgba

    /// - Parameter palette: the palette to show instead of the one of the config, without the colors of the user
    init(_ model: SettingsModel, palette: ThemePalette? = nil, isDark: Bool) {
        let palette = palette ?? model.palette
        let isOwn = palette == model.palette
        let borders = BordersConfig()
            .copy(\.activeColor, isOwn ? model.color(.bordersActiveColor) : BordersConfig().activeColor)
            .copy(\.inactiveColor, isOwn ? model.color(.bordersInactiveColor) : BordersConfig().inactiveColor)
            .copy(\.floatingColor, isOwn ? model.color(.bordersFloatingColor) : BordersConfig().floatingColor)
            .applying(palette, seed: model.paletteSeed, isDark: isDark)
        func resolve(_ color: ConfigColor) -> Rgba { color.resolve(auto: isDark ? .white : .black, systemAccent: .systemAccent) }
        menuBar = isOwn ? model.menuBarConfig : model.menuBarConfig.copy(\.colors, MenuBarColors()).copy(\.palette, palette)
        active = resolve(borders.activeColor)
        inactive = resolve(borders.inactiveColor)
        floating = resolve(borders.floatingColor)
    }
}

/// The item in the menu bar and three windows with their borders, in one variant of the palette, with where the
/// colors come from on top of it: green (a theme), orange (custom colors) or gray (no theme)
private struct ThemePreview: View {
    let model: SettingsModel

    var body: some View {
        let isDark = model.previewIsDark
        let hovered = model.hoveredPalette
        let colors = PreviewColors(model, palette: hovered, isDark: isDark)
        VStack(spacing: 0) {
            MenuBarItemImage(config: MenuBarSamples.withSampleLabels(colors.menuBar), isDarkBar: isDark, zoom: 1.6)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(menuBarBackground(isDark))
            HStack(spacing: 12) {
                ForEach(Array([colors.active, colors.inactive, colors.floating].enumerated()), id: \.offset) { _, border in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(white: isDark ? 0.13 : 0.97))
                        .frame(height: 64)
                        .padding(3)
                        .background(Color(nsColor: border.nsColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 44)
        }
        .background(desktop(isDark))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottom) { statusBar(hovered: hovered) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Strings.Settings.livePreview)
    }

    private func desktop(_ isDark: Bool) -> LinearGradient {
        let colors = isDark
            ? [Color(red: 0.18, green: 0.2, blue: 0.31), Color(red: 0.29, green: 0.26, blue: 0.45)]
            : [Color(red: 0.84, green: 0.86, blue: 0.92), Color(red: 0.93, green: 0.89, blue: 0.95)]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// The source of the colors, and the variant shown
    private func statusBar(hovered: ThemePalette?) -> some View {
        let manual = model.manualColorKeys
        let (color, title, detail): (Color, String, String) = switch true {
            case hovered != nil: (.accentColor, hovered?.title ?? "", Strings.Settings.previewOnly)
            case model.palette == .system: (.secondary, Strings.Settings.noThemeTitle, Strings.Settings.noThemeInUse)
            case manual.isEmpty: (.green, model.palette.title, Strings.Settings.themeInUseDetail)
            default: (.orange, Strings.Settings.custom, Strings.Settings.customInUse(manual.map(Strings.Settings.colorName), base: model.palette.title))
        }
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.black.opacity(0.45), in: Capsule())
            .foregroundStyle(.white)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(model.previewIsDark ? Color.white.opacity(0.85) : Color.black.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .help(detail)
            Spacer(minLength: 4)
            if hovered == nil, model.palette != .system, !manual.isEmpty {
                Button(Strings.Settings.resetToTheme) { model.resetManualColors() }
                    .controlSize(.small)
                    .help(Strings.Settings.useOnlyTheme(model.palette.title))
            }
            // Over a dark capsule, in the dark appearance: it reads the same over both variants of the preview
            Picker("", selection: Binding(get: { model.previewIsDark }, set: { model.previewVariantIsDark = $0 })) {
                Text(Strings.Settings.dark).tag(true)
                Text(Strings.Settings.light).tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .environment(\.colorScheme, .dark)
            .padding(3)
            .background(.black.opacity(0.45), in: Capsule())
            .help(Strings.Settings.variantHelp)
        }
        .padding(8)
        .accessibilityElement(children: .contain)
    }
}

/// A palette as a small desktop: its menu bar item and two windows with their borders. Hovering it shows it in the
/// preview, without writing it. Selected: the theme in use. Base (dashed): the palette that gives the colors the user
/// hasn't set, while no theme is selected
private struct PaletteTile: View {
    let model: SettingsModel
    let palette: ThemePalette
    let title: String
    let isSelected: Bool
    let isBase: Bool
    let action: () -> Void

    static let height: CGFloat = 86

    var body: some View {
        let isDark = model.previewIsDark
        let colors = PreviewColors(model, palette: palette, isDark: isDark)
        Button(action: action) {
            VStack(spacing: 5) {
                VStack(spacing: 0) {
                    MenuBarItemImage(config: MenuBarSamples.withSampleLabels(colors.menuBar), isDarkBar: isDark, zoom: 0.55)
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                        .background(menuBarBackground(isDark).opacity(0.9))
                    HStack(spacing: 4) {
                        window(colors.active)
                        window(colors.inactive)
                    }
                    .padding(5)
                }
                .background(isDark ? Color(white: 0.2) : Color(white: 0.88))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(isBase ? Strings.Settings.baseOf(title) : title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(5)
            .frame(height: Self.height)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : isBase ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isBase ? [4, 3] : []),
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isInside in
            if isInside {
                model.hoveredPalette = palette
            } else if model.hoveredPalette == palette {
                model.hoveredPalette = nil
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func window(_ border: Rgba) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color(white: model.previewIsDark ? 0.12 : 0.98))
            .frame(height: 24)
            .padding(2)
            .background(Color(nsColor: border.nsColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
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

// MARK: - Borders

/// Edits the [borders] table. See: SettingsFeatures.borders
struct BordersSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            Section {
                preview
            }
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
                ToggleRow(model: model, title: Strings.Settings.hideWhenSingle, detail: Strings.Settings.hideWhenSingleDetail, key: .bordersHideWhenSingle)
            } header: {
                Text(Strings.Settings.windowBorders)
            } footer: {
                Text(Strings.Settings.colorsInThemes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(Strings.Settings.modeColorsFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var preview: some View {
        let isEnabled = model.bool(.bordersEnabled)
        return HStack(spacing: 14) {
            window(Strings.Settings.active, isEnabled ? .bordersActiveColor : nil, glows: model.bool(.bordersGlow))
            window(Strings.Settings.inactive, isEnabled ? .bordersInactiveColor : nil)
            window(Strings.Settings.floatingPreview, isEnabled ? .bordersFloatingColor : nil)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.21, green: 0.24, blue: 0.33), Color(red: 0.27, green: 0.27, blue: 0.42)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
        )
    }

    /// A window with its border around it: the border is drawn outside of the frame of the window.
    /// With square corners the border is a plain rectangle, and it fills the rounded corners of the window
    private func window(_ title: String, _ colorKey: SettingsKey?, glows: Bool = false) -> some View {
        let width = CGFloat(model.int(.bordersWidth))
        let radius = CGFloat(model.int(.bordersCornerRadius))
        let outerRadius = model.bool(.bordersSquareCorners) ? 0 : radius + width
        let color = colorKey.map { Color(nsColor: model.color($0).resolve(auto: .white, systemAccent: .systemAccent).nsColor) } ?? .clear
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(white: 0.13))
            .frame(height: 90)
            .overlay { Text(title).font(.caption).foregroundStyle(.secondary) }
            .padding(width)
            .background(color, in: RoundedRectangle(cornerRadius: outerRadius, style: .continuous))
            // The blur radius of a SwiftUI shadow is a standard deviation: half of the one of the config
            .shadow(color: glows ? color : .clear, radius: CGFloat(model.int(.bordersGlowRadius)) / 2)
    }
}

// MARK: - Gaps

/// Edits the [gaps] table: the room between the windows, and between the windows and the edges of the screen
struct GapsSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            Section {
                preview
            }
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
            Section(Strings.Settings.singleWindow) {
                ToggleRow(model: model, title: Strings.Settings.smartGaps, detail: Strings.Settings.smartGapsDetail, key: .gapsSmart)
            }
        }
    }

    private func gapRow(_ title: String, detail: String? = nil, _ key: SettingsKey) -> some View {
        SliderRow(model: model, title: title, detail: detail, key: key, range: Gaps.settingsRange, showsTable: false)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Three windows of a screen, with the gaps at their real size, and the borders as the Borders tab leaves them
    private var preview: some View {
        let gaps = (
            horizontal: CGFloat(model.int(.gapsInnerHorizontal)),
            vertical: CGFloat(model.int(.gapsInnerVertical)),
            top: CGFloat(model.int(.gapsOuterTop)),
            bottom: CGFloat(model.int(.gapsOuterBottom)),
            left: CGFloat(model.int(.gapsOuterLeft)),
            right: CGFloat(model.int(.gapsOuterRight)),
        )
        let borderWidth = model.bool(.bordersEnabled) ? CGFloat(model.int(.bordersWidth)) : 0
        let radius = CGFloat(model.int(.bordersCornerRadius))
        let squareCorners = model.bool(.bordersSquareCorners)
        let active = model.color(.bordersActiveColor).resolve(auto: .white, systemAccent: .systemAccent).nsColor
        let inactive = model.color(.bordersInactiveColor).resolve(auto: .white, systemAccent: .systemAccent).nsColor
        return Canvas { context, size in
            let area = CGRect(origin: .zero, size: size).inset(top: gaps.top, left: gaps.left, bottom: gaps.bottom, right: gaps.right)
            guard area.width > gaps.horizontal, area.height > gaps.vertical else { return }
            let leftWidth = ((area.width - gaps.horizontal) / 2).rounded()
            let topHeight = ((area.height - gaps.vertical) / 2).rounded()
            let rightX = area.minX + leftWidth + gaps.horizontal
            let windows: [(CGRect, NSColor)] = [
                (CGRect(x: area.minX, y: area.minY, width: leftWidth, height: area.height), active),
                (CGRect(x: rightX, y: area.minY, width: area.maxX - rightX, height: topHeight), inactive),
                (CGRect(x: rightX, y: area.minY + topHeight + gaps.vertical, width: area.maxX - rightX, height: area.height - topHeight - gaps.vertical), inactive),
            ]
            for (frame, color) in windows {
                let windowRadius = min(radius, frame.width / 2, frame.height / 2)
                if borderWidth > 0 {
                    // Outside of the window. With square corners, the corners that the window leaves empty keep the color of the border
                    let outerRadius = squareCorners ? 0 : windowRadius + borderWidth
                    let border = Path(roundedRect: frame.insetBy(dx: -borderWidth, dy: -borderWidth), cornerRadius: outerRadius, style: .continuous)
                    context.fill(border, with: .color(Color(nsColor: color)))
                }
                context.fill(Path(roundedRect: frame, cornerRadius: windowRadius, style: .continuous), with: .color(Color(white: 0.13)))
            }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(colors: [Color(red: 0.21, green: 0.24, blue: 0.33), Color(red: 0.27, green: 0.27, blue: 0.42)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Text(Strings.Settings.actualSize).font(.caption2).foregroundStyle(.white.opacity(0.6)).padding(6)
        }
        .accessibilityLabel(Strings.Settings.actualSize)
    }
}

extension CGRect {
    fileprivate func inset(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) -> CGRect {
        CGRect(x: minX + left, y: minY + top, width: max(0, width - left - right), height: max(0, height - top - bottom))
    }
}

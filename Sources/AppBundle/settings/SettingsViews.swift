import AppKit
import Common
import SwiftUI

private let settingsWidth: CGFloat = 600

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
        LabeledContent {
            HStack(spacing: 10) {
                // The window and the file are the same thing: every row shows the key it writes
                Text(showsTable ? key.label : key.path.key)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
                control().disabled(disabledReason != nil)
            }
        } label: {
            Text(title)
            if let text = disabledReason ?? detail { Text(text) }
        }
    }
}

private struct ToggleRow: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey
    /// The value to show, when it isn't just the one of the key
    var value: Bool? = nil

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key) {
            Toggle("", isOn: Binding(get: { value ?? model.bool(key) }, set: { model.set(key, .bool($0)) }))
                .labelsHidden()
                .toggleStyle(.switch)
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

    /// 'auto' is shown as the color of the text of a dark menu bar
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

private struct ErrorBanner: View {
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

// MARK: - General

struct GeneralSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            ErrorBanner(model: model)
            Section(Strings.Settings.startup) {
                ToggleRow(model: model, title: Strings.Settings.startAtLogin, detail: Strings.Settings.startAtLoginDetail, key: .startAtLogin)
            }
            Section(Strings.Settings.tiling) {
                let isDwindle = model.string(.newWindowPlacement) == NewWindowPlacement.dwindle.rawValue
                pickerRow(
                    Strings.Settings.placement,
                    detail: isDwindle ? Strings.Settings.placementDwindleDetail : Strings.Settings.placementAfterFocusedDetail,
                    key: .newWindowPlacement,
                    options: [
                        (NewWindowPlacement.dwindle.rawValue, Strings.Settings.dwindle),
                        (NewWindowPlacement.afterFocused.rawValue, Strings.Settings.afterFocused),
                    ],
                )
                pickerRow(
                    Strings.Settings.startupLayout,
                    detail: startupLayoutDetail,
                    key: .startupLayout,
                    options: [
                        (StartupLayout.grid.rawValue, Strings.Settings.grid),
                        (StartupLayout.row.rawValue, Strings.Settings.row),
                        (StartupLayout.dwindle.rawValue, Strings.Settings.dwindle),
                    ],
                )
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// A key with a few possible values, as a segmented control
    private func pickerRow(_ title: String, detail: String, key: SettingsKey, options: [(value: String, title: String)]) -> some View {
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

    private var startupLayoutDetail: String {
        switch StartupLayout(rawValue: model.string(.startupLayout)) {
            case .row: Strings.Settings.startupRowDetail
            case .dwindle: Strings.Settings.startupDwindleDetail
            case .grid, nil: Strings.Settings.startupGridDetail
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

// MARK: - Menu bar

struct MenuBarSettingsView: View {
    let model: SettingsModel
    let icons: AppIconCache

    var body: some View {
        Form {
            ErrorBanner(model: model)
            Section {
                preview
            }
            Section(Strings.Settings.theme) {
                HStack(spacing: 8) {
                    ForEach(MenuBarTheme.allCases, id: \.self) { theme in
                        themeButton(theme)
                    }
                }
                .disabled(model.disabledReason(.menuBarTheme) != nil)
                if let reason = model.disabledReason(.menuBarTheme), model.unavailableReason == nil {
                    Text(reason).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section(Strings.Settings.options) {
                ToggleRow(model: model, title: Strings.Settings.showItem, detail: Strings.Settings.showItemDetail, key: .menuBarEnabled)
                ToggleRow(
                    model: model,
                    title: Strings.Settings.showAppIcons,
                    detail: Strings.Settings.showAppIconsDetail,
                    key: .menuBarShowAppIcons,
                    value: model.menuBarConfig.effectiveShowAppIcons,
                )
                ToggleRow(model: model, title: Strings.Settings.dimEmpty, detail: Strings.Settings.dimEmptyDetail, key: .menuBarDimEmpty)
                ToggleRow(model: model, title: Strings.Settings.showMode, detail: Strings.Settings.showModeDetail, key: .menuBarShowMode)
            }
            Section {
                ColorRow(model: model, title: Strings.Settings.accent, detail: Strings.Settings.accentDetail, key: .menuBarAccent, allowsAuto: false)
                ColorRow(model: model, title: Strings.Settings.focused, key: .menuBarFocused, allowsAuto: true)
                ColorRow(model: model, title: Strings.Settings.occupied, key: .menuBarOccupied, allowsAuto: true)
                ColorRow(model: model, title: Strings.Settings.emptyColor, key: .menuBarEmpty, allowsAuto: true)
            } header: {
                tableHeader(Strings.Settings.colors, SettingsKey.menuBarFocused)
            } footer: {
                Text(Strings.Settings.colorsFooter)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The item as the window leaves it, in a dark and in a light menu bar: a fixed color doesn't adapt to the menu bar.
    /// The sample is in the 'resize' mode when the mode is shown, so the badge can be seen
    private var preview: some View {
        let config = model.menuBarConfig
        var snapshot = MenuBarSamples.snapshot
        if config.showMode { snapshot.mode = "resize" }
        return VStack(spacing: 0) {
            ForEach([true, false], id: \.self) { isDarkBar in
                item(config, snapshot, isDarkBar: isDarkBar, zoom: 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(barBackground(isDarkBar))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(Strings.Settings.livePreview).font(.caption2).foregroundStyle(.white.opacity(0.6)).padding(6)
        }
        .accessibilityLabel(Strings.Settings.livePreview)
    }

    private func themeButton(_ theme: MenuBarTheme) -> some View {
        let isSelected = model.menuBarTheme == theme
        return Button {
            model.setTheme(theme)
        } label: {
            VStack(spacing: 6) {
                item(MenuBarConfig(theme: theme), MenuBarSamples.snapshot, isDarkBar: true, zoom: theme == .chipsIcons ? 0.5 : 0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .background(barBackground(true), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(theme.rawValue).font(.system(size: 11, design: .monospaced))
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

    @ViewBuilder
    private func item(_ config: MenuBarConfig, _ snapshot: MenuBarSnapshot, isDarkBar: Bool, zoom: CGFloat) -> some View {
        if let image = MenuBarSamples.image(config, snapshot: snapshot, isDarkBar: isDarkBar, scale: 2 * max(1, zoom), icons: icons.icon) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: image.size.width * zoom, height: image.size.height * zoom)
        }
    }

    private func barBackground(_ isDarkBar: Bool) -> LinearGradient {
        let colors = isDarkBar
            ? [Color(red: 0.21, green: 0.24, blue: 0.33), Color(red: 0.27, green: 0.27, blue: 0.42)]
            : [Color(red: 0.93, green: 0.93, blue: 0.94), Color(red: 0.87, green: 0.87, blue: 0.89)]
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }
}

// MARK: - Borders

/// Edits the [borders] table. See: SettingsFeatures.borders
struct BordersSettingsView: View {
    let model: SettingsModel

    var body: some View {
        Form {
            ErrorBanner(model: model)
            Section {
                preview
            }
            Section(Strings.Settings.windowBorders) {
                ToggleRow(model: model, title: Strings.Settings.showBorders, key: .bordersEnabled)
                sliderRow(Strings.Settings.width, key: .bordersWidth, range: 1 ... 20)
                sliderRow(Strings.Settings.cornerRadius, detail: Strings.Settings.cornerRadiusDetail, key: .bordersCornerRadius, range: 0 ... 40)
            }
            Section {
                ColorRow(model: model, title: Strings.Settings.activeWindow, key: .bordersActiveColor, allowsAuto: false)
                ColorRow(model: model, title: Strings.Settings.inactiveWindows, key: .bordersInactiveColor, allowsAuto: false)
                ColorRow(model: model, title: Strings.Settings.floatingWindow, key: .bordersFloatingColor, allowsAuto: false)
            } header: {
                tableHeader(Strings.Settings.colors, SettingsKey.bordersActiveColor)
            }
        }
        .formStyle(.grouped)
        .frame(width: settingsWidth)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The slider shows its value while it is dragged, and writes it when it is released
    private func sliderRow(_ title: String, detail: String? = nil, key: SettingsKey, range: ClosedRange<Double>) -> some View {
        SettingsRow(model: model, title: title, detail: detail, key: key) {
            Slider(
                value: Binding(get: { Double(model.int(key)) }, set: { model.preview(key, .int(Int($0.rounded()))) }),
                in: range,
                step: 1,
            ) { isEditing in
                if !isEditing { model.commit(key) }
            }
            .frame(width: 160)
            Text(Strings.Settings.points(model.int(key)))
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var preview: some View {
        let isEnabled = model.bool(.bordersEnabled)
        return HStack(spacing: 14) {
            window(Strings.Settings.active, isEnabled ? .bordersActiveColor : nil)
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

    /// A window with its border around it: the border is drawn outside of the frame of the window
    private func window(_ title: String, _ colorKey: SettingsKey?) -> some View {
        let width = CGFloat(model.int(.bordersWidth))
        let radius = CGFloat(model.int(.bordersCornerRadius))
        let color = colorKey.map { Color(nsColor: model.color($0).resolve(auto: .white, systemAccent: .systemAccent).nsColor) } ?? .clear
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(white: 0.13))
            .frame(height: 90)
            .overlay { Text(title).font(.caption).foregroundStyle(.secondary) }
            .padding(width)
            .background(color, in: RoundedRectangle(cornerRadius: radius + width, style: .continuous))
    }
}

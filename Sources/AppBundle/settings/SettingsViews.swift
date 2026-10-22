import AppKit
import Common
import SwiftUI

let settingsWidth: CGFloat = 600

/// The content of a tab: a form as tall as its rows. The window shows all of it, or scrolls it when the screen
/// is too small for that. See: SettingsPageController
private struct SettingsPage<Content: View>: View {
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

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key) {
            Toggle("", isOn: Binding(get: { model.bool(key) }, set: { model.set(key, .bool($0)) }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// A number of points. The slider shows its value while it is dragged, and writes it when it is released
private struct SliderRow: View {
    let model: SettingsModel
    let title: String
    var detail: String? = nil
    let key: SettingsKey
    let range: ClosedRange<Int>
    var step: Int = 1
    /// false: the header of the section already names the table of the key
    var showsTable: Bool = true
    /// The value as the slider shows it
    var format: (Int) -> String = Strings.Settings.points

    var body: some View {
        SettingsRow(model: model, title: title, detail: detail, key: key, showsTable: showsTable) {
            Slider(
                value: Binding(get: { Double(model.int(key)) }, set: { model.preview(key, .int(Int($0.rounded()))) }),
                in: Double(range.lowerBound) ... Double(range.upperBound),
                step: Double(step),
            ) { isEditing in
                if !isEditing { model.commit(key) }
            }
            .frame(width: 160)
            Text(format(model.int(key)))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
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
                    format: Strings.Settings.milliseconds,
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
                HStack(alignment: .top, spacing: 12) {
                    preview.frame(maxWidth: .infinity)
                    themeStatus.frame(width: 210)
                }
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
                chip(
                    Strings.Settings.systemPalette,
                    swatches: swatches(.system),
                    isSelected: model.palette == .system,
                    isBase: false,
                ) { pick(.system) }
                chip(
                    Strings.Settings.materialFromWallpaper,
                    swatches: swatches(.material),
                    isSelected: model.palette == .material && seedIsWallpaper && !model.hasCustomColors,
                    isBase: model.palette == .material && seedIsWallpaper && model.hasCustomColors,
                ) { pick(.material, seed: ThemeSeed.wallpaperLiteral) }
                chip(
                    Strings.Settings.materialFromColor,
                    swatches: swatches(.material),
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(ThemePalette.allCases.filter { $0 != .system && $0 != .material }, id: \.self) { palette in
                    chip(
                        palette.title,
                        swatches: swatches(palette),
                        isSelected: model.palette == palette && !model.hasCustomColors,
                        isBase: model.palette == palette && model.hasCustomColors,
                    ) { pick(palette) }
                }
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
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
        Section(Strings.Settings.options) {
            ToggleRow(model: model, title: Strings.Settings.dimEmpty, detail: Strings.Settings.dimEmptyDetail, key: .menuBarDimEmpty)
            ToggleRow(model: model, title: Strings.Settings.showMode, detail: Strings.Settings.showModeDetail, key: .menuBarShowMode)
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
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Where the colors come from: a theme, the user, or the system. Green, orange or gray, always on top
    private var themeStatus: some View {
        let manual = model.manualColorKeys
        let (color, symbol, title, detail): (Color, String, String, String) = switch true {
            case model.palette == .system:
                (.secondary, "circle.dashed", Strings.Settings.noThemeTitle, Strings.Settings.noThemeInUse)
            case manual.isEmpty:
                (.green, "checkmark.circle.fill", Strings.Settings.themeTitle(model.palette.title), Strings.Settings.themeInUseDetail)
            default:
                (.orange, "paintpalette.fill", Strings.Settings.custom, Strings.Settings.customInUse(manual.map(Strings.Settings.colorName), base: model.palette.title))
        }
        return VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.palette != .system && !manual.isEmpty {
                Button(Strings.Settings.useOnlyTheme(model.palette.title)) { model.resetManualColors() }
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Picking a theme while some colors are the user's own asks first: the theme takes them over
    /// - Parameter seed: also writes [theme] seed (Material You)
    private func pick(_ palette: ThemePalette, seed: String? = nil) {
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

    /// The item in a dark and in a light menu bar, and three windows with their borders in the colors of the appearance
    /// of the system
    private var preview: some View {
        let config = model.menuBarConfig
        let isDark = isSystemAppearanceDark
        let borders = BordersConfig()
            .copy(\.activeColor, model.color(.bordersActiveColor))
            .copy(\.inactiveColor, model.color(.bordersInactiveColor))
            .copy(\.floatingColor, model.color(.bordersFloatingColor))
            .applying(model.palette, seed: model.paletteSeed, isDark: isDark)
        func color(_ config: ConfigColor) -> Color { Color(nsColor: config.resolve(auto: .white, systemAccent: .systemAccent).nsColor) }
        let window = Color(white: isDark ? 0.13 : 0.96)
        return VStack(spacing: 10) {
            VStack(spacing: 0) {
                ForEach([true, false], id: \.self) { isDarkBar in
                    MenuBarItemImage(config: config, isDarkBar: isDarkBar, zoom: 1.6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(menuBarBackground(isDarkBar))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            HStack(spacing: 10) {
                ForEach(Array([borders.activeColor, borders.inactiveColor, borders.floatingColor].enumerated()), id: \.offset) { _, border in
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(window)
                        .frame(height: 56)
                        .padding(3)
                        .background(color(border), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
            }
        }
        .padding(12)
        .background(menuBarBackground(isDark).opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityLabel(Strings.Settings.livePreview)
    }

    private func styleButton(_ theme: MenuBarTheme) -> some View {
        let isSelected = model.menuBarTheme == theme
        return Button {
            model.setTheme(theme)
        } label: {
            VStack(spacing: 6) {
                MenuBarItemImage(config: MenuBarConfig(theme: theme, palette: model.palette, paletteSeed: model.paletteSeed), isDarkBar: true, zoom: 0.8)
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

    /// The colors of the palette in the appearance of the system: the focused workspace, the accent, the workspaces
    /// with windows, the inactive border
    private func swatches(_ palette: ThemePalette) -> [Color] {
        let isDark = isSystemAppearanceDark
        return switch palette.colors(isDark: isDark, seed: model.paletteSeed) {
            case let colors?: [colors.focused, colors.accent, colors.occupied, colors.inactiveBorder].map { Color(nsColor: $0.nsColor) }
            case nil: [Color.accentColor, isDark ? .white : .black, .gray, Color(nsColor: Rgba(hex: "#8E8E93").orDie().nsColor)]
        }
    }

    /// A palette as a small card. Selected: the theme in use. Base (dashed): the palette that gives the colors the user
    /// hasn't set, while no theme is selected
    private func chip(_ title: String, swatches: [Color], isSelected: Bool, isBase: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                HStack(spacing: 3) {
                    ForEach(Array(swatches.enumerated()), id: \.offset) { _, swatch in
                        Circle().fill(swatch).frame(width: 10, height: 10)
                            .overlay { Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5) }
                    }
                }
                Text(isBase ? Strings.Settings.baseOf(title) : title)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .padding(.horizontal, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : isBase ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.25),
                        style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isBase ? [4, 3] : []),
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Menu bar

struct MenuBarSettingsView: View {
    let model: SettingsModel

    var body: some View {
        SettingsPage {
            ErrorBanner(model: model)
            Section {
                preview
            }
            Section {
                ToggleRow(model: model, title: Strings.Settings.showItem, detail: Strings.Settings.showItemDetail, key: .menuBarEnabled)
            } header: {
                Text(Strings.Settings.options)
            } footer: {
                // The shape, its options and the colors are with the palette, in one place
                Text(Strings.Settings.indicatorInThemes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The item as the window leaves it, in a dark and in a light menu bar: a fixed color doesn't adapt to the menu bar.
    /// The sample is in the 'resize' mode when the mode is shown, so its initial can be seen in the marker
    private var preview: some View {
        let config = model.menuBarConfig
        var snapshot = MenuBarSamples.snapshot
        if config.showMode { snapshot.mode = "resize" }
        return VStack(spacing: 0) {
            ForEach([true, false], id: \.self) { isDarkBar in
                MenuBarItemImage(config: config, snapshot: snapshot, isDarkBar: isDarkBar, zoom: 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(menuBarBackground(isDarkBar))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text(Strings.Settings.livePreview).font(.caption2).foregroundStyle(.white.opacity(0.6)).padding(6)
        }
        .accessibilityLabel(Strings.Settings.livePreview)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Section {
                // One row per binding mode of the config file. See: SettingsModel.colorableModes
                ForEach(model.colorableModes, id: \.self) { mode in
                    ColorRow(model: model, title: mode, key: .bordersModeColor(mode), allowsAuto: false, fallback: .bordersActiveColor)
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

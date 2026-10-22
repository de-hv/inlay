import AppKit
import Common
import SwiftUI

let settingsSidebarWidth: CGFloat = 200

/// The first segment of the segmented controls that only change what the window shows, never the config: the parts of
/// Themes, the variant of its previews, the modes of Shortcuts. See: inspectSettingsWindow
@MainActor let windowOnlySegments: Set = [Strings.Settings.paletteSection, Strings.Settings.dark, mainModeId]

/// A row of a page that the search of the sidebar finds: by its title, its key or the title of its page
struct SettingsSearchEntry: Equatable {
    var page: SettingsPageID
    var title: String
    /// The key the row writes, as the row shows it
    var key: String = ""
    /// The part of Themes the row is in
    var themesSection: ThemesSection? = nil
}

@MainActor
enum SettingsSearch {
    static var entries: [SettingsSearchEntry] {
        typealias S = Strings.Settings
        func entry(_ page: SettingsPageID, _ title: String, _ key: SettingsKey? = nil, _ section: ThemesSection? = nil) -> SettingsSearchEntry {
            SettingsSearchEntry(page: page, title: title, key: key?.label ?? "", themesSection: section)
        }
        return [
            entry(.general, S.startAtLogin, .startAtLogin),
            entry(.general, S.autoReload, .autoReloadConfig),
            entry(.general, S.reloadNotice, .notificationsOnReload),
            entry(.general, S.export),
            entry(.general, S.showItem, .menuBarEnabled),
            entry(.general, S.showKeys, .settingsShowKeys),
            entry(.themes, S.palettes, .themePalette, .palette),
            entry(.themes, S.seed, .themeSeed, .palette),
            entry(.themes, S.wallpaper, .themeWallpaper, .palette),
            entry(.themes, S.hooks, nil, .palette),
            entry(.themes, S.workspaceIndicator, .menuBarTheme, .indicator),
            entry(.themes, S.labels, nil, .indicator),
            entry(.themes, S.dimEmpty, .menuBarDimEmpty, .indicator),
            entry(.themes, S.showMode, .menuBarShowMode, .indicator),
            entry(.themes, S.perMonitor, .menuBarPerMonitor, .indicator),
            entry(.themes, S.activeWorkspaceColor, .menuBarFocused, .colors),
            entry(.themes, S.inactiveWorkspaceColor, .menuBarOccupied, .colors),
            entry(.themes, S.emptyWorkspaceColor, .menuBarEmpty, .colors),
            entry(.themes, S.accent, .menuBarAccent, .colors),
            entry(.themes, S.activeWindow, .bordersActiveColor, .colors),
            entry(.themes, S.inactiveWindows, .bordersInactiveColor, .colors),
            entry(.themes, S.floatingWindow, .bordersFloatingColor, .colors),
            entry(.tiling, S.placement, .newWindowPlacement),
            entry(.tiling, S.splitTarget, .splitTarget),
            entry(.tiling, S.splitRatio, .splitRatio),
            entry(.tiling, S.startupLayout, .startupLayout),
            entry(.tiling, S.minWindowSize, .minWindowSize),
            entry(.gaps, S.horizontal, .gapsInnerHorizontal),
            entry(.gaps, S.vertical, .gapsInnerVertical),
            entry(.gaps, S.top, .gapsOuterTop),
            entry(.gaps, S.bottom, .gapsOuterBottom),
            entry(.gaps, S.left, .gapsOuterLeft),
            entry(.gaps, S.right, .gapsOuterRight),
            entry(.gaps, S.smartGaps, .gapsSmart),
            entry(.borders, S.showBorders, .bordersEnabled),
            entry(.borders, S.width, .bordersWidth),
            entry(.borders, S.squareCorners, .bordersSquareCorners),
            entry(.borders, S.cornerRadius, .bordersCornerRadius),
            entry(.borders, S.glow, .bordersGlow),
            entry(.borders, S.glowRadius, .bordersGlowRadius),
            entry(.borders, S.hideWhenSingle, .bordersHideWhenSingle),
            entry(.borders, S.modeColors, .bordersModeColor("")),
            entry(.animations, S.animate, .animationsEnabled),
            entry(.animations, S.duration, .animationsDuration),
            entry(.animations, S.workspaceSwitch, .animationsWorkspaceSwitch),
            entry(.workspaces, S.workspacesPage, .persistentWorkspaces),
            entry(.workspaces, S.floatingApps),
            entry(.shortcuts, S.shortcuts),
        ]
    }

    static func results(_ text: String) -> [SettingsSearchEntry] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            let haystack = [entry.title, entry.key, entry.page.title].joined(separator: " ").lowercased()
            return words.allSatisfy(haystack.contains)
        }
    }
}

/// The pages of the window, grouped like in System Settings, a search field over them, and the last change at the
/// bottom, with Undo
struct SettingsSidebar: View {
    let model: SettingsModel
    let select: (SettingsPageID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(Strings.Settings.search, text: Binding(get: { model.searchText }, set: { model.searchText = $0 }))
                    .textFieldStyle(.plain)
                if !model.searchText.isEmpty {
                    Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Strings.Settings.clearSearch)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if model.searchText.isEmpty { pages } else { results }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            changeBar
        }
        .frame(width: settingsSidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.035))
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var pages: some View {
        let groups: [String?] = [nil, Strings.Settings.windowsGroup, Strings.Settings.workflowGroup]
        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            if let group {
                Text(group)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 12)
                    .padding(.bottom, 3)
            }
            ForEach(SettingsPageID.allCases.filter { $0.group == group }, id: \.self) { page in
                pageRow(page)
            }
        }
    }

    private func pageRow(_ page: SettingsPageID) -> some View {
        let isSelected = model.page == page
        return Button { select(page) } label: {
            HStack(spacing: 8) {
                Image(systemName: page.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(nsColor: page.tint.nsColor), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(page.title).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var results: some View {
        let results = SettingsSearch.results(model.searchText)
        if results.isEmpty {
            Text(Strings.Settings.noResults)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(8)
        }
        ForEach(Array(results.enumerated()), id: \.offset) { _, result in
            Button { open(result) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title).font(.system(size: 12.5, weight: .medium))
                    Text(result.key.isEmpty ? result.page.title : "\(result.page.title) · \(result.key)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(model.highlightedTitle == result.title ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Goes to the page of the result and makes its row stand out for a moment
    private func open(_ result: SettingsSearchEntry) {
        if let section = result.themesSection { model.themesSection = section }
        select(result.page)
        model.highlightedTitle = result.title
        Task { @MainActor [model] in
            try? await Task.sleep(for: .seconds(2.5))
            if model.highlightedTitle == result.title { model.highlightedTitle = nil }
        }
    }

    /// The last change written by the window, and the buttons that undo and redo it
    @ViewBuilder
    private var changeBar: some View {
        if let change = model.undoStack.last ?? model.redoStack.last {
            VStack(alignment: .leading, spacing: 6) {
                Divider()
                Text(model.undoStack.isEmpty ? Strings.Settings.undone : Strings.Settings.lastChange)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(change.summary)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Button(Strings.Settings.undo) { model.undo() }
                        .disabled(model.undoStack.isEmpty)
                        .help("⌘Z")
                    Button(Strings.Settings.redo) { model.redo() }
                        .disabled(model.redoStack.isEmpty)
                        .help("⇧⌘Z")
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}

/// The sidebar on the leading side, and the pages next to it
final class SettingsRootViewController: NSViewController {
    let pages: SettingsTabViewController
    private let sidebar: NSView

    init(sidebar: NSView, pages: SettingsTabViewController) {
        self.sidebar = sidebar
        self.pages = pages
        super.init(nibName: nil, bundle: nil)
        addChild(pages)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let root = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        for view in [sidebar, separator, pages.view] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: settingsSidebarWidth),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            separator.topAnchor.constraint(equalTo: root.topAnchor),
            separator.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),
            pages.view.leadingAnchor.constraint(equalTo: separator.trailingAnchor),
            pages.view.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pages.view.topAnchor.constraint(equalTo: root.topAnchor),
            pages.view.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
    }
}

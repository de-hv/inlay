import AppKit
import Common
import SwiftUI

let renderSettingsFlag = "--render-settings"

/// `Inlay --render-settings <dir> [<config>]`: draws every tab of the Settings window off screen, the way the window
/// shows it once the Accessibility permission is granted and the config is loaded. A way to look at the window
/// without running Inlay.
///
/// The text of the config is the one of the shipped config, or the one of `config`. The config of the user is neither
/// read nor written: only its path is shown, the one a new config gets
@MainActor
func renderSettingsSamples(to directory: URL, config: URL?) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let text = try String(contentsOf: config ?? defaultConfigUrl, encoding: .utf8)
    // Always the dark appearance, whatever the one of this Mac is: the images don't depend on it
    NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    let url = newUserConfigUrl
    ServerState.shared.axPermissionStatus = .granted
    ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now.addingTimeInterval(-120), url: url, errorCount: 0, warningCount: 0, isApplied: true)
    let model = SettingsModel { .success(.init(url: url, text: text, exists: true)) }
    model.refresh()
    // The content of every page, the Themes page once per part of it
    let tabs: [(String, AnyView, ThemesSection)] = [
        ("general", AnyView(GeneralSettingsView(model: model)), .palette),
        ("themes", AnyView(ThemesSettingsView(model: model)), .palette),
        ("themes-indicator", AnyView(ThemesSettingsView(model: model)), .indicator),
        ("themes-colors", AnyView(ThemesSettingsView(model: model)), .colors),
        ("tiling", AnyView(TilingSettingsView(model: model)), .palette),
        ("gaps", AnyView(GapsSettingsView(model: model)), .palette),
        ("animations", AnyView(AnimationsSettingsView(model: model)), .palette),
        ("borders", AnyView(BordersSettingsView(model: model)), .palette),
        ("workspaces", AnyView(WorkspacesSettingsView(model: model)), .palette),
        ("shortcuts", AnyView(ShortcutsSettingsView(model: model)), .palette),
    ]
    for (name, view, section) in tabs {
        model.themesSection = section
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        try write(hosting, to: directory.appending(path: "settings-\(name).png"))
    }
    // The keys over the rows, as while ⌥ is held: nothing in the rows moves
    model.isOptionHeld = true
    let keys = NSHostingView(rootView: BordersSettingsView(model: model))
    let keysWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    keysWindow.contentView = keys
    keysWindow.setContentSize(keys.fittingSize)
    keys.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: .now.addingTimeInterval(0.2))
    try write(keys, to: directory.appending(path: "settings-borders-keys.png"))
    model.isOptionHeld = false

    // The whole window, with its sidebar, on every page: as tall as the page, whatever the screen
    model.themesSection = .palette
    let controller = SettingsWindowController(model: model)
    let window = controller.makeWindow(visibleFrame: { _ in CGRect(x: 0, y: 0, width: 4000, height: 4000) })
    for page in SettingsPageID.allCases {
        controller.select(page)
        RunLoop.current.run(until: .now.addingTimeInterval(0.4))
        guard let content = unsafe window.contentView else { continue }
        content.layoutSubtreeIfNeeded()
        try write(content, to: directory.appending(path: "settings-window-\(page.rawValue).png"))
    }
}

@MainActor
private func write(_ view: NSView, to url: URL) throws {
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try bitmap.representation(using: .png, properties: [:])?.write(to: url)
}

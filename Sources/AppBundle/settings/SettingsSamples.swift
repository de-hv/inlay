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
    _ = NSApplication.shared
    let url = newUserConfigUrl
    ServerState.shared.axPermissionStatus = .granted
    ServerState.shared.lastConfigLoad = ConfigLoadStatus(date: .now.addingTimeInterval(-120), url: url, errorCount: 0, warningCount: 0, isApplied: true)
    let model = SettingsModel { .success(.init(url: url, text: text, exists: true)) }
    model.refresh()
    let tabs: [(String, AnyView)] = [
        ("general", AnyView(GeneralSettingsView(model: model))),
        ("menu-bar", AnyView(MenuBarSettingsView(model: model, icons: AppIconCache()))),
        ("borders", AnyView(BordersSettingsView(model: model))),
    ]
    for (name, view) in tabs {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.2))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { continue }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "settings-\(name).png"))
    }
}

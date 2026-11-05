import AppKit
import Common
import Foundation

/// The key 'theme' of the config: a set of colors for the borders and the menu bar item, the ones of a theme that
/// Inlay ships with (themes/ of the repo, Resources/themes of the app) or of the user (themes/ of the config folder).
/// A theme is a Lua file that returns a table with the same shape as the config, with the look only:
///
///     return {
///       extends = 'nord',  -- optional: another theme, under this one
///       borders = { activeColor = …, inactiveColor = …, floatingColor = …, fullscreenColor = …, modeColors = { … },
///                   glow = …, glowRadius = … },
///       menuBar = { systemColors = …, colors = { focused = …, accent = …, occupied = …, empty = … } },
///     }
///
/// The value of the key is the name of a theme, a table like that one, or `{ dark = …, light = … }`: a theme for each
/// appearance of macOS. Without the key, the theme is 'material' (defaultThemeName). The values of the theme go under
/// the tables 'borders' and 'menuBar' of the config, so what the config writes wins, and what neither says keeps the
/// default of the code. `theme = {}`: no theme at all.
/// The wallpaper is not part of a theme: Inlay never reads it nor changes it
let themeKey = "theme"
let themesFolderName = "themes"
/// The theme of a config without the key 'theme'
let defaultThemeName = "material"

/// The borders and the menu bar for the light appearance of macOS, when 'theme' has a dark and a light theme
struct AppearanceColors: Equatable, Sendable {
    var borders: BordersConfig
    var menuBar: MenuBarConfig
}

/// The folder of the themes that Inlay ships with
var builtInThemesUrl: URL {
    // Only when it is needed: getDefaultConfigUrlFromProject() stops the app on a Mac without the sources of Inlay
    func fromProject() -> URL { getDefaultConfigUrlFromProject().deletingLastPathComponent().appending(component: themesFolderName) }
    if isUnitTest { return fromProject() }
    // Useful for debug builds that are not app bundles
    return Bundle.main.url(forResource: themesFolderName, withExtension: nil) ?? fromProject()
}

/// The names of the themes that Inlay ships with, sorted
var builtInThemeNames: [String] {
    let files = (try? FileManager.default.contentsOfDirectory(atPath: builtInThemesUrl.path)) ?? []
    return files.filter { $0.hasSuffix(".lua") }.map { String($0.dropLast(4)) }.sorted()
}

/// What 'theme' gives: the table of the theme for each appearance. nil: no theme (the defaults of the code)
struct ResolvedTheme {
    var dark: OrderedJson.JsonDict? = nil
    /// Only with `{ dark = …, light = … }`
    var light: OrderedJson.JsonDict? = nil
}

/// Reads the themes. It keeps the files of the config folder it reads or looks for: saving or creating one of them
/// reloads the config
struct ThemeResolver {
    /// The folder of the config. nil: a config without a folder, which only has the themes of Inlay
    let configFolder: URL?
    private(set) var files: [LuaConfigFile] = []

    /// A theme that extends another one that extends another one…
    private static let maxDepth = 8

    init(configFolder: URL?) { self.configFolder = configFolder }

    mutating func resolve(_ raw: OrderedJson, _ c: inout ConfigParserContext) -> ResolvedTheme {
        let backtrace = ConfigBacktrace.rootKey(themeKey)
        guard case .dict(let dict) = raw, dict["dark"] != nil || dict["light"] != nil else {
            return ResolvedTheme(dark: theme(raw, backtrace, place: nil, depth: 0, &c))
        }
        for key in dict.keys where key != "dark" && key != "light" {
            c.errors.append(.init(backtrace + .key(key), "A theme with 'dark' and 'light' has no other keys: write them in the theme of each appearance"))
        }
        guard let dark = dict["dark"], let light = dict["light"] else {
            c.errors.append(.init(backtrace, "'dark' and 'light' go together: the theme for each appearance of macOS"))
            return ResolvedTheme()
        }
        return ResolvedTheme(
            dark: theme(dark, backtrace + .key("dark"), place: nil, depth: 0, &c) ?? [:],
            light: theme(light, backtrace + .key("light"), place: nil, depth: 0, &c) ?? [:],
        )
    }

    /// The table of a theme: a name, or a table of colors that may extend another theme.
    /// - Parameter place: the file of the theme, for the errors. nil: the config itself
    private mutating func theme(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, place: String?, depth: Int, _ c: inout ConfigParserContext) -> OrderedJson.JsonDict? {
        switch raw {
            case .string(let name):
                return named(name, backtrace, depth: depth, &c)
            case .dict(let dict):
                var base: OrderedJson.JsonDict = [:]
                if let extends = dict["extends"] {
                    if let name = extends.asStringOrNil {
                        base = named(name, backtrace, depth: depth, &c) ?? [:]
                    } else {
                        c.errors.append(diagnostic(backtrace, place, ["extends"], expectedActualTypeError(expected: .string, actual: extends.valueType)))
                    }
                }
                return mergedTheme(base, colors(dict, backtrace, place: place, &c))
            default:
                c.errors.append(.init(backtrace, expectedActualTypeError(expected: [.string, .table], actual: raw.valueType)))
                return nil
        }
    }

    /// The theme of the config folder with that name, or else the one of Inlay
    private mutating func named(_ name: String, _ backtrace: ConfigBacktrace, depth: Int, _ c: inout ConfigParserContext) -> OrderedJson.JsonDict? {
        guard depth < Self.maxDepth else {
            c.errors.append(.init(backtrace, "The themes extend each other in a loop: '\(name)' is reached again"))
            return nil
        }
        guard name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            c.errors.append(.init(backtrace, "'\(name)' isn't the name of a theme: write the name of its file, without .lua"))
            return nil
        }
        let fileName = name + ".lua"
        if let folder = configFolder?.appending(component: themesFolderName) {
            let url = folder.appending(component: fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return load(url, place: "\(themesFolderName)/\(fileName)", backtrace, depth: depth, isUsers: true, &c)
            }
            // Creating it must reload the config: it would take the place of the theme of Inlay
            files.append(LuaConfigFile(url: url, text: nil))
        }
        let builtIn = builtInThemesUrl.appending(component: fileName)
        if FileManager.default.fileExists(atPath: builtIn.path) {
            return load(builtIn, place: fileName, backtrace, depth: depth, isUsers: false, &c)
        }
        let yours = configFolder == nil ? "" : ". Yours go in \(themesFolderName)/<name>.lua, next to the config"
        c.warnings.append(.init(backtrace, "There is no theme '\(name)': the colors are the defaults. The themes of Inlay: \(builtInThemeNames.joined(separator: ", "))\(yours)"))
        return nil
    }

    private mutating func load(_ url: URL, place: String, _ backtrace: ConfigBacktrace, depth: Int, isUsers: Bool, _ c: inout ConfigParserContext) -> OrderedJson.JsonDict? {
        let lua = LuaConfigLoader.load(file: url)
        if isUsers { files += lua.files }
        guard lua.errors.isEmpty else {
            c.errors += lua.errors.map { .init(backtrace, "\(place): \($0.message)", preventConfigReload: $0.preventConfigReload) }
            return nil
        }
        return theme(.dict(lua.table), backtrace, place: place, depth: depth + 1, &c)
    }

    /// The look of a theme, checked: a key that isn't one of a theme (see themeKeysMessage), or a value that isn't
    /// right for its key, is an error and is left out
    private func colors(_ dict: OrderedJson.JsonDict, _ backtrace: ConfigBacktrace, place: String?, _ c: inout ConfigParserContext) -> OrderedJson.JsonDict {
        var result: OrderedJson.JsonDict = [:]
        for (key, value) in dict {
            switch key {
                case "extends": break
                case "borders":
                    guard let table = asTable(value, [key], backtrace, place, &c) else { continue }
                    var borders: OrderedJson.JsonDict = [:]
                    for (key, value) in table {
                        let path = ["borders", key]
                        switch key {
                            case "activeColor", "inactiveColor", "floatingColor", "fullscreenColor":
                                if isColor(value, allowAuto: false, path, backtrace, place, &c) { borders[key] = value }
                            case "glow":
                                if isValid(parseBool(value, .emptyRoot), path, backtrace, place, &c) { borders[key] = value }
                            case "glowRadius":
                                let range = BordersConfig.glowRadiusRange
                                let radius = parseInt(value, .emptyRoot)
                                    .filter(.init(.emptyRoot, "glowRadius must be in [\(range.lowerBound), \(range.upperBound)] range")) { range.contains($0) }
                                if isValid(radius, path, backtrace, place, &c) { borders[key] = value }
                            case "modeColors":
                                guard let modes = asTable(value, path, backtrace, place, &c) else { continue }
                                var colors: OrderedJson.JsonDict = [:]
                                for (mode, color) in modes where isColor(color, allowAuto: false, path + [mode], backtrace, place, &c) {
                                    colors[mode] = color
                                }
                                borders[key] = .dict(colors)
                            default: c.errors.append(notAColor(backtrace, place, path))
                        }
                    }
                    result[key] = .dict(borders)
                case "menuBar":
                    guard let table = asTable(value, [key], backtrace, place, &c) else { continue }
                    var menuBar: OrderedJson.JsonDict = [:]
                    var colors: OrderedJson.JsonDict = [:]
                    for (key, value) in table {
                        if key == "systemColors" {
                            if isValid(parseBool(value, .emptyRoot), ["menuBar", key], backtrace, place, &c) { menuBar[key] = value }
                            continue
                        }
                        guard key == "colors" else {
                            c.errors.append(notAColor(backtrace, place, ["menuBar", key]))
                            continue
                        }
                        guard let table = asTable(value, ["menuBar", key], backtrace, place, &c) else { continue }
                        for (key, value) in table {
                            let path = ["menuBar", "colors", key]
                            if !["focused", "accent", "occupied", "empty"].contains(key) {
                                c.errors.append(notAColor(backtrace, place, path))
                            } else if isColor(value, allowAuto: true, path, backtrace, place, &c) {
                                colors[key] = value
                            }
                        }
                    }
                    menuBar["colors"] = .dict(colors)
                    result[key] = .dict(menuBar)
                default:
                    c.errors.append(notAColor(backtrace, place, [key]))
            }
        }
        return result
    }

    private func asTable(_ raw: OrderedJson, _ path: [String], _ backtrace: ConfigBacktrace, _ place: String?, _ c: inout ConfigParserContext) -> OrderedJson.JsonDict? {
        guard case .dict(let dict) = raw else {
            c.errors.append(diagnostic(backtrace, place, path, expectedActualTypeError(expected: .table, actual: raw.valueType)))
            return nil
        }
        return dict
    }

    private func notAColor(_ backtrace: ConfigBacktrace, _ place: String?, _ path: [String]) -> ConfigParseDiagnostic {
        diagnostic(backtrace, place, path, themeKeysMessage)
    }

    private func isColor(_ raw: OrderedJson, allowAuto: Bool, _ path: [String], _ backtrace: ConfigBacktrace, _ place: String?, _ c: inout ConfigParserContext) -> Bool {
        isValid(parseConfigColor(allowAuto: allowAuto)(raw, .emptyRoot), path, backtrace, place, &c)
    }

    private func isValid<T>(_ result: ResOrConfigParseDiagnostic<T>, _ path: [String], _ backtrace: ConfigBacktrace, _ place: String?, _ c: inout ConfigParserContext) -> Bool {
        // The backtrace of the parser is replaced by the one of the theme
        switch result {
            case .success: return true
            case .failure(let error):
                c.errors.append(diagnostic(backtrace, place, path, error.message))
                return false
        }
    }

    /// 'theme: themes/mio.lua: borders.width: …', or 'theme.borders.width: …' for the table of the config
    private func diagnostic(_ backtrace: ConfigBacktrace, _ place: String?, _ path: [String], _ message: String) -> ConfigParseDiagnostic {
        guard let place else { return .init(path.reduce(backtrace) { $0 + .key($1) }, message) }
        return .init(backtrace, "\(place): \(path.joined(separator: ".")): \(message)")
    }
}

/// What a theme can have
let themeKeysMessage = "A theme only has the look of the borders and of the menu bar: the colors of 'borders' and of " +
    "'menuBar.colors', 'borders.glow', 'borders.glowRadius' and 'menuBar.systemColors'"

/// The tables of `over` merged into the ones of `base`; for anything else, the value of `over`. The keys of `over`
/// keep their order and come first: the errors of the config are reported in the order it has
func mergedTheme(_ base: OrderedJson.JsonDict, _ over: OrderedJson.JsonDict) -> OrderedJson.JsonDict {
    var result: OrderedJson.JsonDict = [:]
    for (key, value) in over {
        if case .dict(let baseTable)? = base[key], case .dict(let overTable) = value {
            result[key] = .dict(mergedTheme(baseTable, overTable))
        } else {
            result[key] = value
        }
    }
    for (key, value) in base where result[key] == nil {
        result[key] = value
    }
    return result
}

extension Config {
    /// The borders for the appearance of macOS right now: the light theme of 'theme' when there is one and macOS is light
    @MainActor var bordersForAppearance: BordersConfig {
        if let light = lightAppearance, !isSystemAppearanceDark { return light.borders }
        return borders
    }

    /// The menu bar for the appearance of macOS right now. See: bordersForAppearance
    @MainActor var menuBarForAppearance: MenuBarConfig {
        if let light = lightAppearance, !isSystemAppearanceDark { return light.menuBar }
        return menuBar
    }
}

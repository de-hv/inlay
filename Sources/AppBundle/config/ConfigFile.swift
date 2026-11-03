import Common
import Foundation

let configDotfileName = ".inlay.lua"
/// Where the config of the user is created when there is none: ${XDG_CONFIG_HOME}/inlay/inlay.lua
/// It's the same place scripts/install.sh uses
var newUserConfigUrl: URL { userConfigFolder.appending(path: configFileName) }

/// The config of Inlay 0.2, before Lua: ~/.inlay.toml or ${XDG_CONFIG_HOME}/inlay/inlay.toml
let legacyConfigFileName = "inlay.toml"
let legacyConfigDotfileName = ".inlay.toml"
var legacyUserConfigUrl: URL { userConfigFolder.appending(path: legacyConfigFileName) }

private var userConfigFolder: URL {
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    return xdgConfigHome.appending(path: "inlay")
}

func findCustomConfigUrl() -> ConfigFile {
    if let configLocation = serverArgs.configLocation {
        let url = URL(filePath: configLocation)
        return FileManager.default.fileExists(atPath: url.path) ? .file(url) : .noCustomConfigExists
    }
    let home = FileManager.default.homeDirectoryForCurrentUser
    switch existing([home.appending(path: configDotfileName), newUserConfigUrl]) {
        case []: break
        case let candidates where candidates.count == 1: return .file(candidates[0])
        case let candidates: return .ambiguousConfigError(candidates)
    }
    // No Lua config: one of Inlay 0.2 isn't read, but it isn't silently replaced by the built-in config either
    return existing([home.appending(path: legacyConfigDotfileName), legacyUserConfigUrl]).first.map(ConfigFile.legacyConfig)
        ?? .noCustomConfigExists
}

private func existing(_ candidates: [URL]) -> [URL] {
    candidates.filter { FileManager.default.fileExists(atPath: $0.path) }
}

enum ConfigFile: Equatable {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists
    /// A TOML config of Inlay 0.2, and no Lua config
    case legacyConfig(URL)

    var urlOrNil: URL? {
        return switch self {
            case .file(let url), .legacyConfig(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}

/// Why a config of Inlay 0.2 isn't read
func legacyConfigMessage(_ url: URL) -> String {
    let lua = url.deletingLastPathComponent().appending(path: url.lastPathComponent.hasPrefix(".") ? configDotfileName : configFileName)
    return """
        \(url.path.tildePath) is a config of Inlay 0.2, which Inlay \(inlayAppVersion) doesn't read: the config is Lua now, \
        in \(lua.path.tildePath), and its keys are camelCase (cornerRadius, onWindowDetected). Write it there. Or move \
        \(url.lastPathComponent) away and restart Inlay: it creates \(configFileName) with the built-in config, to start from
        """
}

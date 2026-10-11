import Common
import Foundation

let configDotfileName = ".inlay.toml"
/// Where the config of the user is created when there is none: ${XDG_CONFIG_HOME}/inlay/inlay.toml
/// It's the same place scripts/install.sh uses
var newUserConfigUrl: URL {
    let xdgConfigHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
    return xdgConfigHome.appending(path: "inlay").appending(path: "inlay.toml")
}

func findCustomConfigUrl() -> ConfigFile {
    let candidates: [URL] = switch serverArgs.configLocation {
        case let configLocation?: [URL(filePath: configLocation)]
        case nil:
            [
                FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName),
                newUserConfigUrl,
            ]
    }
    let existingCandidates: [URL] = candidates.filter { (candidate: URL) in FileManager.default.fileExists(atPath: candidate.path) }
    let count = existingCandidates.count
    return switch count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates.first.orDie())
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}

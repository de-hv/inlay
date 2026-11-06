import AppKit
import Common

struct ConfigCommand: Command {
    let args: ConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        switch args.mode {
            case .show(let key):
                return switch ConfigShow.text(key: key, mine: args.mine, keys: args.keys, json: args.json) {
                    case .success(let text): .succ(io.out(text))
                    case .failure(let message): .fail(io.err(message))
                }
            case .files:
                return .succ(io.out(ConfigShow.filesText()))
            case .file(let name):
                return switch ConfigShow.fileText(name) {
                    case .success(let text): .succ(io.out(text))
                    case .failure(let message): .fail(io.err(message))
                }
            case .configPath:
                return .succ(io.out(configUrl.absoluteURL.path))
            case .use(let path):
                return await changeConfig(io, ConfigFiles.use(URL(filePath: path)))
            case .unlink:
                return await changeConfig(io, ConfigFiles.unlink())
            case .explain(let key):
                // The CLI answers it on its own, without the server. This is for 'config --explain' run by a binding
                return switch ConfigReference.load().flatMap({ $0.explain(key) }) {
                    case .success(let text): .succ(io.out(text))
                    case .failure(let message): .fail(io.err(message))
                }
            case .types:
                // The CLI answers it on its own too
                return switch EditorTypes.writeLuarc() {
                    case .success(let text): .succ(io.out(text))
                    case .failure(let message): .fail(io.err(message))
                }
        }
    }
}

/// After --use or --unlink: says what was done, and loads the config that is now in use
@MainActor private func changeConfig(_ io: CmdIo, _ result: Result<String, ConfigFiles.UseError>) async -> BinaryExitCode {
    switch result {
        case .success(let message):
            io.out(message)
            let reload = await reloadConfig_nonCancellable()
            if !reload.stderr.isEmpty { io.err(reload.stderr) }
            return .from(bool: reload.isOk)
        case .failure(let error):
            return .fail(io.err(error.message))
    }
}

extension Shell<any Command> {
    var shellOfCommandsDescription: String { buildDescription { $0.args.description } }
}

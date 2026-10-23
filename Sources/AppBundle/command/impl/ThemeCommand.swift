import AppKit
import Common

/// 'theme set <palette>' writes the palette in the config and reloads it. 'theme list' prints the palettes
struct ThemeCommand: Command {
    let args: ThemeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        switch args.action.val {
            case .list:
                return .succ(io.out(list()))
            case .set:
                return await set(args.name ?? "", io)
        }
    }

    @MainActor private func list() -> String {
        let current = config.theme.palette
        var lines = ThemePalette.allCases.map { palette in
            var line = (palette == current ? "* " : "  ") + palette.rawValue
            if palette == .material { line += "  (seed: \(config.theme.seed))" }
            return line
        }
        let manual = ManualColors.keys(in: config)
        if !manual.isEmpty {
            lines.append("")
            lines.append(Strings.Theme.manualColorsNote(manual.map(\.label)))
        }
        return lines.joined(separator: "\n")
    }

    @MainActor private func set(_ name: String, _ io: CmdIo) async -> BinaryExitCode {
        guard let palette = ThemePalette(rawValue: name) else {
            return .fail(io.err("Unknown palette '\(name)'. Possible values: \(ThemePalette.unionLiteral)"))
        }
        let target: ConfigEditor.Target
        switch ConfigEditor.target() {
            case .success(let it): target = it
            case .failure(let error): return .fail(io.err(error.message))
        }
        let manual = ManualColors.keys(in: config)
        var edits = [ConfigEdit(path: SettingsKey.themePalette.path, value: .string(palette.rawValue))]
        if args.resetColors { edits += manual.map { ConfigEdit(path: $0.path, value: nil) } }
        if case .failure(let error) = ConfigEditor.apply(edits, to: target) {
            return .fail(io.err(error.message))
        }
        let result = await reloadConfig_nonCancellable(notice: .always)
        if !result.isOk { return .fail(io.err(result.stdout)) }
        if !args.resetColors && !manual.isEmpty {
            io.err(Strings.Theme.manualColorsNote(manual.map(\.label)))
        }
        return .succ(io.out(Strings.Theme.paletteSet(palette.title)))
    }
}

import AppKit
import Common

struct ReloadConfigCommand: Command {
    let args: ReloadConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let result = await reloadConfig_nonCancellable(args: args)
        if !result.stdout.isEmpty {
            io.out(result.stdout)
        }
        if !result.stderr.isEmpty {
            io.err(result.stderr)
        }
        return .from(bool: result.isOk)
    }
}

struct ReloadConfigResult {
    let isOk: Bool
    let stdout: String
    let stderr: String
}

/// The text of the config that was applied last. What the notice of the next reload compares with. See: ReloadNotice
@MainActor private var appliedConfigText: String? = nil

/// When a reload shows its notice. See: ReloadNoticePanel
enum ReloadNoticeTrigger {
    /// At startup, and after the settings window writes the file: the window already shows the change
    case never
    /// The file is different from the config that was applied last. 'reload-config' runs in key bindings that
    /// have nothing to do with the file (the 'esc' that leaves a binding mode), and the save of the file is what
    /// the notice is about
    case ifChanged
    /// "Reload Config" in the menu: the user asked, so the notice answers, also with "No setting changed"
    case always
}

@MainActor func reloadConfig_nonCancellable(
    args: ReloadConfigCmdArgs = ReloadConfigCmdArgs(rawArgs: []),
    forceConfigUrl: URL? = nil,
    notice: ReloadNoticeTrigger = .ifChanged,
) async -> ReloadConfigResult {
    let result = readConfig(forceConfigUrl: forceConfigUrl)
    let parseResult = result.parseConfigResult
    let warningsAsErrors = args.warningsAsErrors
    let isApplied = parseResult.allowReloadConfig && !args.dryRun

    var hotkeyWarnings: [ConfigParseDiagnostic] = []
    let previousText = appliedConfigText
    if isApplied {
        appliedConfigText = result.text
        resetHotKeys()
        config = parseResult.config
        configUrl = result.configUrl
        // Nothing is registered right now, so every binding of every mode can be tried
        hotkeyWarnings = hotkeyRegistrationWarnings(config.modes, canRegister: canRegisterHotKey)
        await activateMode_nonCancellable(activeMode)
        // The built-in config that is loaded first, before the config of the user (see: bootstrapConfig_nonCancellable),
        // must not add Inlay to the login items: the config of the user decides
        if forceConfigUrl == nil { syncStartAtLogin() }
        syncFocusFollowsMouse(config)
        // The theme of the config of the user: not the built-in config that is loaded first
        if forceConfigUrl == nil {
            WallpaperSeed.shared.sync()
            ThemeController.shared.configDidLoad()
        }
    }

    var errors = parseResult.errors.map { $0.description(.error) }
    var warnings = (parseResult.warnings + hotkeyWarnings).map { $0.description(.warning) }
    let containsWarnings = !warnings.isEmpty

    if !args.noGui {
        let lines = errors + warnings
        switch true {
            case !errors.isEmpty:
                let msg = failedToParseMsg(configUrl: result.configUrl, errorsCount: errors.count, warningsCount: warnings.count, lines: lines)
                MessageModel.shared.message = Message(body: msg, containsWarnings: containsWarnings)
            case warningsAsErrors && !warnings.isEmpty:
                let msg = parsedWithWarningsMsg(configUrl: result.configUrl, warningsCount: warnings.count, lines: lines)
                MessageModel.shared.message = Message(body: msg, containsWarnings: containsWarnings)
            default:
                MessageModel.shared.message = nil
        }
        // The window of the diagnostics tells about a config that has errors. The notice is for the one that loads
        let showsNotice = switch notice {
            case .never: false
            case .ifChanged: result.text != previousText
            case .always: true
        }
        if isApplied && showsNotice && errors.isEmpty && !(warningsAsErrors && !warnings.isEmpty),
           let notice = ReloadNotice(
               style: config.notifications.onReload,
               fileName: result.configUrl.lastPathComponent,
               oldText: previousText,
               newText: result.text,
               warningCount: warnings.count,
           )
        {
            ReloadNoticePanel.shared.show(notice)
        }
    }
    if !args.dryRun {
        DebugStats.count("config.load")
        ServerState.shared.lastConfigLoad = ConfigLoadStatus(
            date: .now,
            url: result.configUrl,
            errorCount: errors.count,
            warningCount: warnings.count,
            isApplied: parseResult.allowReloadConfig,
        )
        // Also when the config wasn't applied: the file is watched, so that fixing it loads it.
        // Without a config of the user, the place where it would be created is watched
        ConfigAutoReload.sync(url: result.configUrl == defaultConfigUrl ? newUserConfigUrl : result.configUrl, text: result.text)
        publishUiState()
    }

    if warningsAsErrors {
        errors += warnings
        warnings = []
    }

    return ReloadConfigResult(
        isOk: errors.isEmpty,
        stdout: errors.joined(separator: "\n\n"),
        stderr: warnings.joined(separator: "\n\n"),
    )
}

private func failedToParseMsg(configUrl: URL, errorsCount: Int, warningsCount: Int, lines: [String]) -> String {
    let path = configUrl.absoluteURL.path.singleQuoted
    let header = "Failed to parse \(path). \(errorsCount) error(s). \(warningsCount) warning(s)"
    return "\(header)\n\n\(lines.joined(separator: "\n\n"))"
}

private func parsedWithWarningsMsg(configUrl: URL, warningsCount: Int, lines: [String]) -> String {
    let path = configUrl.absoluteURL.path.singleQuoted
    let header = "Parsed \(path) with \(warningsCount) warning(s). Feel free to close this window."
    return "\(header)\n\n\(lines.joined(separator: "\n\n"))"
}

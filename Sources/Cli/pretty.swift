import Common
import Darwin
import Foundation
import Network

/// The styles of the two streams: each one is colored when it is a terminal. See: CliStyle
let outStyle = CliStyle.of(fd: STDOUT_FILENO)
let errStyle = CliStyle.of(fd: STDERR_FILENO)

extension Array where Element == String {
    var slice: StrArrSlice { StrArrSlice.new(self, 0 ..< count) ?? StrArrSlice.new([], 0 ..< 0)! }
}

/// One more question to the server, on the same connection. nil: it failed
private func ask(_ connection: NWConnection, _ args: [String], failExitCode: Int32) async -> ServerAnswer? {
    let answer = await run(connection, args.slice, stdin: "", windowId: nil, workspace: nil, failExitCode: failExitCode)
    return answer.exitCode == EXIT_CODE_ZERO ? answer : nil
}

/// The list-* commands as a table, for a terminal: nil when the command isn't one of them, when stdout isn't a
/// terminal, or when the command chooses its own output (--format, --json, --count). Then the server's answer is
/// printed as it is, as it always was
func prettyList(_ connection: NWConnection, _ parsedArgs: any CmdArgs, _ args: [String], windowId: UInt32?, workspace: String?, failExitCode: Int32) async -> ServerAnswer? {
    guard isatty(STDOUT_FILENO) == 1, !args.contains(where: { ["--format", "--json", "--count", "-h", "--help"].contains($0) }) else { return nil }
    let format: String
    switch parsedArgs {
        case is ListWorkspacesCmdArgs: format = CliLists.workspaceFormat
        case is ListWindowsCmdArgs: format = CliLists.windowFormat
        case is ListMonitorsCmdArgs: format = CliLists.monitorFormat
        case is ListAppsCmdArgs: format = CliLists.appFormat
        default: return nil
    }
    let main = await run(connection, (args + ["--json", "--format", format]).slice, stdin: "", windowId: windowId, workspace: workspace, failExitCode: failExitCode)
    guard main.exitCode == EXIT_CODE_ZERO else { return main }
    let objects = CliLists.objects(main.stdout)
    func trimmed(_ answer: ServerAnswer?) -> String? {
        answer.map { $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    let table: CliTable
    switch parsedArgs {
        case is ListWorkspacesCmdArgs:
            let windows = await ask(connection, ["list-windows", "--all", "--json", "--format", CliLists.windowFormat], failExitCode: failExitCode)
            let config = await ask(connection, ["config", "--show", "workspaces", "--json"], failExitCode: failExitCode)
            var names: [String: String] = [:]
            for workspace in CliLists.objects(config?.stdout ?? "[]") {
                if let id = workspace["id"] as? String, let name = workspace["name"] as? String { names[id] = name }
            }
            table = CliLists.workspaces(objects, windows: CliLists.objects(windows?.stdout ?? "[]"), names: names)
        case is ListWindowsCmdArgs:
            let focused = trimmed(await ask(connection, ["list-windows", "--focused", "--format", "%{window-id}"], failExitCode: failExitCode))
            table = CliLists.windows(objects, focusedId: focused)
        case is ListMonitorsCmdArgs:
            let visible = await ask(connection, ["list-workspaces", "--monitor", "all", "--visible", "--json", "--format", "%{workspace} %{monitor-id}"], failExitCode: failExitCode)
            var workspaces: [String: String] = [:]
            for object in CliLists.objects(visible?.stdout ?? "[]") {
                let monitor = (object["monitor-id"] as? NSNumber)?.stringValue ?? (object["monitor-id"] as? String) ?? ""
                if let workspace = object["workspace"] as? String { workspaces[monitor] = workspace }
            }
            let focused = trimmed(await ask(connection, ["list-monitors", "--focused", "--format", "%{monitor-id}"], failExitCode: failExitCode))
            table = CliLists.monitors(objects, workspaces: workspaces, focusedId: focused)
        default:
            let focused = trimmed(await ask(connection, ["list-windows", "--focused", "--format", "%{app-pid}"], failExitCode: failExitCode))
            table = CliLists.apps(objects, focusedPid: focused)
    }
    let text = table.rows.isEmpty
        ? outStyle.paint("  none", .muted)
        : table.render(width: terminalColumns(), style: outStyle).joined(separator: "\n")
    return ServerAnswer(exitCode: EXIT_CODE_ZERO, stdout: text, serverVersionAndHash: main.serverVersionAndHash)
}

/// The output of a config command, for a terminal: the Lua highlighted, the files with their labels
func prettyConfig(_ parsedArgs: any CmdArgs, _ stdout: String) -> String {
    guard outStyle.isEnabled, let config = parsedArgs as? ConfigCmdArgs else { return stdout }
    switch config.mode {
        case .show where !config.json && !config.keys: return CliText.lua(stdout, style: outStyle)
        case .file: return CliText.lua(stdout, style: outStyle)
        case .explain: return CliText.explain(stdout, style: outStyle)
        case .files: return CliText.files(stdout, style: outStyle)
        default: return stdout
    }
}

/// The diagnostics on stderr, for a terminal: 'error:' and 'warning:', and the line of Lua that fails
func prettyDiagnostics(_ stderr: String) -> String {
    let folder = EditorTypes.configFolder()
    return CliText.diagnostics(stderr, style: errStyle) { file, line in
        guard let folder, let text = try? String(contentsOf: folder.appending(path: file), encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.getOrNil(atIndex: line - 1).map(String.init)
    }
}

/// 'inlay' alone: the server, where you are, and the config. Each fact is a question to the server; one that fails
/// is left out
func printStatus() async -> Never {
    var status = CliText.Status(version: inlayAppVersion)
    let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
    if await connection.initConnection().error == nil {
        let failExitCode = EXIT_CODE_TWO
        if let version = await ask(connection, ["list-modes", "--current"], failExitCode: failExitCode) {
            let server = version.serverVersionAndHash
            status.serverVersion = server.split(separator: " ").first.map(String.init) ?? server
            status.mode = version.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if status.serverVersion != nil {
            let focused = CliLists.objects(await ask(connection, ["list-workspaces", "--focused", "--json", "--format", "%{workspace} %{monitor-name}"], failExitCode: failExitCode)?.stdout ?? "[]").first
            status.workspace = focused?["workspace"] as? String
            status.monitor = (focused?["monitor-name"] as? String).map { $0.replacingOccurrences(of: " Display", with: "") }
            if let count = await ask(connection, ["list-windows", "--workspace", "focused", "--count"], failExitCode: failExitCode) {
                status.windows = Int(count.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            let workspaces = CliLists.objects(await ask(connection, ["config", "--show", "workspaces", "--json"], failExitCode: failExitCode)?.stdout ?? "[]")
            status.workspaces = workspaces.isEmpty ? nil : workspaces.count
            status.workspaceName = workspaces.first { ($0["id"] as? String) == status.workspace }?["name"] as? String
            if let theme = await ask(connection, ["config", "--show", "theme", "--json"], failExitCode: failExitCode) {
                let text = theme.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if let object = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed) {
                    status.theme = (object as? String) ?? ((object as? [String: Any])?["extends"] as? String)
                }
            }
            if let bindings = await ask(connection, ["config", "--show", "mode", "--keys"], failExitCode: failExitCode) {
                status.bindings = bindings.stdout.split(separator: "\n").count
            }
            if let path = await ask(connection, ["config", "--config-path"], failExitCode: failExitCode) {
                let url = URL(filePath: path.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                let folder = url.deletingLastPathComponent()
                let real = folder.resolvingSymlinksInPath()
                status.configPath = folder.path.tildePath
                if real.path != folder.path { status.configTarget = real.path.tildePath }
            }
            let check = await run(connection, ["reload-config", "--dry-run"].slice, stdin: "", windowId: nil, workspace: nil, failExitCode: failExitCode)
            status.configErrors = check.exitCode == EXIT_CODE_ZERO ? 0 : max(1, check.stderr.split(separator: "\n").filter { $0.hasPrefix("[ERROR]") }.count)
        }
    }
    exit(EXIT_CODE_ZERO, out: CliText.status(status, width: terminalColumns(), style: outStyle))
}

/// 'inlay --version': the CLI and the app, the first line alone for scripts
func printVersion() async -> Never {
    let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
    var server: String? = nil
    if await connection.initConnection().error == nil {
        server = await run(connection, [], stdin: "", windowId: nil, workspace: nil, failExitCode: EXIT_CODE_TWO).serverVersionAndHash
    }
    print("inlay \(cliClientVersionAndHash)")
    print(outStyle.paint("Inlay.app \(server ?? "not running")", server == nil ? .warning : .muted))
    if let server, server != cliClientVersionAndHash {
        eprint(versionMismatch(server: server))
    }
    exit(EXIT_CODE_ZERO)
}

func versionMismatch(server: String) -> String {
    let short = { (text: String) in text.split(separator: " ").first.map(String.init) ?? text }
    return """
        \(errStyle.paint("warning:", .warning)) Inlay.app is \(short(server)), this inlay is \(inlayAppVersion)
        \(errStyle.paint("hint:", .muted))  restart Inlay: \(errStyle.paint("open -a Inlay", .accent))
        """
}

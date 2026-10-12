import Common
import Darwin
import Foundation
import Network

let usage =
    """
    USAGE: \(CommandLine.arguments.first ?? "inlay") [-h|--help] [-v|--version] <subcommand> [<args>...]

    SUBCOMMANDS:
    \(subcommandDescriptions.sortedBy { $0[0] }.toPaddingTable(columnSeparator: "   ").joined(separator: "\n"))
    """

@main
struct Main {
    static func main() async {
        let args = CommandLine.arguments.slice(1...) ?? []

        if args.isEmpty {
            exit(EXIT_CODE_TWO, err: usage)
        }
        if args.first == "--help" || args.first == "-h" {
            exit(EXIT_CODE_ZERO, out: usage)
        }

        if args.first == "--version" || args.first == "-v" {
            let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)
            let serverVersionAndHash: String?
            switch await connection.initConnection().error {
                case nil:
                    let ans = await run(connection, [], stdin: "", windowId: nil, workspace: nil, failExitCode: EXIT_CODE_TWO)
                    serverVersionAndHash = ans.serverVersionAndHash
                case .nwError(let e):
                    eprint(e.localizedDescription)
                    serverVersionAndHash = nil
                case .customError(let msg):
                    exit(EXIT_CODE_TWO, err: msg)
            }
            print(
                """
                inlay CLI client version: \(cliClientVersionAndHash)
                Inlay.app server version: \(serverVersionAndHash ?? "Unknown. The server is not responding")
                """,
            )
            if serverVersionAndHash != nil && cliClientVersionAndHash != serverVersionAndHash {
                eprint(
                    """
                    Warning: Inlay client/server versions don't match. Possible fixes:
                      - Restart Inlay.app (server restart is required after each update)
                      - Reinstall and restart Inlay (corrupted installation)
                    """,
                )
            }
            exit(EXIT_CODE_ZERO)
        }

        // Not a command of the server: it removes the server
        if args.first == "uninstall" {
            runUninstall(args.slice(1...)?.toArray() ?? [])
        }

        let parsedArgs: any CmdArgs
        switch parseCmdArgs(args) {
            // Optimizations
            case .cmd(_ as TrueCmdArgs): exit(ConditionalExitCode._true.rawValue)
            case .cmd(_ as FalseCmdArgs): exit(ConditionalExitCode._false.rawValue)

            case .cmd(let _parsedArgs): parsedArgs = _parsedArgs
            case .help(let help): exit(EXIT_CODE_ZERO, out: help)
            case .failure(let e): exit(e.exitCode, err: e.msg)
        }

        let failExitCode = parsedArgs.failExitCode

        // Documentation: answered from the reference that ships with Inlay, so it works without the server
        if let configArgs = parsedArgs as? ConfigCmdArgs, case .explain(let key) = configArgs.mode {
            switch ConfigReference.load().flatMap({ $0.explain(key) }) {
                case .success(let text): exit(EXIT_CODE_ZERO, out: text)
                case .failure(let message): exit(failExitCode, err: message)
            }
        }

        let connection = NWConnection(to: NWEndpoint.unix(path: socketPath), using: .tcp)

        switch await connection.initConnection().error {
            case nil: break
            case .customError(let msg):
                exit(failExitCode, err: msg)
            case .nwError(let e):
                // The server opens its socket once it has the Accessibility permission
                exit(
                    failExitCode,
                    err: "Can't connect to Inlay server. Is Inlay.app running?\n" +
                        "If it is, it may be waiting for the Accessibility permission: " +
                        "System Settings > Privacy & Security > Accessibility\n\(e.localizedDescription)",
                )
        }

        var stdin = ""
        if parsedArgs.commonState.explicitStdinFlag == true ||
            // todo: drop after a couple of versions
            (parsedArgs.commonState.explicitStdinFlag != false && (parsedArgs is WorkspaceCmdArgs && (parsedArgs as! WorkspaceCmdArgs).target.val.isRelatve || parsedArgs is MoveNodeToWorkspaceCmdArgs && (parsedArgs as! MoveNodeToWorkspaceCmdArgs).target.val.isRelatve) && hasStdin())
        {
            if parsedArgs is WorkspaceCmdArgs && parsedArgs.commonState.explicitStdinFlag == nil ||
                parsedArgs is MoveNodeToWorkspaceCmdArgs && parsedArgs.commonState.explicitStdinFlag == nil
            {
                exit(
                    failExitCode,
                    err: """
                        ERROR: Implicit stdin is detected (stdin is not TTY). Implicit stdin was forbidden upstream in AeroSpace v0.20.0.
                        1. Please supply '--stdin' flag to make stdin explicit and preserve the old behavior
                        2. You can also use '--no-stdin' flag to behave as if no stdin was supplied
                        Breaking change issue: https://github.com/nikitabobko/AeroSpace/issues/1683
                        """,
                )
            }
            var index = 0
            while let line = readLine(strippingNewline: false) {
                stdin += line
                index += 1
                if index > 1000 {
                    exit(failExitCode, err: "stdin number of lines limit is exceeded")
                }
            }
        }

        let windowId = ProcessInfo.processInfo.environment[INLAY_WINDOW_ID].flatMap(UInt32.init)
        let workspace = ProcessInfo.processInfo.environment[INLAY_WORKSPACE]

        // Handle subscribe command specially
        if parsedArgs is SubscribeCmdArgs {
            await runSubscribe(connection, args, windowId: windowId, workspace: workspace, failExitCode: parsedArgs.failExitCode)
            exit(EXIT_CODE_ZERO) // Should not reach here
        }

        var ans = await run(connection, args, stdin: stdin, windowId: windowId, workspace: workspace, failExitCode: failExitCode)

        // The server only knows how to answer once. Until interrupted (ctrl-c), or until the server is gone
        if let seconds = (parsedArgs as? DebugStatsCmdArgs)?.watch {
            while ans.exitCode == EXIT_CODE_ZERO {
                print(ans.stdout + "\n")
                unsafe fflush(stdout)
                try? await Task.sleep(for: .seconds(Int(seconds)))
                ans = await run(connection, args, stdin: stdin, windowId: windowId, workspace: workspace, failExitCode: failExitCode)
            }
        }

        if !ans.stdout.isEmpty { print(ans.stdout) }
        if !ans.stderr.isEmpty { eprint(ans.stderr) }
        if ans.exitCode != EXIT_CODE_ZERO && ans.serverVersionAndHash != cliClientVersionAndHash {
            eprint(
                """
                Warning: Inlay client/server versions don't match
                  - inlay CLI client version: \(cliClientVersionAndHash)
                  - Inlay.app server version: \(ans.serverVersionAndHash)
                  Possible fixes:
                  - Restart Inlay.app (server restart is required after each update)
                  - Reinstall and restart Inlay (corrupted installation)
                """,
            )
        }
        exit(ans.exitCode)
    }
}

func runSubscribe(_ connection: NWConnection, _ args: StrArrSlice, windowId: UInt32?, workspace: String?, failExitCode: Int32) async {
    if let e = await connection.writeAtomic(ClientRequest(args: args.toArray(), stdin: "", windowId: windowId, workspace: workspace)).error {
        exit(failExitCode, err: "Failed to write to server socket: \(e)")
    }

    while true {
        switch await connection.readNonAtomic() {
            case .success(let data):
                if let str = String(data: data, encoding: .utf8) {
                    print(str)
                    unsafe fflush(stdout)
                } else {
                    exit(failExitCode, err: "Can't convert bytes to utf8 String")
                }
            case .failure(let e):
                exit(failExitCode, err: "runSubscribe error: \(e)")
        }
    }
}

func run(_ connection: NWConnection, _ args: StrArrSlice, stdin: String, windowId: UInt32?, workspace: String?, failExitCode: Int32) async -> ServerAnswer {
    if let e = await connection.writeAtomic(ClientRequest(args: args.toArray(), stdin: stdin, windowId: windowId, workspace: workspace)).error {
        exit(failExitCode, err: "Failed to write to server socket: \(e)")
    }

    switch await connection.readNonAtomic() {
        case .success(let answer):
            return (try? JSONDecoder().decode(ServerAnswer.self, from: answer)) ?? exitT(EXIT_CODE_TWO, err: "Failed to parse server response: \(String(data: answer, encoding: .utf8).prettyDescription)")
        case .failure(let error):
            exit(failExitCode, err: "Failed to read from server socket: \(error)")
    }
}

/// 'inlay uninstall': runs the uninstall script that ships with Inlay. The script deletes the app that contains
/// it (and this CLI), so a temporary copy of it is what runs
func runUninstall(_ args: [String]) -> Never {
    let files = ["uninstall.sh", "lib.sh"]
    let sources = files.map { shippedFile(inResources: "scripts/\($0)", inRepo: "scripts/\($0)") }
    let directory = FileManager.default.temporaryDirectory.appending(path: "inlay-uninstall.\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (file, source) in zip(files, sources) {
            guard let source else {
                exit(EXIT_CODE_TWO, err: "Can't find the uninstall script (\(file)). Is Inlay installed correctly? It is expected in Inlay.app/Contents/Resources/scripts")
            }
            try FileManager.default.copyItem(at: source, to: directory.appending(path: file))
        }
    } catch {
        exit(EXIT_CODE_TWO, err: "Can't prepare the uninstall script in \(directory.path): \(error.localizedDescription)")
    }

    unsafe setenv("INLAY_UNINSTALL_SELF_DIR", directory.path, 1) // The script removes its own copy
    // The app that this CLI belongs to, wherever it is installed
    if let app = appBundle() { unsafe setenv("INLAY_UNINSTALL_APP", app.path, 1) }
    // The script takes the place of this process, rather than being a child of it: it keeps the terminal,
    // where it asks for confirmation, and it doesn't depend on a binary that it deletes
    let arguments = ["/bin/bash", directory.appending(path: "uninstall.sh").path] + args
    let cArguments: [UnsafeMutablePointer<CChar>?] = unsafe arguments.map { unsafe strdup($0) } + [nil]
    unsafe execv("/bin/bash", cArguments)
    let reason = unsafe String(cString: strerror(errno))
    exit(EXIT_CODE_TWO, err: "Can't run the uninstall script: \(reason)")
}

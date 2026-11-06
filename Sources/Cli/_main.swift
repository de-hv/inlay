import Common
import Darwin
import Foundation
import Network

@main
struct Main {
    static func main() async {
        var args = CommandLine.arguments.slice(1...) ?? []

        // Alone: what is running, where you are, and the commands people use
        if args.isEmpty {
            await printStatus()
        }
        if args.first == "--help" || args.first == "-h" || args.first == "help" && args.count == 1 {
            let all = args.contains("--all")
            var descriptions: [String: String] = [:]
            for pair in subcommandDescriptions { descriptions[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1] }
            exit(EXIT_CODE_ZERO, out: CliText.help(descriptions: all ? descriptions : nil, width: terminalColumns(), style: outStyle))
        }

        if args.first == "--version" || args.first == "-v" || args.first == "version" && args.count == 1 {
            await printVersion()
        }

        // For scripts/build-app.sh: the file of types for the editors, made from the config reference. See: EditorTypes
        if args.first == EditorTypes.printFlag {
            switch ConfigReference.load() {
                case .success(let reference): exit(EXIT_CODE_ZERO, out: EditorTypes.generate(reference))
                case .failure(let message): exit(EXIT_CODE_TWO, err: message)
            }
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
            case .failure(let e):
                if let name = args.first, e.msg == "Unrecognized subcommand '\(name)'" {
                    let commands = subcommandDescriptions.map { $0[0].trimmingCharacters(in: .whitespaces) }
                    exit(e.exitCode, err: CliText.unknownCommand(name, arguments: args.slice(1...)?.toArray() ?? [], commands: commands, style: errStyle))
                }
                exit(e.exitCode, err: errStyle.isEnabled ? "\(errStyle.paint("error:", .error)) \(e.msg)" : e.msg)
        }

        let failExitCode = parsedArgs.failExitCode

        // Documentation: answered from the reference that ships with Inlay, so it works without the server
        if let configArgs = parsedArgs as? ConfigCmdArgs, case .explain(let key) = configArgs.mode {
            switch ConfigReference.load().flatMap({ $0.explain(key) }) {
                case .success(let text): exit(EXIT_CODE_ZERO, out: prettyConfig(parsedArgs, text))
                case .failure(let message): exit(failExitCode, err: message)
            }
        }
        // The .luarc.json of the config folder: the CLI knows the app it is in
        if let configArgs = parsedArgs as? ConfigCmdArgs, case .types = configArgs.mode {
            switch EditorTypes.writeLuarc() {
                case .success(let text): exit(EXIT_CODE_ZERO, out: text)
                case .failure(let message): exit(failExitCode, err: message)
            }
        }
        // The server has a working directory of its own: the path of 'config --use' goes to it absolute
        if let configArgs = parsedArgs as? ConfigCmdArgs, case .use(let path) = configArgs.mode, !path.hasPrefix("/") {
            let absolute = URL(filePath: path, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath + "/")).standardizedFileURL.path
            let array = args.toArray()
            if let index = array.firstIndex(of: "--use"), array.getOrNil(atIndex: index + 1) == path {
                args = StrArrSlice.new(array.enumerated().map { $0.offset == index + 1 ? absolute : $0.element }, 0 ..< array.count) ?? args
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
                        ERROR: Implicit stdin is detected (stdin is not TTY): a relative workspace ('next', 'prev') doesn't read stdin on its own.
                        1. Please supply '--stdin' flag to read the workspaces from stdin
                        2. You can also use '--no-stdin' flag to behave as if no stdin was supplied
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

        if let table = await prettyList(connection, parsedArgs, args.toArray(), windowId: windowId, workspace: workspace, failExitCode: failExitCode) {
            if !table.stdout.isEmpty { print(table.stdout) }
            if !table.stderr.isEmpty { eprint(prettyDiagnostics(table.stderr)) }
            exit(table.exitCode)
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

        if !ans.stdout.isEmpty { print(prettyConfig(parsedArgs, ans.stdout)) }
        if !ans.stderr.isEmpty { eprint(prettyDiagnostics(ans.stderr)) }
        if ans.exitCode != EXIT_CODE_ZERO && ans.serverVersionAndHash != cliClientVersionAndHash {
            eprint(versionMismatch(server: ans.serverVersionAndHash))
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

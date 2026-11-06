import Foundation

/// The autocompletion of the keys of the config in an editor, through lua-language-server (Zed, VS Code, Neovim…):
/// - scripts/build-app.sh writes the file of types, inlay.d.lua, into Inlay.app/Contents/Resources/types, made from
///   the config reference (see: generate). Every version of Inlay carries its own;
/// - `inlay config --types` writes once a .luarc.json in the config folder, which points the language server at
///   that folder of the app. An update of Inlay changes the file it points at, so there is nothing else to do.
public enum EditorTypes {
    public static let folderName = "types"
    public static let fileName = "inlay.d.lua"
    public static let luarcName = ".luarc.json"
    /// What the CLI of the build is run with to print the file of types. See: scripts/build-app.sh
    public static let printFlag = "--print-config-types"

    // MARK: - .luarc.json

    /// The folder of types of the app that runs this binary
    public static func appTypesFolder(executable: String = CommandLine.arguments[0]) -> URL? {
        appBundle(ofExecutable: executable).map { $0.appending(path: "Contents/Resources").appending(path: folderName) }
    }

    /// The folder of the config: where inlay.lua is. nil: ~/.inlay.lua, a config without a folder of its own
    public static func configFolder(environment: [String: String] = ProcessInfo.processInfo.environment, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let xdg = environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) } ?? home.appending(path: ".config")
        let folder = xdg.appending(path: "inlay")
        if FileManager.default.fileExists(atPath: folder.appending(path: "inlay.lua").path) { return folder }
        if FileManager.default.fileExists(atPath: home.appending(path: ".inlay.lua").path) { return nil }
        return folder
    }

    public static func luarc(typesFolder: URL) -> String {
        """
        {
          "runtime.version": "Lua 5.4",
          "workspace.library": ["\(typesFolder.path)"],
          "diagnostics.globals": ["inlay"]
        }

        """
    }

    /// Writes the .luarc.json of the config folder, unless there is one: then it prints it, and what it would write
    public static func writeLuarc(typesFolder: URL? = appTypesFolder(), configFolder: URL? = configFolder()) -> Result<String, String> {
        guard let typesFolder, FileManager.default.fileExists(atPath: typesFolder.appending(path: fileName).path) else {
            return .failure("The types of the config are in the app: run the 'inlay' of the installed Inlay.app (the one of Homebrew or of install.sh)")
        }
        guard let configFolder else {
            return .failure("~/.inlay.lua has no folder of its own for \(luarcName): move it to ~/.config/inlay/inlay.lua")
        }
        let target = configFolder.appending(path: luarcName)
        let text = luarc(typesFolder: typesFolder)
        if let current = try? String(contentsOf: target, encoding: .utf8) {
            if current.contains(typesFolder.path) {
                return .success("\(target.path) already points at the types of this Inlay:\n\n\(current)")
            }
            return .success("""
                \(target.path) exists, and it is left as it is. It is:

                \(current)
                For the types of this Inlay, it needs:

                \(text)
                """)
        }
        do {
            try FileManager.default.createDirectory(at: configFolder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: target, options: .withoutOverwriting)
        } catch {
            return .failure("Can't write \(target.path): \(error.localizedDescription)")
        }
        return .success("""
            Wrote \(target.path):

            \(text)
            Open the config folder in your editor (with lua-language-server: the Lua extension of Zed or of VS Code) \
            to get the keys of the config, their values and what they do. Updating Inlay updates the types.
            """)
    }

    // MARK: - inlay.d.lua

    /// The tables whose keys are names that the user chooses, with the type of their values
    private static let freeFormTables: [String: String] = [
        "mode": "table<string, InlayConfig.mode.item>",
        "borders.mode_colors": "table<string, string>",
        "exec.env_vars": "table<string, string>",
        "key_mapping.key_notation_to_key_code": "table<string, string>",
        "workspace_to_monitor_force_assignment": "table<string, string|string[]>",
        "animations.curves": "table<string, number[]>",
    ]

    /// The tables that are lists of tables: their items are a class
    private static let arrays: [String: String] = [
        "on_window_detected": "(InlayConfig.on_window_detected|'workspaces')[]",
        "workspaces": "InlayConfig.workspaces[]",
    ]

    /// The file of types for lua-language-server, from the config reference
    public static func generate(_ reference: ConfigReference) -> String {
        var out = """
            ---@meta
            -- The keys of the config of Inlay, for lua-language-server: autocompletion, their values and what
            -- they do. Made from config-reference.lua by scripts/build-app.sh: don't edit it.


            """
        var classes: [String: [ConfigReference.Entry]] = ["": []]
        var classOrder: [String] = [""]
        var seen: Set<String> = []
        for entry in reference.entries {
            guard seen.insert(entry.path).inserted, !entry.isCommentedOut || entry.fallback != nil || entry.possibleValues != nil else { continue }
            let parts = entry.path.split(separator: ".").map(String.init)
            let parent = parts.dropLast().joined(separator: ".")
            // Inside a free-form table: examples, not keys
            if freeFormTables.keys.contains(where: { parent == $0 || parent.hasPrefix($0 + ".") }) { continue }
            if classes[parent] == nil {
                classes[parent] = []
                classOrder.append(parent)
            }
            classes[parent]?.append(entry)
        }
        out += """
            ---@class InlayConfig.mode.item
            ---@field binding? table<string, string|string[]|false> The key bindings of the mode: the key = a command, or a list of commands. false removes a key binding of the built-in config


            """
        for name in classOrder {
            let className = name.isEmpty ? "InlayConfig" : "InlayConfig.\(name)"
            let variable = className.replacingOccurrences(of: ".", with: "_")
            out += "---@class \(className)\nlocal \(variable) = {}\n\n"
            for entry in classes[name] ?? [] {
                let key = String(entry.path.split(separator: ".").last ?? "")
                var doc = entry.comment
                if let possible = entry.possibleValues { doc.append("Possible values: \(possible)") }
                if let fallback = entry.fallbackText { doc.append("Default: \(fallback)") }
                for line in doc { out += "--- \(line)\n" }
                out += "---@type \(type(of: entry, reference))?\n"
                let access = key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil ? ".\(key)" : "['\(key)']"
                out += "\(variable)\(access) = nil\n\n"
            }
        }
        out += functions
        // 'true' and 'false' are words of Lua: inlay.dsp['true']() still works
        let commands = CmdKind.allCases.map(\.rawValue).filter { !["true", "false"].contains($0) }.sorted()
        out += "---@class inlay.dsp: { [string]: fun(...: any): string }\n"
        for command in commands {
            let name = command == "exec-and-forget" ? "exec" : command.replacingOccurrences(of: "-", with: "_")
            out += "---@field \(name) fun(...: any): string '\(command) …'\n"
        }
        out += "inlay.dsp = {}\n"
        return out
    }

    /// The functions of inlay. See: the prelude of LuaConfigLoader, and the header of config-reference.lua
    private static let functions = """
        ---@class inlay
        inlay = {}

        ---@class inlay.bind_options
        ---@field mode? string The binding mode: 'main' without it

        ---@alias inlay.command string|string[]

        --- The keys of the config, in a table. Many calls are merged: the tables key by key, the lists one after the
        --- other, and for anything else the last one wins
        ---@param values InlayConfig
        function inlay.config(values) end

        --- The look of the borders and of the menu bar: the name of a theme, or a table
        ---@param theme string|table
        function inlay.theme(theme) end

        --- A workspace. Yours replace the 7 of the built-in config
        ---@param workspace InlayConfig.workspaces
        function inlay.workspace(workspace) end

        --- A key binding: the keys, and a command or a list of commands
        ---@param keys string 'cmd-alt-h'
        ---@param command inlay.command
        ---@param options? inlay.bind_options
        function inlay.bind(keys, command, options) end

        --- Removes a key binding of the built-in config
        ---@param keys string
        ---@param options? inlay.bind_options
        function inlay.unbind(keys, options) end

        --- A window rule, or 'workspaces': the place of the rules of the apps of the workspaces
        ---@param rule InlayConfig.on_window_detected|'workspaces'
        function inlay.window_rule(rule) end

        --- Commands that run on an event. workspace_changed: a program and its arguments
        ---@param event 'start'|'focus_changed'|'monitor_changed'|'mode_changed'|'workspace_changed'
        ---@param commands inlay.command
        function inlay.on(event, commands) end

        --- A variable of the programs that Inlay starts. ${NAME} is replaced by the value of the variable
        ---@param name string
        ---@param value string
        function inlay.env(name, value) end

        --- A curve of your own for the animations
        ---@param name string
        ---@param points number[] { x1, y1, x2, y2 }
        function inlay.curve(name, points) end

        ---@class inlay.animation: InlayConfig.animations
        ---@field leaf 'global'|'open'|'move'|'fullscreen'|'workspace'
        ---@field curve? string
        ---@field duration? integer

        --- An animation: leaf, and its keys
        ---@param animation inlay.animation
        function inlay.animation(animation) end

        ---@param name string A file of the config folder, without .lua: 'binds', 'conf.binds' for conf/binds.lua
        ---@return any
        function require(name) end


        """

    private static func type(of entry: ConfigReference.Entry, _ reference: ConfigReference) -> String {
        if let free = freeFormTables[entry.path] { return free }
        if let array = arrays[entry.path] { return array }
        if entry.path == "theme" { return "string|table" }
        if entry.isTable { return "InlayConfig.\(entry.path)" }
        // A number of points, or one for each monitor
        if entry.path.hasPrefix("gaps.") { return "integer|table" }
        if let possible = entry.possibleValues {
            if possible.contains("true|false") { return "boolean" }
            if possible.range(of: #"^-?[0-9]+(\.[0-9]+)? \.\.\. "#, options: .regularExpression) != nil {
                return possible.prefix { $0 != " " }.contains(".") ? "number" : "integer"
            }
            let options = possible.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            if options.count > 1, options.allSatisfy({ $0.range(of: #"^'[^' ]+'$"#, options: .regularExpression) != nil }) {
                return options.joined(separator: "|")
            }
            // 'pills|chips|hypr': the names of a string value
            if entry.fallback?.hasPrefix("'") == true, options.allSatisfy({ $0.range(of: #"^[A-Za-z][A-Za-z0-9-]*$"#, options: .regularExpression) != nil }) {
                return options.map { "'\($0)'" }.joined(separator: "|")
            }
            if options.count > 1, options.allSatisfy({ $0.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil }) {
                return "integer"
            }
            if possible.contains("'") || possible.contains("#") { return "string" }
        }
        let isCommands = entry.comment.joined(separator: " ").contains("a list of commands")
        switch entry.fallback ?? entry.value {
            case "true"?, "false"?: return "boolean"
            case let value? where Double(value) != nil: return value.contains(".") ? "number" : "integer"
            case let value? where value.hasPrefix("'"): return isCommands ? "string|string[]" : "string"
            case let value? where value.hasPrefix("{"):
                if isCommands { return "string|string[]" }
                // A list of strings ({ '1', '2' }), or a pattern and a list of them (monitor)
                if let example = entry.value, example.hasPrefix("{ '") { return entry.path.hasSuffix("monitor") ? "string|string[]" : "string[]" }
                return "table"
            default: return "any"
        }
    }
}

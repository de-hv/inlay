import CLua
import Common
import Foundation

/// A file that a Lua config is made of, with the text that was run
struct LuaConfigFile: Equatable, Sendable {
    let url: URL?
    /// nil: a module that `require` couldn't read. Creating it must reload the config
    let text: String?
    /// The call of `require` that read it first: 'inlay.lua:3'. nil: the main file
    var requiredAt: String? = nil
}

/// What running a Lua config gives
struct LuaConfig {
    /// The table of the config: what the calls of `inlay` made (or, for a theme, what the file returns). Empty if it
    /// couldn't be run
    var table: OrderedJson.JsonDict
    /// The main file first, then every module, in the order of the first `require`. Also the ones read before an
    /// error, and the one that couldn't be read: fixing them must reload the config
    var files: [LuaConfigFile]
    var errors: [ConfigParseDiagnostic]
    /// Where each value was set: 'binds.lua:12'. The keys are the paths of the values in `table`; an item of a list
    /// (a workspace, a window rule) is at its number, from 1: ["onWindowDetected", "2"]
    var origins: [[String]: String] = [:]
}

/// Runs the config. `inlay.lua` doesn't return a table: it calls the functions of `inlay` (inlay.config,
/// inlay.bind, inlay.window_rule…), which make the same OrderedJson that the parsers of the config read.
/// The Lua it runs can't reach the system:
/// - only the base, string, table, math and utf8 libraries, without dofile and loadfile, and `load` only takes text;
/// - `require(name)` runs `<name>.lua` of the folder of the main file, once, like the require of Lua (`a.b`:
///   `a/b.lua`);
/// - a config that runs for too long (an endless loop) is stopped.
///
/// A table is an array when its keys are 1…n, and a table of keys when they are all strings. The empty table is a
/// table of keys: the parsers take it as an empty array too
enum LuaConfigLoader {
    enum Kind {
        /// A config: the calls of `inlay` make it, and the file returns nothing
        case config
        /// A file that returns a table of keys: a theme
        case table
    }

    /// Runs the file and the modules of its folder
    static func load(file: URL, kind: Kind = .config) -> LuaConfig {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            let message = "Can't read contents of \(file.path.singleQuoted) as a utf8 string"
            return LuaConfig(table: [:], files: [], errors: [.init(.emptyRoot, message, preventConfigReload: true)])
        }
        return load(text, url: file, kind: kind)
    }

    /// - Parameter url: where the text comes from: its name is the name of the file in the errors, and its folder has the
    ///   modules. Without it, `require` fails
    static func load(_ text: String, url: URL? = nil, kind: Kind = .config) -> LuaConfig {
        let state = unsafe luaL_newstate().orDie("Lua can't allocate its state")
        defer { unsafe lua_close(state) }
        var config = LuaConfig(table: [:], files: [LuaConfigFile(url: url, text: text)], errors: [])

        unsafe openLibraries(state)
        unsafe lua_sethook(state, stopEndlessConfig, LUA_MASKCOUNT, maxInstructions)

        // The prelude leaves its state (the modules it reads, the config that the calls make) at the bottom of the stack
        let folder = url?.deletingLastPathComponent()
        let name = url?.lastPathComponent ?? "inlay.lua"
        let isPreludeLoaded = unsafe run(state, prelude, chunkName: "=inlay", arguments: { state in
            unsafe lua_pushcclosure(state, readModule, 0)
            if let folder { unsafe lua_pushstring(state, folder.path) } else { unsafe lua_pushnil(state) }
            unsafe lua_pushstring(state, name)
            return 3
        })
        guard isPreludeLoaded else { die("The prelude of the Lua config fails: \(unsafe popString(state) ?? "")") }
        let preludeIndex = unsafe lua_gettop(state)

        let isRun = unsafe run(state, text, chunkName: "@" + name, arguments: { _ in 0 })
        config.files += unsafe readModules(state, preludeIndex, folder: folder)
        guard isRun else {
            config.errors.append(.init(.emptyRoot, unsafe popString(state) ?? "\(name) fails", preventConfigReload: true))
            return config
        }

        switch kind {
            case .table:
                guard unsafe lua_type(state, -1) == LUA_TTABLE else {
                    let message = "\(name) must return the table of the config. It returns: \(unsafe typeName(state, -1))"
                    config.errors.append(.init(.emptyRoot, message, preventConfigReload: true))
                    return config
                }
            case .config:
                switch unsafe lua_type(state, -1) {
                    case LUA_TNIL: break
                    case LUA_TTABLE:
                        config.errors.append(.init(.emptyRoot, """
                            \(name) returns a table: the config is no longer a table that it returns, but calls. Put the \
                            table in inlay.config({ … }) (the key bindings in inlay.bind, the window rules in inlay.window_rule, \
                            the workspaces in inlay.workspace), and require('name') the other files. 'inlay config --explain inlay' tells how
                            """, preventConfigReload: true))
                        return config
                    default:
                        let message = "\(name) returns a \(unsafe typeName(state, -1)): the config is the calls of inlay (inlay.config, inlay.bind…), and it returns nothing"
                        config.errors.append(.init(.emptyRoot, message, preventConfigReload: true))
                        return config
                }
                unsafe lua_settop(state, -2)
                unsafe lua_getfield(state, preludeIndex, "config")
                config.origins = unsafe readOrigins(state, preludeIndex)
        }
        var path: Set<Int> = []
        switch unsafe toJson(state, -1, .emptyRoot, &path, &config.errors) {
            case .dict(let table)?: config.table = table
            default:
                config.errors.append(.init(.emptyRoot, "\(name) must return a table of keys, not an array", preventConfigReload: true))
        }
        return config
    }

    /// Enough for any config. An endless loop reaches it in a fraction of a second
    static let maxInstructions: Int32 = 10_000_000

    private static let maxDepth = 64

    private static func openLibraries(_ state: OpaquePointer) {
        let libraries: [(String, lua_CFunction)] = unsafe [
            ("_G", luaopen_base), ("string", luaopen_string), ("table", luaopen_table),
            ("math", luaopen_math), ("utf8", luaopen_utf8),
            // For the lines of the errors of the prelude, which takes it away
            ("debug", luaopen_debug),
        ]
        for unsafe (name, open) in unsafe libraries {
            unsafe luaL_requiref(state, name, open, 1)
            unsafe lua_settop(state, -2)
        }
        for global in ["dofile", "loadfile"] {
            unsafe lua_pushnil(state)
            unsafe lua_setglobal(state, global)
        }
    }

    /// Loads and runs the text. Its result stays on the stack (nil if it returns nothing), or the message of its error
    private static func run(_ state: OpaquePointer, _ text: String, chunkName: String, arguments: (OpaquePointer) -> Int32) -> Bool {
        let bytes = Array(text.utf8)
        let status = bytes.withUnsafeBufferPointer { buffer in
            unsafe buffer.withMemoryRebound(to: CChar.self) { chars in
                // "t": text only. Precompiled chunks can break the state of Lua
                unsafe luaL_loadbufferx(state, chars.baseAddress, chars.count, chunkName, "t")
            }
        }
        guard status == LUA_OK else { return false }
        return unsafe lua_pcallk(state, arguments(state), 1, 0, 0, nil) == LUA_OK
    }

    /// The modules that the prelude has read: `{ { name = 'binds', text = '…' }, … }`, in its state at the index
    private static func readModules(_ state: OpaquePointer, _ preludeIndex: Int32, folder: URL?) -> [LuaConfigFile] {
        guard let folder else { return [] }
        unsafe lua_getfield(state, preludeIndex, "modules")
        let index = unsafe lua_gettop(state)
        defer { unsafe lua_settop(state, -2) }
        let count = unsafe lua_rawlen(state, index)
        guard count > 0 else { return [] }
        return (1 ... Int64(count)).compactMap { i in
            unsafe lua_rawgeti(state, index, i)
            defer { unsafe lua_settop(state, -2) }
            unsafe lua_getfield(state, -1, "name")
            unsafe lua_getfield(state, -2, "text")
            unsafe lua_getfield(state, -3, "from")
            defer { unsafe lua_settop(state, -4) }
            guard let name = unsafe string(state, -3) else { return nil }
            return LuaConfigFile(url: moduleUrl(folder, name), text: unsafe string(state, -2), requiredAt: unsafe string(state, -1))
        }
    }

    static func moduleUrl(_ folder: URL, _ name: String) -> URL { folder.appending(path: name + ".lua") }

    /// Where the calls of `inlay` set each value: `{ { path = { 'mode', 'main', 'binding', 'cmd-alt-h' }, place = 'binds.lua:3' }, … }`.
    /// A later call over the same path wins, like its value
    private static func readOrigins(_ state: OpaquePointer, _ preludeIndex: Int32) -> [[String]: String] {
        unsafe lua_getfield(state, preludeIndex, "origins")
        defer { unsafe lua_settop(state, -2) }
        var path: Set<Int> = []
        var errors: [ConfigParseDiagnostic] = []
        guard case .array(let items)? = unsafe toJson(state, -1, .emptyRoot, &path, &errors) else { return [:] }
        var origins: [[String]: String] = [:]
        for item in items {
            guard let dict = item.asDictOrNil, let place = dict["place"]?.asStringOrNil else { continue }
            let keys = dict["path"]?.asArrayOrNil?.compactMap(\.asStringOrNil) ?? []
            origins[keys] = place
        }
        return origins
    }

    /// The value at the index as OrderedJson. `path`: the tables that contain it, to tell a table that contains
    /// itself. nil: the value can't be one, and an error says why
    private static func toJson(
        _ state: OpaquePointer,
        _ index: Int32,
        _ backtrace: ConfigBacktrace,
        _ path: inout Set<Int>,
        _ errors: inout [ConfigParseDiagnostic],
    ) -> OrderedJson? {
        switch unsafe lua_type(state, index) {
            case LUA_TBOOLEAN: return .bool(unsafe lua_toboolean(state, index) != 0)
            case LUA_TNUMBER:
                if unsafe lua_isinteger(state, index) != 0 { return .int(unsafe lua_tointegerx(state, index, nil)) }
                let number = unsafe lua_tonumberx(state, index, nil)
                // 3 / 1 is 3.0 in Lua: a whole number is an integer for the parsers too
                return Int64(exactly: number).map(OrderedJson.int) ?? .double(number)
            case LUA_TSTRING:
                if let string = unsafe string(state, index) { return .string(string) }
                errors.append(.init(backtrace, "The string isn't valid UTF-8"))
                return nil
            case LUA_TTABLE: return unsafe tableToJson(state, unsafe lua_absindex(state, index), backtrace, &path, &errors)
            default:
                errors.append(.init(backtrace, "Unsupported Lua type: \(unsafe typeName(state, index))"))
                return nil
        }
    }

    private static func tableToJson(
        _ state: OpaquePointer,
        _ index: Int32,
        _ backtrace: ConfigBacktrace,
        _ path: inout Set<Int>,
        _ errors: inout [ConfigParseDiagnostic],
    ) -> OrderedJson? {
        // The address of the table tells it apart
        let pointer = Int(bitPattern: unsafe lua_topointer(state, index))
        guard path.count < maxDepth, unsafe lua_checkstack(state, 4) != 0 else {
            errors.append(.init(backtrace, "The tables are nested too deep"))
            return nil
        }
        guard path.insert(pointer).inserted else {
            errors.append(.init(backtrace, "The table contains itself"))
            return nil
        }
        defer { path.remove(pointer) }

        var keys: [String: OrderedJson] = [:]
        var items: [Int64: OrderedJson] = [:]
        var isValid = true
        unsafe lua_pushnil(state)
        while unsafe lua_next(state, index) != 0 {
            defer { unsafe lua_settop(state, -2) } // The value. The key stays for lua_next
            switch unsafe lua_type(state, -2) {
                case LUA_TSTRING:
                    guard let key = unsafe string(state, -2) else {
                        errors.append(.init(backtrace, "A key isn't valid UTF-8"))
                        isValid = false
                        continue
                    }
                    if let value = unsafe toJson(state, -1, backtrace + .key(key), &path, &errors) { keys[key] = value }
                case LUA_TNUMBER where unsafe lua_isinteger(state, -2) != 0:
                    let i = unsafe lua_tointegerx(state, -2, nil)
                    // The parsers count the items of an array from 0
                    if let value = unsafe toJson(state, -1, backtrace + .index(Int(i) - 1), &path, &errors) { items[i] = value }
                default:
                    errors.append(.init(backtrace, "A key is a \(unsafe typeName(state, -2)): keys are strings, or 1, 2, 3… in an array"))
                    isValid = false
            }
        }
        guard isValid else { return nil }

        switch (keys.isEmpty, items.isEmpty) {
            case (_, true):
                var dict = OrderedJson.JsonDict()
                for (key, value) in keys.sortedEntries { dict[key] = value }
                return .dict(dict)
            case (true, false):
                guard items.keys.sorted() == Array(1 ... Int64(items.count)) else {
                    errors.append(.init(backtrace, "The array has holes: its items must be 1, 2, 3… with no nil between them"))
                    return nil
                }
                return .array(items.sortedEntries.map(\.value))
            case (false, false):
                errors.append(.init(backtrace, "The table mixes keys and the items of an array"))
                return nil
        }
    }

    private static func string(_ state: OpaquePointer, _ index: Int32) -> String? {
        var length = 0
        guard let chars = unsafe lua_tolstring(state, index, &length) else { return nil }
        return unsafe String(bytes: UnsafeRawBufferPointer(start: chars, count: length), encoding: .utf8)
    }

    private static func popString(_ state: OpaquePointer) -> String? {
        defer { unsafe lua_settop(state, -2) }
        return unsafe string(state, -1)
    }

    private static func typeName(_ state: OpaquePointer, _ index: Int32) -> String {
        unsafe String(cString: lua_typename(state, lua_type(state, index)))
    }

    /// The Lua side: `require` and the API of `inlay`. It is called with the function that reads a module, the folder
    /// of the config (nil without one) and the name of the main file, and returns its state:
    /// `{ modules = { { name = 'binds', text = '…' }, … }, config = { … }, origins = { { path = { … }, place = 'binds.lua:3' }, … } }`.
    /// The functions of `inlay` fill `config`, the same table of keys that the parsers read, and `origins`, where each
    /// value was set
    private static let prelude = """
        local readModule, folder, mainFile = ...
        local modules, loaded, loading = {}, {}, {}
        local rawLoad, getinfo = load, debug.getinfo
        debug = nil

        -- The file that runs now: the place of an error when the line is unknown
        local currentFile = mainFile

        -- 'file:line' of the code at the level of the stack. A tail call (return require('x')) leaves no line
        local function place(level)
          local info = getinfo(level + 1, 'Sl')
          if info and info.currentline > 0 and info.source ~= '=inlay' then
            return info.short_src .. ':' .. info.currentline
          end
          return currentFile
        end

        -- The same, for the first level at or above it that is code of the config, not of here
        local function placeOfConfig(level)
          level = level + 1
          local info = getinfo(level, 'S')
          while info and info.source == '=inlay' do
            level = level + 1
            info = getinfo(level, 'S')
          end
          return place(level - 1)
        end

        local function where(level) return place(level + 1) .. ': ' end

        function require(name)
          if type(name) ~= 'string' or not name:match('^[%w_%-]+$') and not name:match('^[%w_%-]+[%w_%-%.]*[%w_%-]$') or name:find('%.%.') then
            error(where(2) .. "require: '" .. tostring(name) .. "' isn't a file of the config folder: write its name without .lua (a.b for a/b.lua)", 0)
          end
          local path = name:gsub('%.', '/')
          if loaded[path] ~= nil then return loaded[path] end
          if loading[path] then error(where(2) .. 'require: ' .. path .. '.lua requires itself', 0) end
          if not folder then error(where(2) .. 'require: this config has no folder', 0) end
          local text, problem = readModule(folder .. '/' .. path .. '.lua')
          modules[#modules + 1] = { name = path, text = text, from = place(2) }
          if not text then error(where(2) .. 'require: ' .. problem, 0) end
          local chunk, syntaxError = rawLoad(text, '@' .. path .. '.lua', 't')
          if not chunk then error(syntaxError, 0) end
          local previousFile = currentFile
          loading[path], currentFile = true, path .. '.lua'
          local value = chunk()
          loading[path], currentFile = nil, previousFile
          if value == nil then value = true end
          loaded[path] = value
          return value
        end

        -- Only text: a precompiled chunk can break the state of Lua
        function load(chunk, chunkName, _, ...)
          return rawLoad(chunk, chunkName, 't', ...)
        end

        local function isArray(t)
          local count = 0
          for _ in pairs(t) do count = count + 1 end
          return count > 0 and count == #t
        end

        -- A table that contains itself stays so: the error of the config says it
        local function copy(value, seen)
          if type(value) ~= 'table' then return value end
          seen = seen or {}
          if seen[value] then return seen[value] end
          local result = {}
          seen[value] = result
          for k, v in pairs(value) do result[k] = copy(v, seen) end
          return result
        end

        -- nil, or why the tables can't be merged
        local function mergeInto(target, source)
          for key, value in pairs(source) do
            local current = target[key]
            if type(current) == 'table' and type(value) == 'table' and next(current) ~= nil then
              if next(value) == nil then
                -- An empty table adds nothing
              elseif isArray(current) and isArray(value) then
                for _, item in ipairs(value) do current[#current + 1] = copy(item) end
              elseif not isArray(current) and not isArray(value) then
                local problem = mergeInto(current, value)
                if problem then return problem end
              else
                return "'" .. tostring(key) .. "' is an array in one table and a table of keys in another"
              end
            else
              target[key] = copy(value)
            end
          end
        end

        -- What the functions of inlay make: the table of the config, and where each value comes from
        local config, origins = {}, {}

        local function record(path, at)
          origins[#origins + 1] = { path = path, place = at }
        end

        -- Every value of the table, under the path: a table of keys is gone into; a list and a value are one
        local function recordValues(path, value, at)
          if type(value) == 'table' and next(value) ~= nil and not isArray(value) and #path < 16 then
            for key, child in pairs(value) do
              if type(key) == 'string' then
                local childPath = { table.unpack(path) }
                childPath[#childPath + 1] = key
                recordValues(childPath, child, at)
              end
            end
          else
            record(path, at)
          end
        end

        -- The table of keys at the path of the config, made if it isn't there
        local function tableAt(...)
          local t = config
          for _, key in ipairs({ ... }) do
            if type(t[key]) ~= 'table' then t[key] = {} end
            t = t[key]
          end
          return t
        end

        local function fail(name, message) error(placeOfConfig(2) .. ': inlay.' .. name .. ': ' .. message, 0) end

        local function isTableOfKeys(value) return type(value) == 'table' and not isArray(value) end

        local function checkOptions(name, options, allowed)
          if options == nil then return {} end
          if not isTableOfKeys(options) then fail(name, 'the options are a table, like { mode = \\'service\\' }') end
          for key in pairs(options) do
            if not allowed[key] then fail(name, "'" .. tostring(key) .. "' isn't an option") end
          end
          return options
        end

        local function isCommand(value)
          if type(value) == 'string' then return true end
          if type(value) ~= 'table' or (next(value) ~= nil and not isArray(value)) then return false end
          for _, item in ipairs(value) do if type(item) ~= 'string' then return false end end
          return true
        end

        local function appendItem(key, item, at)
          local list = config[key]
          if type(list) ~= 'table' then
            list = {}
            config[key] = list
            record({ key }, at)
          end
          list[#list + 1] = copy(item)
          record({ key, tostring(#list) }, at)
        end

        inlay = {}

        function inlay.config(values)
          if not isTableOfKeys(values) then fail('config', 'it takes a table of keys, like { gaps = { inner = 8 } }') end
          local problem = mergeInto(config, values)
          if problem then fail('config', problem) end
          recordValues({}, values, place(2))
        end

        function inlay.theme(theme)
          if type(theme) ~= 'string' and type(theme) ~= 'table' then
            fail('theme', 'it takes the name of a theme, or a table: { extends = \\'gruvbox\\', borders = { … } }')
          end
          config.theme = copy(theme)
          record({ 'theme' }, place(2))
        end

        function inlay.workspace(workspace)
          if not isTableOfKeys(workspace) then fail('workspace', "it takes a table: { id = '1', key = 'h', apps = { … } }") end
          appendItem('workspaces', workspace, place(2))
        end

        local bindOptions = { mode = true }

        local function bindingsOf(name, options)
          local mode = checkOptions(name, options, bindOptions).mode or 'main'
          if type(mode) ~= 'string' then fail(name, 'mode is the name of a binding mode') end
          return mode, tableAt('mode', mode, 'binding')
        end

        function inlay.bind(keys, command, options)
          if type(keys) ~= 'string' then fail('bind', "the keys are a string, like 'cmd-alt-h'") end
          if not isCommand(command) then fail('bind', 'the command is a string, or a list of them') end
          local mode, bindings = bindingsOf('bind', options)
          bindings[keys] = copy(command)
          record({ 'mode', mode, 'binding', keys }, place(2))
        end

        function inlay.unbind(keys, options)
          if type(keys) ~= 'string' then fail('unbind', "the keys are a string, like 'cmd-alt-h'") end
          local mode, bindings = bindingsOf('unbind', options)
          bindings[keys] = false
          record({ 'mode', mode, 'binding', keys }, place(2))
        end

        function inlay.window_rule(rule)
          if rule ~= 'workspaces' and not isTableOfKeys(rule) then
            fail('window_rule', "it takes a table, { match = { appId = '…' }, run = 'layout floating' }, or 'workspaces'")
          end
          appendItem('onWindowDetected', rule, place(2))
        end

        local events = {
          start = 'afterStartupCommand',
          focus_changed = 'onFocusChanged',
          monitor_changed = 'onFocusedMonitorChanged',
          mode_changed = 'onModeChanged',
          workspace_changed = 'execOnWorkspaceChange',
        }

        function inlay.on(event, commands)
          local key = events[event]
          if not key then fail('on', "'" .. tostring(event) .. "' isn't an event: start, focus_changed, monitor_changed, mode_changed or workspace_changed") end
          if not isCommand(commands) then fail('on', 'the commands are a string, or a list of them') end
          local at = place(2)
          if key == 'execOnWorkspaceChange' then
            -- A program and its arguments: one, the last one
            config[key] = copy(type(commands) == 'string' and { commands } or commands)
          else
            local list = config[key]
            if type(list) ~= 'table' then list = {} config[key] = list end
            if type(commands) == 'string' then commands = { commands } end
            for _, command in ipairs(commands) do list[#list + 1] = command end
          end
          record({ key }, at)
        end

        function inlay.env(name, value)
          if type(name) ~= 'string' or type(value) ~= 'string' then fail('env', "it takes a name and a value: inlay.env('PATH', '/opt/homebrew/bin:${PATH}')") end
          tableAt('exec', 'envVars')[name] = value
          record({ 'exec', 'envVars', name }, place(2))
        end

        function inlay.curve(name, points)
          if type(name) ~= 'string' or type(points) ~= 'table' then fail('curve', 'it takes a name and { x1, y1, x2, y2 }') end
          tableAt('animations', 'curves')[name] = copy(points)
          record({ 'animations', 'curves', name }, place(2))
        end

        local leaves = { global = true, open = true, move = true, fullscreen = true, workspace = true }

        function inlay.animation(animation)
          if not isTableOfKeys(animation) or not leaves[animation.leaf] then
            fail('animation', "it takes { leaf = 'open', curve = 'quint', duration = 200 }. leaf: global, open, move, fullscreen or workspace")
          end
          local values = copy(animation)
          local leaf = values.leaf
          values.leaf = nil
          local path = leaf == 'global' and { 'animations' } or { 'animations', leaf }
          local problem = mergeInto(tableAt(table.unpack(path)), values)
          if problem then fail('animation', problem) end
          recordValues(path, values, place(2))
        end

        -- The commands, as functions: inlay.dsp.focus('left') is 'focus left'. Each one gives the string
        local aliases = { exec = 'exec-and-forget' }
        inlay.dsp = setmetatable({}, {
          __index = function(_, name)
            local command = aliases[name] or tostring(name):gsub('_', '-')
            return function(...)
              local parts = { command }
              for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
              return table.concat(parts, ' ')
            end
          end,
        })

        function inlay.merge()
          error(where(2) .. "inlay.merge is gone: require('name') runs name.lua, whose inlay.config, inlay.bind… calls are part of the config", 0)
        end

        return { modules = modules, config = config, origins = origins }
        """
}


/// `readModule(path)`: the text of the file, or nil and why. It never raises an error: a Lua error would jump over
/// the Swift code
private func readModule(_ state: OpaquePointer?) -> Int32 {
    var length = 0
    guard let state = unsafe state, let chars = unsafe lua_tolstring(state, 1, &length),
          let path = unsafe String(bytes: UnsafeRawBufferPointer(start: chars, count: length), encoding: .utf8)
    else {
        unsafe lua_pushnil(state)
        unsafe lua_pushstring(state, "the path isn't valid UTF-8")
        return 2
    }
    let url = URL(filePath: path)
    if let text = try? String(contentsOf: url, encoding: .utf8) {
        unsafe lua_pushstring(state, text)
        return 1
    }
    let name = url.lastPathComponent
    let folder = url.deletingLastPathComponent().path.tildePath
    unsafe lua_pushnil(state)
    unsafe lua_pushstring(state, FileManager.default.fileExists(atPath: path)
        ? "can't read \(name) of \(folder) as a utf8 string"
        : "there is no \(name) in \(folder)")
    return 2
}

/// The count hook: the config has run LuaConfigLoader.maxInstructions instructions
private func stopEndlessConfig(_ state: OpaquePointer?, _: UnsafeMutablePointer<lua_Debug>?) {
    guard let state = unsafe state else { return }
    unsafe luaL_where(state, 0) // 0: the function that runs, not the hook
    unsafe lua_pushstring(state, "the config runs for too long: is there an endless loop?")
    unsafe lua_concat(state, 2)
    _ = unsafe lua_error(state) // Doesn't return
}

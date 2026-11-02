import CLua
import Common
import Foundation

/// A file that a Lua config is made of, with the text that was run
struct LuaConfigFile: Equatable, Sendable {
    let url: URL?
    let text: String
}

/// What running a Lua config gives
struct LuaConfig {
    /// The table that the main file returns. Empty if it couldn't be run
    var table: OrderedJson.JsonDict
    /// The main file first, then every module, in the order of the first `require`. Also the ones read before an
    /// error: fixing them must reload the config
    var files: [LuaConfigFile]
    var errors: [ConfigParseDiagnostic]
}

/// Runs the config: `inlay.lua` returns a table, which becomes the same OrderedJson that the parsers of the config
/// read. The Lua it runs can't reach the system:
/// - only the base, string, table, math and utf8 libraries, without dofile and loadfile, and `load` only takes text;
/// - `require(name)` loads `<name>.lua` of the folder of the main file, once, like the require of Lua;
/// - `inlay.merge(...)` puts tables together: the tables of the same key are merged, the arrays are concatenated, and
///   for anything else the last one wins;
/// - a config that runs for too long (an endless loop) is stopped.
///
/// A table is an array when its keys are 1…n, and a table of keys when they are all strings. The empty table is a
/// table of keys: the parsers take it as an empty array too
enum LuaConfigLoader {
    /// Runs the file and the modules of its folder
    static func load(file: URL) -> LuaConfig {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            let message = "Can't read contents of \(file.path.singleQuoted) as a utf8 string"
            return LuaConfig(table: [:], files: [], errors: [.init(.emptyRoot, message, preventConfigReload: true)])
        }
        return load(text, url: file)
    }

    /// - Parameter url: where the text comes from: its name is the name of the file in the errors, and its folder has the
    ///   modules. Without it, `require` fails
    static func load(_ text: String, url: URL? = nil) -> LuaConfig {
        let state = unsafe luaL_newstate().orDie("Lua can't allocate its state")
        defer { unsafe lua_close(state) }
        var config = LuaConfig(table: [:], files: [LuaConfigFile(url: url, text: text)], errors: [])

        unsafe openLibraries(state)
        unsafe lua_sethook(state, stopEndlessConfig, LUA_MASKCOUNT, maxInstructions)

        // The prelude leaves the table of the modules it reads at the bottom of the stack
        let folder = url?.deletingLastPathComponent()
        let name = url?.lastPathComponent ?? "inlay.lua"
        let isPreludeLoaded = unsafe run(state, prelude, chunkName: "=inlay", arguments: { state in
            unsafe lua_pushcclosure(state, readModule, 0)
            if let folder { unsafe lua_pushstring(state, folder.path) } else { unsafe lua_pushnil(state) }
            unsafe lua_pushstring(state, name)
            return 3
        })
        guard isPreludeLoaded else { die("The prelude of the Lua config fails: \(unsafe popString(state) ?? "")") }
        let modulesIndex = unsafe lua_gettop(state)

        let isRun = unsafe run(state, text, chunkName: "@" + name, arguments: { _ in 0 })
        guard isRun else {
            config.errors.append(.init(.emptyRoot, unsafe popString(state) ?? "\(name) fails", preventConfigReload: true))
            config.files += unsafe readModules(state, modulesIndex, folder: folder)
            return config
        }
        config.files += unsafe readModules(state, modulesIndex, folder: folder)

        guard unsafe lua_type(state, -1) == LUA_TTABLE else {
            let message = "\(name) must return the table of the config. It returns: \(unsafe typeName(state, -1))"
            config.errors.append(.init(.emptyRoot, message, preventConfigReload: true))
            return config
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

    /// The modules that the prelude has read: `{ { name = 'binds', text = '…' }, … }`
    private static func readModules(_ state: OpaquePointer, _ index: Int32, folder: URL?) -> [LuaConfigFile] {
        guard let folder else { return [] }
        let count = unsafe lua_rawlen(state, index)
        guard count > 0 else { return [] }
        return (1 ... Int64(count)).compactMap { i in
            unsafe lua_rawgeti(state, index, i)
            defer { unsafe lua_settop(state, -2) }
            unsafe lua_getfield(state, -1, "name")
            unsafe lua_getfield(state, -2, "text")
            defer { unsafe lua_settop(state, -3) }
            guard let name = unsafe string(state, -2), let text = unsafe string(state, -1) else { return nil }
            return LuaConfigFile(url: moduleUrl(folder, name), text: text)
        }
    }

    static func moduleUrl(_ folder: URL, _ name: String) -> URL { folder.appending(path: name + ".lua") }

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

    /// The Lua side: `require` and `inlay`. It is called with the function that reads a module, the folder of the
    /// config (nil without one) and the name of the main file, and returns the table of the modules it reads
    private static let prelude = """
        local readModule, folder, mainFile = ...
        local modules, loaded, loading = {}, {}, {}
        local rawLoad, getinfo = load, debug.getinfo
        debug = nil

        -- The file that runs now: the place of an error when the line is unknown
        local currentFile = mainFile

        -- 'file:line: ' of the code at the level of the stack. A tail call (return require('x')) leaves no line
        local function where(level)
          local info = getinfo(level + 1, 'Sl')
          if info and info.currentline > 0 and info.source ~= '=inlay' then
            return info.short_src .. ':' .. info.currentline .. ': '
          end
          return currentFile .. ': '
        end

        function require(name)
          if type(name) ~= 'string' or not name:match('^[%w_%-]+$') then
            error(where(2) .. "require: '" .. tostring(name) .. "' isn't a file of the config folder: write its name without .lua", 0)
          end
          if loaded[name] ~= nil then return loaded[name] end
          if loading[name] then error(where(2) .. 'require: ' .. name .. '.lua requires itself', 0) end
          if not folder then error(where(2) .. 'require: this config has no folder', 0) end
          local text, problem = readModule(folder .. '/' .. name .. '.lua')
          if not text then error(where(2) .. 'require: ' .. problem, 0) end
          modules[#modules + 1] = { name = name, text = text }
          local chunk, syntaxError = rawLoad(text, '@' .. name .. '.lua', 't')
          if not chunk then error(syntaxError, 0) end
          local previousFile = currentFile
          loading[name], currentFile = true, name .. '.lua'
          local value = chunk()
          loading[name], currentFile = nil, previousFile
          if value == nil then value = true end
          loaded[name] = value
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

        local function copy(value)
          if type(value) ~= 'table' then return value end
          local result = {}
          for k, v in pairs(value) do result[k] = copy(v) end
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

        inlay = {}

        function inlay.merge(...)
          local result = {}
          for i = 1, select('#', ...) do
            local part = select(i, ...)
            if type(part) ~= 'table' then
              error(where(2) .. 'inlay.merge: argument ' .. i .. ' is a ' .. type(part) .. ', not a table', 0)
            end
            local problem = mergeInto(result, part)
            if problem then error(where(2) .. 'inlay.merge: ' .. problem, 0) end
          end
          return result
        end

        return modules
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

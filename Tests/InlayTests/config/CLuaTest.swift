import CLua
import Testing

extension InlayTests {
    @Suite struct CLuaTest {
        /// The Lua of Sources/CLua builds, links and runs code
        @Test func testRunsLua() {
            let state = unsafe luaL_newstate()
            defer { unsafe lua_close(state) }
            #expect(unsafe luaL_loadstring(state, "return 1 + 1") == LUA_OK)
            #expect(unsafe lua_pcallk(state, 0, 1, 0, 0, nil) == LUA_OK)
            #expect(unsafe lua_tointegerx(state, -1, nil) == 2)
        }
    }
}

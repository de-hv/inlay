@testable import AppBundle
import Common
import Testing

/// What changed between two texts of the config, and the notice of a reload. See: ConfigDiff, ReloadNotice
extension InlayTests {
    @Suite @MainActor struct ReloadNoticeTest {
        init() {
            setUpWorkspacesForTests()
        }

        // MARK: - ConfigDiff

        @Test func testAChangedValue() {
            assertEquals(
                ConfigDiff.changes(from: "[borders]\n    width = 4\n", to: "[borders]\n    width = 8\n"),
                [ConfigChange(key: "borders.width", old: "4", new: "8")],
            )
        }

        @Test func testCommentsAndFormattingDontCount() {
            let old = """
                [gaps]
                    inner.horizontal = 8
                    outer.top = 8
                """
            let new = """
                # The gaps
                [gaps.outer]
                top =     8   # under the menu bar

                [gaps.inner]
                horizontal = 8
                """
            assertEquals(ConfigDiff.changes(from: old, to: new), [])
        }

        @Test func testAddedAndRemovedKeys_sortedByPath() {
            assertEquals(
                ConfigDiff.changes(
                    from: "auto-reload-config = true\n[menu-bar]\ntheme = 'pills'\n",
                    to: "[menu-bar]\ntheme = 'chips'\n[gaps]\nsmart = true\n",
                ),
                [
                    ConfigChange(key: "auto-reload-config", old: "true", new: nil),
                    ConfigChange(key: "gaps.smart", old: nil, new: "true"),
                    ConfigChange(key: "menu-bar.theme", old: "'pills'", new: "'chips'"),
                ],
            )
        }

        @Test func testArraysAndArraysOfTables() {
            let old = """
                [mode.main.binding]
                cmd-alt-ctrl-j = ['workspace 1', 'mode main']

                [[on-window-detected]]
                if.app-id = 'com.mitchellh.ghostty'
                run = ['layout tiling', 'move-node-to-workspace 1']
                """
            let new = """
                [mode.main.binding]
                cmd-alt-ctrl-j = 'workspace 1'

                [[on-window-detected]]
                if.app-id = 'com.mitchellh.ghostty'
                run = ['layout tiling', 'move-node-to-workspace 2']
                """
            assertEquals(ConfigDiff.changes(from: old, to: new), [
                ConfigChange(key: "mode.main.binding.cmd-alt-ctrl-j", old: "['workspace 1', 'mode main']", new: "'workspace 1'"),
                ConfigChange(
                    key: "on-window-detected[0].run",
                    old: "['layout tiling', 'move-node-to-workspace 1']",
                    new: "['layout tiling', 'move-node-to-workspace 2']",
                ),
            ])
        }

        @Test func testQuotedKeysAndStrings() {
            assertEquals(
                ConfigDiff.changes(from: "[workspace-to-monitor-force-assignment]\n'1' = 'main'\n", to: "[workspace-to-monitor-force-assignment]\n'1' = \"it's\"\n"),
                [ConfigChange(key: "workspace-to-monitor-force-assignment.1", old: "'main'", new: "\"it's\"")],
            )
            assertEquals(
                ConfigDiff.changes(from: "[exec.env-vars]\n'MY VAR' = 'a'\n", to: "[exec.env-vars]\n'MY VAR' = 'b'\n")?.map(\.key),
                ["exec.env-vars.'MY VAR'"],
            )
        }

        @Test func testInvalidToml() {
            assertNil(ConfigDiff.changes(from: "width = 4", to: "width = "))
        }

        // MARK: - ReloadNotice

        @Test func testStyles() {
            let old = "[borders]\nwidth = 4\n"
            let new = "[borders]\nwidth = 8\n"
            assertNil(ReloadNotice(style: .off, fileName: "inlay.toml", oldText: old, newText: new, warningCount: 0))
            assertNil(ReloadNotice(style: .simple, fileName: "inlay.toml", oldText: old, newText: new, warningCount: 0)?.changes)
            assertEquals(
                ReloadNotice(style: .diff, fileName: "inlay.toml", oldText: old, newText: new, warningCount: 0)?.changes,
                [ConfigChange(key: "borders.width", old: "4", new: "8")],
            )
            // Nothing to compare with: no list of changes, rather than a wrong one
            assertNil(ReloadNotice(style: .diff, fileName: "inlay.toml", oldText: nil, newText: new, warningCount: 0)?.changes)
        }

        @Test func testManyChanges_andWarnings() throws {
            let old = (1 ... 6).map { "key\($0) = 1" }.joined(separator: "\n")
            let new = (1 ... 6).map { "key\($0) = 2" }.joined(separator: "\n")
            let notice = try #require(ReloadNotice(style: .diff, fileName: "inlay.toml", oldText: old, newText: new, warningCount: 0))
            assertEquals(notice.shownChanges.map(\.key), ["key1", "key2", "key3", "key4"])
            assertEquals(notice.hiddenChangeCount, 2)
            assertEquals(notice.duration, .milliseconds(2500))

            let withWarnings = try #require(ReloadNotice(style: .simple, fileName: "inlay.toml", oldText: old, newText: new, warningCount: 2))
            assertEquals(withWarnings.duration, .seconds(6))
            assertEquals(withWarnings.hiddenChangeCount, 0)
        }

        // MARK: - The config

        @Test func testParseOnReload() {
            assertEquals(parseConfig("").config.notifications.onReload, .diff)
            let simple = parseConfig("[notifications]\non-reload = 'simple'\n")
            assertEquals(simple.errors, [])
            assertEquals(simple.config.notifications.onReload, .simple)
            let wrong = parseConfig("[notifications]\non-reload = 'loud'\n")
            assertEquals(wrong.errors.map(\.message), ["Can't parse on-reload 'loud'. Possible values: (diff|simple|off)"])
        }

        @Test func testParseSingleWindowKeys() {
            let result = parseConfig("[gaps]\nsmart = true\n[borders]\nhide-when-single = true\n")
            assertEquals(result.errors, [])
            assertEquals(result.config.gaps.smart, true)
            assertEquals(result.config.borders.hideWhenSingle, true)
            assertEquals(parseConfig("").config.gaps.smart, false)
            assertEquals(parseConfig("").config.borders.hideWhenSingle, false)
        }

        /// The settings window writes these keys. The defaults it shows must be the ones of the parser
        @Test func testSettingsKeysAgreeWithTheParser() {
            assertEquals(SettingsKey.gapsSmart.defaultValue, .bool(Gaps.zero.smart))
            assertEquals(SettingsKey.bordersHideWhenSingle.defaultValue, .bool(BordersConfig().hideWhenSingle))
        }
    }
}

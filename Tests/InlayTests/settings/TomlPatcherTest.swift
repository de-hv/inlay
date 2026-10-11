@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite struct TomlPatcherTest {
        private let theme = TomlKeyPath(["menu-bar"], "theme")
        private let focused = TomlKeyPath(["menu-bar", "colors"], "focused")
        private let startAtLogin = TomlKeyPath([], "start-at-login")

        private func set(_ text: String, _ path: TomlKeyPath, _ value: TomlValue, sourceLocation: SourceLocation = #_sourceLocation) -> String {
            do {
                return try TomlPatcher.set(text, path, value)
            } catch {
                Issue.record("\(error)", sourceLocation: sourceLocation)
                return ""
            }
        }

        private func remove(_ text: String, _ path: TomlKeyPath, sourceLocation: SourceLocation = #_sourceLocation) -> String {
            do {
                return try TomlPatcher.remove(text, path)
            } catch {
                Issue.record("\(error)", sourceLocation: sourceLocation)
                return ""
            }
        }

        private func setError(_ text: String, _ path: TomlKeyPath, _ value: TomlValue = .string("x")) -> TomlPatcher.PatchError? {
            do {
                _ = try TomlPatcher.set(text, path, value)
                return nil
            } catch {
                return error
            }
        }

        private func isInvalidToml(_ error: TomlPatcher.PatchError?) -> Bool {
            if case .invalidToml = error { true } else { false }
        }

        // MARK: - Replace

        @Test func testReplaceValue() {
            let text = """
                [menu-bar]
                enabled = true
                theme = 'chips'
                show-mode = false

                """
            assertEquals(set(text, theme, .string("square")), """
                [menu-bar]
                enabled = true
                theme = 'square'
                show-mode = false

                """)
        }

        @Test func testReplaceKeepsCommentsAndSpacing() {
            let text = """
                # The menu bar
                [menu-bar]   # the item
                    theme   =   "chips"    # default: 'chips'
                    # show-mode = true
                    show-mode = false# no space

                [menu-bar.colors]
                focused  = 'auto'            # background of the focused workspace
                occupied = 'auto'            # workspaces with windows

                """
            let patched = set(set(text, theme, .string("minimal")), focused, .string("#D19A66"))
            assertEquals(patched, """
                # The menu bar
                [menu-bar]   # the item
                    theme   =   'minimal'  # default: 'chips'
                    # show-mode = true
                    show-mode = false# no space

                [menu-bar.colors]
                focused  = '#D19A66'         # background of the focused workspace
                occupied = 'auto'            # workspaces with windows

                """)
            // A value right before its comment
            assertEquals(set(patched, TomlKeyPath(["menu-bar"], "show-mode"), .bool(true)).contains("    show-mode = true# no space\n"), true)
            // A longer value never eats the last space before the comment
            assertEquals(
                set("a = 1 # one\n", TomlKeyPath([], "a"), .int(1000)),
                "a = 1000 # one\n",
            )
        }

        @Test func testReplaceOnlyInTheRightTable() {
            let text = """
                theme = 'top'
                [other]
                theme = 'other'
                [menu-bar.colors]
                theme = 'colors'
                [menu-bar]
                theme = 'chips'
                [[menu-bar-list]]
                theme = 'list'

                """
            assertEquals(set(text, theme, .string("square")), text.replacingOccurrences(of: "'chips'", with: "'square'"))
            assertEquals(set(text, TomlKeyPath([], "theme"), .string("x")), text.replacingOccurrences(of: "'top'", with: "'x'"))
        }

        @Test func testValueKinds() {
            let text = "[t]\na = 'x'\nb = true\nc = 4\nd = 0.5\n"
            assertEquals(set(text, TomlKeyPath(["t"], "a"), .string("it's")), "[t]\na = \"it's\"\nb = true\nc = 4\nd = 0.5\n")
            assertEquals(set(text, TomlKeyPath(["t"], "a"), .string("tab\there \"q\" \\")), "[t]\na = \"tab\\there \\\"q\\\" \\\\\"\nb = true\nc = 4\nd = 0.5\n")
            assertEquals(set(text, TomlKeyPath(["t"], "b"), .bool(false)), "[t]\na = 'x'\nb = false\nc = 4\nd = 0.5\n")
            assertEquals(set(text, TomlKeyPath(["t"], "c"), .int(16)), "[t]\na = 'x'\nb = true\nc = 16\nd = 0.5\n")
            assertEquals(set(text, TomlKeyPath(["t"], "d"), .float(0.6)), "[t]\na = 'x'\nb = true\nc = 4\nd = 0.6\n")
            assertEquals(set(text, TomlKeyPath(["t"], "d"), .float(1)), "[t]\na = 'x'\nb = true\nc = 4\nd = 1.0\n")
            // The type of a value can change
            assertEquals(set(text, TomlKeyPath(["t"], "c"), .string("four")), "[t]\na = 'x'\nb = true\nc = 'four'\nd = 0.5\n")
        }

        @Test func testStringsWithHashAndQuotes() {
            let text = """
                [menu-bar.colors]
                focused = "#FF0000" # red, "really"
                accent = '#00FF00'# green

                """
            assertEquals(set(text, focused, .string("#0000FF")), """
                [menu-bar.colors]
                focused = '#0000FF' # red, "really"
                accent = '#00FF00'# green

                """)
            assertEquals(set(text, TomlKeyPath(["menu-bar", "colors"], "accent"), .string("system-accent")), """
                [menu-bar.colors]
                focused = "#FF0000" # red, "really"
                accent = 'system-accent'# green

                """)
        }

        @Test func testIdempotent() {
            let text = "[menu-bar]\ntheme = \"chips\"   # comment\n"
            // The value is already right, however it is spelled: nothing changes
            assertEquals(set(text, theme, .string("chips")), text)
            let once = set(text, theme, .string("square"))
            assertEquals(set(once, theme, .string("square")), once)
            let added = set("", focused, .string("auto"))
            assertEquals(set(added, focused, .string("auto")), added)
            let removed = remove(once, theme)
            assertEquals(remove(removed, theme), removed)
        }

        // MARK: - Insert

        @Test func testAddKeyToTheEndOfItsTable() {
            let text = """
                [menu-bar]
                    enabled = true
                    # About the theme
                    theme = 'chips'

                # The colors
                [menu-bar.colors]
                    focused = 'auto'

                [gaps]
                inner.horizontal = 0

                """
            assertEquals(set(text, TomlKeyPath(["menu-bar"], "show-mode"), .bool(true)), """
                [menu-bar]
                    enabled = true
                    # About the theme
                    theme = 'chips'
                    show-mode = true

                # The colors
                [menu-bar.colors]
                    focused = 'auto'

                [gaps]
                inner.horizontal = 0

                """)
            assertEquals(set(text, TomlKeyPath(["menu-bar", "colors"], "empty"), .string("#6B7280")).contains("    focused = 'auto'\n    empty = '#6B7280'\n\n[gaps]"), true)
            assertEquals(set(text, TomlKeyPath(["gaps"], "x"), .int(1)).hasSuffix("inner.horizontal = 0\nx = 1\n"), true)
        }

        @Test func testAddKeyToAnEmptyTable() {
            assertEquals(set("[menu-bar]\n[other]\na = 1\n", theme, .string("square")), "[menu-bar]\ntheme = 'square'\n[other]\na = 1\n")
            assertEquals(set("a = 1\n  [menu-bar] # empty", theme, .string("square")), "a = 1\n  [menu-bar] # empty\n  theme = 'square'\n")
        }

        @Test func testAddKeyAfterAMultilineValue() {
            let text = """
                [menu-bar]
                theme = 'chips'
                list = [
                    1, # one
                    2,
                ]
                [other]

                """
            assertEquals(set(text, TomlKeyPath(["menu-bar"], "enabled"), .bool(false)), """
                [menu-bar]
                theme = 'chips'
                list = [
                    1, # one
                    2,
                ]
                enabled = false
                [other]

                """)
        }

        @Test func testAddTable() {
            assertEquals(set("", theme, .string("square")), "[menu-bar]\ntheme = 'square'\n")
            assertEquals(set("a = 1\n", theme, .string("square")), "a = 1\n\n[menu-bar]\ntheme = 'square'\n")
            // The last line break is missing
            assertEquals(set("[x]\na = 1", theme, .string("square")), "[x]\na = 1\n\n[menu-bar]\ntheme = 'square'\n")
            // The document already ends with an empty line
            assertEquals(set("[x]\na = 1\n\n", theme, .string("square")), "[x]\na = 1\n\n[menu-bar]\ntheme = 'square'\n")
            // The parent table is added after its child. That's valid TOML
            assertEquals(set("[menu-bar.colors]\nfocused = 'auto'\n", theme, .string("square")), "[menu-bar.colors]\nfocused = 'auto'\n\n[menu-bar]\ntheme = 'square'\n")
            // And a child after its parent
            assertEquals(set("[menu-bar]\ntheme = 'chips'\n[z]\n", focused, .string("auto")), "[menu-bar]\ntheme = 'chips'\n[z]\n\n[menu-bar.colors]\nfocused = 'auto'\n")
            // A key that needs quotes
            assertEquals(set("", TomlKeyPath(["a b", "c"], "d.e"), .int(1)), "['a b'.c]\n'd.e' = 1\n")
        }

        @Test func testAddTopLevelKey() {
            // After the last top level key
            assertEquals(
                set("a = 1\nb = [\n  1,\n]\n\n# The table\n[x]\nc = 1\n", startAtLogin, .bool(true)),
                "a = 1\nb = [\n  1,\n]\nstart-at-login = true\n\n# The table\n[x]\nc = 1\n",
            )
            // No top level keys: before the first table and its comments
            assertEquals(
                set("# The config\n\n# The table\n# of x\n[x]\nc = 1\n", startAtLogin, .bool(true)),
                "# The config\n\nstart-at-login = true\n\n# The table\n# of x\n[x]\nc = 1\n",
            )
            assertEquals(set("[x]\nc = 1\n", startAtLogin, .bool(true)), "start-at-login = true\n\n[x]\nc = 1\n")
            // No tables at all
            assertEquals(set("# Only a comment", startAtLogin, .bool(true)), "# Only a comment\nstart-at-login = true\n")
            assertEquals(set("", startAtLogin, .bool(true)), "start-at-login = true\n")
        }

        @Test func testLineEndings() {
            let text = "[menu-bar]\r\ntheme = 'chips' # comment\r\n\r\n[x]\r\na = 1\r\n"
            assertEquals(set(text, theme, .string("square")), "[menu-bar]\r\ntheme = 'square' # comment\r\n\r\n[x]\r\na = 1\r\n")
            assertEquals(set(text, TomlKeyPath(["menu-bar"], "enabled"), .bool(true)), "[menu-bar]\r\ntheme = 'chips' # comment\r\nenabled = true\r\n\r\n[x]\r\na = 1\r\n")
            assertEquals(set(text, focused, .string("auto")), text + "\r\n[menu-bar.colors]\r\nfocused = 'auto'\r\n")
            assertEquals(remove(text, theme), "[menu-bar]\r\n\r\n[x]\r\na = 1\r\n")
        }

        // MARK: - Remove

        @Test func testRemove() {
            let text = """
                [menu-bar]
                enabled = true
                theme = 'chips' # the theme
                # A comment
                show-mode = false

                """
            assertEquals(remove(text, theme), """
                [menu-bar]
                enabled = true
                # A comment
                show-mode = false

                """)
            // Nothing to remove
            assertEquals(remove(text, focused), text)
            assertEquals(remove("", theme), "")
            // The last line, without a line break
            assertEquals(remove("[menu-bar]\ntheme = 'chips'", theme), "[menu-bar]\n")
            // The table stays, even if it is left empty
            assertEquals(remove("[menu-bar]\ntheme = 'chips'\n[x]\n", theme), "[menu-bar]\n[x]\n")
        }

        // MARK: - Refused

        @Test func testDottedKeys() {
            assertEquals(TomlPatcher.locate("menu-bar.theme = 'chips'\n", theme), .unsupported(.dottedKey))
            assertEquals(TomlPatcher.locate("[menu-bar]\ncolors.focused = 'auto'\n", focused), .unsupported(.dottedKey))
            assertEquals(TomlPatcher.locate("menu-bar.colors.focused = 'auto'\n", focused), .unsupported(.dottedKey))
            // The table of the key is defined with dotted keys: a [menu-bar] header can't be added
            assertEquals(TomlPatcher.locate("menu-bar.enabled = true\n", theme), .unsupported(.dottedKey))
            assertEquals(TomlPatcher.locate("[menu-bar]\ncolors.accent = '#FFFFFF'\n", focused), .unsupported(.dottedKey))
            assertEquals(TomlPatcher.locate("menu-bar . \"colors\".accent = '#FFFFFF'\n", focused), .unsupported(.dottedKey))
            assertEquals(setError("menu-bar.theme = 'chips'\n", theme), .unsupported(.dottedKey))
            // Dotted keys of other tables don't matter
            assertEquals(TomlPatcher.locate("gaps.inner.horizontal = 0\nmenu-bars.theme = 1\n[menu-bar]\ncolor.focused = 1\n", theme), .absent)
            assertEquals(TomlPatcher.locate("[menu-bar]\ncolors.accent = '#FFFFFF'\n", theme), .absent)
        }

        @Test func testInlineTables() {
            assertEquals(TomlPatcher.locate("menu-bar = { theme = 'chips' }\n", theme), .unsupported(.inlineTable))
            assertEquals(TomlPatcher.locate("menu-bar = { enabled = true }\n", theme), .unsupported(.inlineTable))
            assertEquals(TomlPatcher.locate("[menu-bar]\ncolors = { focused = 'auto' }\n", focused), .unsupported(.inlineTable))
            assertEquals(TomlPatcher.locate("menu-bar.colors = { }\n", focused), .unsupported(.inlineTable))
            assertEquals(setError("menu-bar = { theme = 'chips' }\n", theme), .unsupported(.inlineTable))
            do {
                _ = try TomlPatcher.remove("menu-bar = { theme = 'chips' }\n", theme)
                Issue.record("Must be refused")
            } catch {
                assertEquals(error, .unsupported(.inlineTable))
            }
        }

        @Test func testOtherUnsupportedShapes() {
            // A value in several lines
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme = '''\nchips'''\n", theme), .unsupported(.multilineValue))
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme = [\n'chips']\n", theme), .unsupported(.multilineValue))
            // Arrays of tables
            assertEquals(TomlPatcher.locate("[[menu-bar]]\ntheme = 'chips'\n", theme), .unsupported(.arrayOfTables))
            assertEquals(TomlPatcher.locate("[[menu-bar]]\n", focused), .unsupported(.arrayOfTables))
            // The key is a table, the table is a value, or something is there twice
            assertEquals(TomlPatcher.locate("[menu-bar.theme]\n", theme), .unsupported(.conflict))
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme.name = 'chips'\n", theme), .unsupported(.conflict))
            assertEquals(TomlPatcher.locate("menu-bar = 'chips'\n", theme), .unsupported(.conflict))
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme = { name = 'chips' }\n", theme), .unsupported(.conflict))
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme = 'a'\ntheme = 'b'\n", theme), .unsupported(.conflict))
            assertEquals(TomlPatcher.locate("[menu-bar]\n[x]\n[menu-bar]\n", theme), .unsupported(.conflict))
        }

        @Test func testInvalidDocuments() {
            // Nothing is returned if the result isn't valid TOML
            assertEquals(isInvalidToml(setError("[menu-bar\ntheme = 'chips'\n", theme)), true)
            assertEquals(isInvalidToml(setError("a = \n[menu-bar]\ntheme = 'chips'\n", theme, .string("square"))), true)
            // A broken value isn't repaired
            assertEquals(setError("[menu-bar]\ntheme = 'chips' oops\n", theme, .string("square")), .unsupported(.multilineValue))
            assertEquals(setError("[menu-bar]\ntheme = \"chips\" \"oops\"\n", theme, .string("square")), .unsupported(.multilineValue))
            assertEquals(setError("[menu-bar]\ntheme = chips oops # comment\n", theme, .string("square")), .unsupported(.multilineValue))
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme = \"a \\\" b\" # comment\n", theme), .line(1))
            assertEquals(TomlPatcher.locate("[menu-bar]\ntheme = 'a \\' # comment\n", theme), .line(1))
            assertEquals(isInvalidToml(setError("[x]\na = \"not closed\n", theme)), true)
        }

        // MARK: - Not confused by

        @Test func testKeysInsideOfStringsAndArrays() {
            let text = """
                description = \"\"\"
                [menu-bar]
                theme = 'inside of a string'
                \"\"\"
                list = [
                  "theme = 'inside of an array'", # ]
                  '''
                [menu-bar]
                theme = 'literal'
                ''',
                ]
                # [menu-bar]
                # theme = 'comment'
                [other] # [menu-bar]
                theme = 'other'

                """
            assertEquals(TomlPatcher.locate(text, theme), .absent)
            assertEquals(set(text, theme, .string("chips")), text + "\n[menu-bar]\ntheme = 'chips'\n")
        }

        @Test func testQuotedKeysAndHeaders() {
            let text = "[ 'menu-bar' . \"colors\" ]\n\"focused\" = 'auto'\n'accent' = 'system-accent'\n"
            assertEquals(TomlPatcher.locate(text, focused), .line(1))
            assertEquals(set(text, focused, .string("#FFFFFF")), "[ 'menu-bar' . \"colors\" ]\n\"focused\" = '#FFFFFF'\n'accent' = 'system-accent'\n")
            assertEquals(set(text, TomlKeyPath(["menu-bar", "colors"], "accent"), .string("#000000")).contains("'accent' = '#000000'\n"), true)
        }

        @Test func testKeyLiteral() {
            assertEquals(TomlPatcher.keyLiteral("menu-bar"), "menu-bar")
            assertEquals(TomlPatcher.keyLiteral("a_B-9"), "a_B-9")
            assertEquals(TomlPatcher.keyLiteral("a b"), "'a b'")
            assertEquals(TomlPatcher.keyLiteral("a.b"), "'a.b'")
            assertEquals(TomlPatcher.keyLiteral(""), "''")
            assertEquals(TomlPatcher.keyLiteral("it's"), "\"it's\"")
        }

        @Test func testValueLiteral() {
            assertEquals(TomlValue.string("chips").literal, "'chips'")
            assertEquals(TomlValue.string("").literal, "''")
            assertEquals(TomlValue.string("a\nb").literal, "\"a\\nb\"")
            assertEquals(TomlValue.string("\u{1}").literal, "\"\\u0001\"")
            assertEquals(TomlValue.int(-3).literal, "-3")
            assertEquals(TomlValue.float(0.25).literal, "0.25")
            assertEquals(TomlValue.float(2).literal, "2.0")
            assertEquals(TomlValue.bool(true).literal, "true")
            // An int isn't a bool, and the other way around
            assertEquals(TomlValue.int(1).matches(true), false)
            assertEquals(TomlValue.bool(true).matches(Int64(1)), false)
            assertEquals(TomlValue.int(1).matches(Int64(1)), true)
            assertEquals(TomlValue.float(1).matches(1.0), true)
        }

        /// The built-in config and the example of the documentation: every key of the settings window, set and removed
        @Test func testRealConfigs() throws {
            let defaultConfig = try String(contentsOf: projectRoot.appending(path: "docs/config-examples/default-config.toml"), encoding: .utf8)
            for key in [
                SettingsKey.startAtLogin, .autoReloadConfig, .newWindowPlacement, .menuBarEnabled, .menuBarTheme, .menuBarShowAppIcons,
                .menuBarDimEmpty, .menuBarShowMode, .menuBarAccent, .menuBarFocused, .menuBarOccupied, .menuBarEmpty,
                .bordersEnabled, .bordersWidth, .bordersCornerRadius, .bordersActiveColor, .bordersInactiveColor, .bordersFloatingColor,
            ] {
                let value: TomlValue = switch key.defaultValue {
                    case .bool(let value): .bool(!value)
                    case .int(let value): .int(value + 3)
                    case .float(let value): .float(value + 0.25)
                    case .string: .string("#123456")
                }
                let patched = set(defaultConfig, key.path, value)
                assertEquals(value.matches(TomlPatcher.decodedValue(patched, key.path)), true, additionalMsg: key.label)
                // Only one line is different
                let before = defaultConfig.split(separator: "\n", omittingEmptySubsequences: false)
                let after = patched.split(separator: "\n", omittingEmptySubsequences: false)
                assertEquals(after.filter { !before.contains($0) }.count, patched.contains("[borders]") ? 2 : 1, additionalMsg: key.label)
                assertEquals(before.filter { !after.contains($0) }.count <= 1, true, additionalMsg: key.label)

                let removed = remove(patched, key.path)
                assertEquals(TomlPatcher.decodedValue(removed, key.path) == nil, true, additionalMsg: key.label)
            }
        }
    }
}

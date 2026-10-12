@testable import AppBundle
import Common
import Foundation
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
            // A key that needs quotes
            assertEquals(set("", TomlKeyPath(["a b", "c"], "d.e"), .int(1)), "['a b'.c]\n'd.e' = 1\n")
        }

        /// A sub-table that isn't in the document goes after its parent table, not to the end of the document
        @Test func testAddSubtable() {
            let resize = TomlKeyPath(["borders", "mode-colors"], "resize")
            let green = TomlValue.string("#30D158")
            // Right after the parent, with an empty line on both sides
            assertEquals(set("[menu-bar]\ntheme = 'chips'\n[z]\n", focused, .string("auto")), "[menu-bar]\ntheme = 'chips'\n\n[menu-bar.colors]\nfocused = 'auto'\n\n[z]\n")
            // The empty lines and the comment above the next table belong to that table
            assertEquals(
                set("[borders]\nwidth = 4 # Thick\n\n\n# The main mode\n# It must exist\n[mode.main.binding]\nalt-h = 'focus left'\n", resize, green),
                "[borders]\nwidth = 4 # Thick\n\n[borders.mode-colors]\nresize = '#30D158'\n\n\n# The main mode\n# It must exist\n[mode.main.binding]\nalt-h = 'focus left'\n",
            )
            // A comment at the end of the parent table, separated from the next table, stays in the parent table
            assertEquals(
                set("[borders]\nwidth = 4\n# glow = true\n\n[z]\n", resize, green),
                "[borders]\nwidth = 4\n# glow = true\n\n[borders.mode-colors]\nresize = '#30D158'\n\n[z]\n",
            )
            // The parent is the last table of the document, with and without the last line break
            assertEquals(set("[a]\n[borders]\nwidth = 4\n", resize, green), "[a]\n[borders]\nwidth = 4\n\n[borders.mode-colors]\nresize = '#30D158'\n")
            assertEquals(set("[a]\n[borders]\nwidth = 4", resize, green), "[a]\n[borders]\nwidth = 4\n\n[borders.mode-colors]\nresize = '#30D158'\n")
            assertEquals(set("[borders]", resize, green), "[borders]\n\n[borders.mode-colors]\nresize = '#30D158'\n")
            assertEquals(set("[borders]\r\nwidth = 4\r\n[z]\r\n", resize, green), "[borders]\r\nwidth = 4\r\n\r\n[borders.mode-colors]\r\nresize = '#30D158'\r\n\r\n[z]\r\n")

            // One level deeper than the keys of the parent
            assertEquals(
                set("[borders]\n    width = 4\n\n[z]\n", resize, green),
                "[borders]\n    width = 4\n\n    [borders.mode-colors]\n        resize = '#30D158'\n\n[z]\n",
            )
            assertEquals(
                set("\t[borders]\n\t\twidth = 4\n", resize, green),
                "\t[borders]\n\t\twidth = 4\n\n\t\t[borders.mode-colors]\n\t\t\tresize = '#30D158'\n",
            )
            // After the sub-tables that the parent already has, and indented like the last one of them
            assertEquals(
                set("[menu-bar]\n  theme = 'chips'\n  [menu-bar.colors]\n      focused = 'auto'\n[z]\n", TomlKeyPath(["menu-bar", "extra"], "a"), .int(1)),
                "[menu-bar]\n  theme = 'chips'\n  [menu-bar.colors]\n      focused = 'auto'\n\n  [menu-bar.extra]\n      a = 1\n\n[z]\n",
            )
            // Only a sibling, without the parent
            assertEquals(
                set("[menu-bar.colors]\nfocused = 'auto'\n[z]\n", TomlKeyPath(["menu-bar", "extra"], "a"), .int(1)),
                "[menu-bar.colors]\nfocused = 'auto'\n\n[menu-bar.extra]\na = 1\n\n[z]\n",
            )
            // The parent ends with a value of several lines, whose last lines look like comments and empty lines
            assertEquals(
                set("[borders]\nnote = \"\"\"\n# not a comment\n\n\"\"\"\n[z]\n", resize, green),
                "[borders]\nnote = \"\"\"\n# not a comment\n\n\"\"\"\n\n[borders.mode-colors]\nresize = '#30D158'\n\n[z]\n",
            )
            assertEquals(
                set("[borders]\nlist = [\n  1,\n  # one\n\n]\n# next\n[z]\n", resize, green),
                "[borders]\nlist = [\n  1,\n  # one\n\n]\n\n[borders.mode-colors]\nresize = '#30D158'\n\n# next\n[z]\n",
            )

            // The table is there: the usual rules. A second key, a quoted one, and the keys removed again
            let one = set("[borders]\nwidth = 4\n\n[z]\n", resize, green)
            let two = set(one, TomlKeyPath(["borders", "mode-colors"], "my mode"), .string("#FF453A"))
            assertEquals(two, "[borders]\nwidth = 4\n\n[borders.mode-colors]\nresize = '#30D158'\n'my mode' = '#FF453A'\n\n[z]\n")
            assertEquals(TomlPatcher.locate(two, TomlKeyPath(["borders", "mode-colors"], "my mode")), .line(5))
            assertEquals(set(two, resize, green), two)
            assertEquals(remove(remove(two, resize), TomlKeyPath(["borders", "mode-colors"], "my mode")), "[borders]\nwidth = 4\n\n[borders.mode-colors]\n\n[z]\n")

            // No parent and no sibling: the end of the document, as before
            assertEquals(set("[z]\na = 1\n", resize, green), "[z]\na = 1\n\n[borders.mode-colors]\nresize = '#30D158'\n")
            // An array of tables is nobody's family
            assertEquals(set("[[borders]]\nwidth = 4\n[z]\n", TomlKeyPath(["other", "sub"], "a"), .int(1)), "[[borders]]\nwidth = 4\n[z]\n\n[other.sub]\na = 1\n")
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
            assertEquals(set(text, focused, .string("auto")), "[menu-bar]\r\ntheme = 'chips' # comment\r\n\r\n[menu-bar.colors]\r\nfocused = 'auto'\r\n\r\n[x]\r\na = 1\r\n")
            assertEquals(remove(text, theme), "[menu-bar]\r\n\r\n[x]\r\na = 1\r\n")
        }

        @Test func testMissingLastLineBreak() {
            // A value is replaced: the end of the document stays as it is
            assertEquals(set("[menu-bar]\ntheme = 'chips'", theme, .string("square")), "[menu-bar]\ntheme = 'square'")
            assertEquals(set("[menu-bar]\ntheme = 'chips'\n[x]\na = 1", theme, .string("square")), "[menu-bar]\ntheme = 'square'\n[x]\na = 1")
            // A key is added in the middle: the same
            assertEquals(set("[menu-bar]\ntheme = 'chips'\n[x]\na = 1", TomlKeyPath(["menu-bar"], "enabled"), .bool(false)), "[menu-bar]\ntheme = 'chips'\nenabled = false\n[x]\na = 1")
            assertEquals(set("[menu-bar]\n[x]\na = 1", theme, .string("square")), "[menu-bar]\ntheme = 'square'\n[x]\na = 1")
            assertEquals(set("[x]\na = 1", startAtLogin, .bool(true)), "start-at-login = true\n\n[x]\na = 1")
            // A key is added after the last line: the line gets its line break
            assertEquals(set("[menu-bar]\ntheme = 'chips'", TomlKeyPath(["menu-bar"], "enabled"), .bool(false)), "[menu-bar]\ntheme = 'chips'\nenabled = false\n")
            assertEquals(set("[menu-bar]", theme, .string("square")), "[menu-bar]\ntheme = 'square'\n")
            assertEquals(set("[x]\r\na = 1", theme, .string("square")), "[x]\r\na = 1\r\n\r\n[menu-bar]\r\ntheme = 'square'\r\n")
        }

        /// The config file belongs to the user. Whatever the document looks like, an edit touches one line of it
        /// (plus the header of a new table and the empty line before it) and leaves every other byte alone
        @Test func testNothingElseChanges() {
            let documents: [String] = [
                "",
                "\n\n\n",
                "# only a comment",
                "a = 1 # no line break at the end",
                "[menu-bar]",
                "[menu-bar] # comment\n\n\n[borders]# comment\n",
                "\t[menu-bar]\n\t\ttheme\t=\t'chips'\t# tabs\n\t[borders]\n\t\twidth=4# no spaces\n",
                "[menu-bar.colors]\nfocused = 'auto'\n[menu-bar]\ntheme = \"chips\"\n[borders]\nwidth = 0x04\n",
                "start-at-login = false\r\n[menu-bar]\r\ntheme = 'chips'\r\n\r\n[borders]\r\nwidth = 4",
                // Mixed line endings
                "start-at-login = false\n[menu-bar]\r\ntheme = 'chips'\n[borders]\r\nwidth = 4\n",
                "after-startup-command = [\n  'exec-and-forget echo [menu-bar]',\n  \"\"\"exec-and-forget echo '\ntheme = 1\n[borders]\n'\"\"\",\n]\n[menu-bar]\n  enabled = true\n",
                "[mode.main.binding]\nalt-h = 'focus left' # theme = 'x'\n'theme' = 'mode main'\n[[on-window-detected]]\nif.app-id = 'a'\nrun = 'layout floating'\n[menu-bar]\n[[on-window-detected]]\nrun = ['layout tiling']\n",
                "# ñandú 日本語 🪟\n[menu-bar]\ntheme = 'chips' # tema «fichas» 🪟\n[gaps]\ninner.horizontal = 8\nouter.top = [{ monitor.'built-in' = 4 }, 8]\n",
                "[tiling]\nsplit-ratio = 0.5\n\n\n\n[borders.mode-colors]\nresize = '#30D158'\n\n# trailing comment\n",
            ]
            let edits: [(TomlKeyPath, TomlValue)] = [
                (startAtLogin, .bool(true)), (theme, .string("square")), (focused, .string("#D19A66")),
                (TomlKeyPath(["borders"], "width"), .int(7)), (TomlKeyPath(["tiling"], "new-window-placement"), .string("after-focused")),
            ]
            func lines(_ text: String) -> [String] { TomlPatcher.Document(text).lines.map { $0.content + $0.terminator } }
            for document in documents {
                for (path, value) in edits {
                    guard let patched = try? TomlPatcher.set(document, path, value) else {
                        Issue.record("Can't set \(path) in \(document.debugDescription)")
                        continue
                    }
                    assertEquals(value.matches(TomlPatcher.decodedValue(patched, path)), true, additionalMsg: "\(path) in \(document.debugDescription)")
                    let before = lines(document), after = lines(patched)
                    let difference = after.difference(from: before)
                    // A line break that was missing at the end counts as a change of the last line.
                    // A new sub-table is its header, its key, and an empty line on both sides
                    let removed = difference.removals.count, added = difference.insertions.count
                    assertEquals(removed <= 1 && added <= 4 + removed, true, additionalMsg: "\(path) in \(document.debugDescription) -> \(patched.debugDescription)")
                    // Every other value of the document is the same
                    var expected = (try? TomlPatcher.decode(document)) ?? [:]
                    var actual = (try? TomlPatcher.decode(patched)) ?? [:]
                    Self.removeValue(&expected, path.full)
                    Self.removeValue(&actual, path.full)
                    assertEquals(NSDictionary(dictionary: actual), NSDictionary(dictionary: expected), additionalMsg: "\(path) in \(document.debugDescription)")

                    // Setting it again changes nothing, and removing it leaves no trace of the value
                    assertEquals(try? TomlPatcher.set(patched, path, value), patched)
                    let cleared = try? TomlPatcher.remove(patched, path)
                    assertNotNil(cleared)
                    assertTrue(cleared.map { TomlPatcher.decodedValue($0, path) == nil } == true)
                }
            }
        }

        private static func removeValue(_ root: inout [String: Any], _ path: [String]) {
            guard let first = path.first else { return }
            if path.count == 1 {
                root.removeValue(forKey: first)
            } else if var child = root[first] as? [String: Any] {
                removeValue(&child, Array(path.dropFirst()))
                if child.isEmpty { root.removeValue(forKey: first) } else { root[first] = child }
            }
        }

        @Test func testByteOrderMarkAndOldMacLineEndings() {
            // A byte order mark hides the first line from the patcher: the key is added again, and the check of
            // the result refuses the duplicate. Nothing is written
            let withMark = "\u{FEFF}start-at-login = false\n[menu-bar]\ntheme = 'chips'\n"
            assertNotNil(setError(withMark, startAtLogin, .bool(true)))
            // Lone carriage returns aren't line breaks for the patcher. Either the edit is right, or it is refused
            let oldMac = "[menu-bar]\rtheme = 'chips'\r"
            if let patched = try? TomlPatcher.set(oldMac, theme, .string("square")) {
                assertTrue(TomlValue.string("square").matches(TomlPatcher.decodedValue(patched, theme)))
            }
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
            let defaultConfig = try String(contentsOf: projectRoot.appending(path: "inlay.toml"), encoding: .utf8)
            for key in [
                SettingsKey.startAtLogin, .autoReloadConfig, .newWindowPlacement, .startupLayout, .splitTarget, .minWindowSize,
                .menuBarEnabled, .menuBarTheme, .menuBarShowAppIcons,
                .menuBarDimEmpty, .menuBarShowMode, .menuBarAccent, .menuBarFocused, .menuBarOccupied, .menuBarEmpty,
                .bordersEnabled, .bordersWidth, .bordersCornerRadius, .bordersActiveColor, .bordersInactiveColor, .bordersFloatingColor,
                .bordersGlow, .bordersGlowRadius,
            ] {
                let value: TomlValue = switch key.defaultValue {
                    // The opposite of what the file has, which isn't always the default
                    case .bool(let value): .bool(!((TomlPatcher.decodedValue(defaultConfig, key.path) as? Bool) ?? value))
                    case .int(let value): .int(value + 3)
                    case .float(let value): .float(value + 0.25)
                    case .string: .string("#123456")
                }
                let patched = set(defaultConfig, key.path, value)
                assertEquals(value.matches(TomlPatcher.decodedValue(patched, key.path)), true, additionalMsg: key.label)
                // Only one line is different
                let before = defaultConfig.split(separator: "\n", omittingEmptySubsequences: false)
                let after = patched.split(separator: "\n", omittingEmptySubsequences: false)
                assertEquals(after.filter { !before.contains($0) }.count, 1, additionalMsg: key.label)
                assertEquals(before.filter { !after.contains($0) }.count <= 1, true, additionalMsg: key.label)

                let removed = remove(patched, key.path)
                assertEquals(TomlPatcher.decodedValue(removed, key.path) == nil, true, additionalMsg: key.label)
            }
        }
    }
}

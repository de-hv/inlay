@testable import AppBundle
import Common
import Testing

extension InlayTests {
    @Suite @MainActor struct ConfigTest {
        @Test func testParseI3Config() {
            let result = parseConfig(LuaConfigLoader.load(file: projectRoot.appending(component: "docs/config-examples/i3-like-config-example.lua")))
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
            assertEquals(result.config.execConfig, defaultConfig.execConfig)
            assertEquals(result.config.enableNormalizationFlattenContainers, false)
            assertEquals(result.config.enableNormalizationOppositeOrientationForNestedContainers, false)
        }

        @Test func testEmptyConfig() {
            let result = parseConfig(lua: "inlay.config({})")
            assertEquals(result.errors, [])
            assertTrue(result.allowReloadConfig)
            assertEquals(result.warnings, [])
        }

        /// inlay.lua, the config of a new install, over the built-in config
        @Test func testParseDefaultConfig() {
            let result = parseConfigOverBuiltIn(LuaConfigLoader.load(file: projectRoot.appending(component: "inlay.lua")))
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
        }

        /// The keys that came from AeroSpace and that Inlay doesn't have anymore: unknown keys
        @Test func testKeysOfAeroSpaceAreUnknown() {
            for key in ["configVersion = 2", "afterLoginCommand = {}", "accordionPadding = 30", "nonEmptyWorkspacesRootContainersLayoutOnStartup = 'smart'", "indentForNestedContainersWithTheSameOrientation = 30"] {
                let name = String(key.prefix { $0 != " " })
                assertEquals(parseConfig(lua: "inlay.config({ \(key) })").strErrors, ["[ERROR] \(name): Unknown top-level key"])
            }
            assertEquals(
                parseConfig(lua: "inlay.config({ on_window_detected = { { match = { duringAerospaceStartup = true }, run = 'layout floating' } } })").strErrors,
                ["[ERROR] on_window_detected[0].match.duringAerospaceStartup: Unknown key"],
            )
        }

        @Test func testExecOnWorkspaceChangeDifferentTypesError() {
            let errors = parseConfig(lua: """
                inlay.config({ exec_on_workspace_change = { '', 1 } })
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] exec_on_workspace_change[1]: Expected type is \'String\'. But actual type is \'Int\'"])
        }

        @Test func testDuplicatedPersistentWorkspaces() {
            let errors = parseConfig(lua: """
                inlay.config({ persistent_workspaces = { 'a', 'a' } })
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] persistent_workspaces: Contains duplicated workspace names"])
        }

        /// Always available: there is no configVersion anymore
        @Test func testPersistentWorkspaces() {
            let result = parseConfig(lua: "inlay.config({ persistent_workspaces = { 'a' } })")
            assertEquals(result.strErrors, [])
            assertEquals(Array(result.config.persistentWorkspaces), ["a"])
        }

        @Test func testWrongTypeForCommand() {
            let errors = parseConfig(lua: """
                inlay.config({
                  mode = {
                    main = {
                      binding = { ['alt-a'] = { 1, 'focus right' } },
                    },
                  },
                })
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] mode.main.binding.alt-a[0]: Expected type is \'String\'. But actual type is \'Int\'"])
        }

        @Test func testDropBindings() {
            let result = parseConfig(lua: """
                inlay.config({
                  mode = { main = {} },
                })
                """,
            )
            assertTrue(result.allowReloadConfig)
            assertEquals(result.errors, [])
            assertTrue(result.config.modes[mainModeId]?.bindings.isEmpty == true)
        }

        @Test func testParseMode() {
            let result = parseConfig(lua: """
                inlay.config({
                  mode = {
                    main = {
                      binding = { ['alt-h'] = 'focus left' },
                    },
                  },
                })
                """,
            )
            assertEquals(result.errors, [])
            let binding = HotkeyBinding(.option, .h, .cmd(FocusCommand.new(direction: .left)))
            assertEquals(
                result.config.modes[mainModeId],
                Mode(bindings: [binding.descriptionWithKeyCode: binding]),
            )
        }

        @Test func testModesMustContainDefaultModeError() {
            let result = parseConfig(lua: """
                inlay.config({
                  mode = {
                    foo = {
                      binding = { ['alt-h'] = 'focus left' },
                    },
                  },
                })
                """,
            )
            assertEquals(
                result.strErrors,
                ["[ERROR] mode: Please specify \'main\' mode"],
            )
            assertEquals(result.config.modes[mainModeId], nil)
        }

        @Test func testHotkeyParseError() {
            let result = parseConfig(lua: """
                inlay.config({
                  mode = {
                    main = {
                      binding = {
                        ['alt-hh'] = 'focus left',
                        ['aalt-j'] = 'focus down',
                        ['alt-k'] = 'focus up',
                      },
                    },
                  },
                })
                """,
            )
            assertEquals(
                result.strErrors,
                [
                    "[ERROR] mode.main.binding.aalt-j: Can\'t parse modifiers in \'aalt-j\' binding",
                    "[ERROR] mode.main.binding.alt-hh: Can\'t parse the key in \'alt-hh\' binding",
                ],
            )
            let binding = HotkeyBinding(.option, .k, .cmd(FocusCommand.new(direction: .up)))
            assertEquals(
                result.config.modes[mainModeId],
                Mode(bindings: [binding.descriptionWithKeyCode: binding]),
            )
        }

        /// The persistent workspaces come from 'persistent_workspaces', or from the ids of 'workspaces'. The key
        /// bindings don't make any
        @Test func testPermanentWorkspaceNames() {
            let fromBindings = parseConfig(lua: """
                inlay.config({
                  mode = {
                    main = {
                      binding = {
                        ['alt-1'] = 'workspace 1',
                        ['alt-2'] = 'workspace 2',
                      },
                    },
                  },
                })
                """,
            )
            assertEquals(fromBindings.errors, [])
            assertEquals(fromBindings.config.persistentWorkspaces, [])

            let fromWorkspaces = parseConfig(lua: "inlay.config({ workspaces = { { id = '1' }, { id = '2' }, { id = '3' }, { id = '4' } } })")
            assertEquals(fromWorkspaces.errors, [])
            assertEquals(Array(fromWorkspaces.config.persistentWorkspaces), ["1", "2", "3", "4"])
        }

        @Test func testUnknownTopLevelKeyParseError() {
            let result = parseConfig(lua: """
                inlay.config({ unknownKey = true, enable_normalization_flatten_containers = false })
                """,
            )
            assertEquals(
                result.strErrors,
                ["[ERROR] unknownKey: Unknown top-level key"],
            )
            assertEquals(result.config.enableNormalizationFlattenContainers, false)
        }

        @Test func testUnknownKeyParseError() {
            let result = parseConfig(lua: """
                inlay.config({
                  enable_normalization_flatten_containers = false,
                  gaps = { unknownKey = true },
                })
                """,
            )
            assertEquals(
                result.strErrors,
                ["[ERROR] gaps.unknownKey: Unknown key"],
            )
            assertEquals(result.config.enableNormalizationFlattenContainers, false)
        }

        @Test func testTypeMismatch() {
            let errors = parseConfig(lua: """
                inlay.config({ enable_normalization_flatten_containers = 'true' })
                """,
            ).strErrors
            assertEquals(
                errors,
                ["[ERROR] enable_normalization_flatten_containers: Expected type is \'Bool\'. But actual type is \'String\'"],
            )
        }

        @Test func testConfigParseError() {
            assertFalse(parseConfig(lua: "inlay.config({").allowReloadConfig)
            assertEquals(
                parseConfig(lua: "inlay.config({").strErrors,
                ["[ERROR] inlay.lua:1: unexpected symbol near <eof>"],
            )

            assertEquals(
                parseConfig(lua: "\nreturn 1").strErrors,
                ["[ERROR] inlay.lua returns a number: the config is the calls of inlay (inlay.config, inlay.bind…), and it returns nothing"],
            )

            assertEquals(
                parseConfig(lua: "inlay.config({ foo: 1 })").strErrors,
                ["[ERROR] inlay.lua:1: <name> expected near '1'"],
            )

            assertEquals(
                parseConfig(lua: "inlay.config({ foo = function() end })").strErrors,
                ["[ERROR] foo: Unsupported Lua type: function"],
            )

            assertEquals(
                parseConfig(lua: "inlay.config({ foo = { bar = print } })").strErrors,
                ["[ERROR] foo.bar: Unsupported Lua type: function", "[ERROR] foo: Unknown top-level key"],
            )
        }

        @Test func testMoveWorkspaceToMonitorCommandParsing() {
            assertTrue(parseCommand("move-workspace-to-monitor --wrap-around next").cmdOrNil?.flatten().singleOrNil() is MoveWorkspaceToMonitorCommand)
            assertTrue(parseCommand("move-workspace-to-display --wrap-around next").cmdOrNil?.flatten().singleOrNil() is MoveWorkspaceToMonitorCommand)
        }

        @Test func testParseTiles() {
            let command = parseCommand("layout tiles h_tiles v_tiles list h_list v_list").cmdOrNil?.flatten().singleOrNil()
            assertTrue(command is LayoutCommand)
            assertEquals((command as! LayoutCommand).args.toggleBetween.val, [.tiles, .h_tiles, .v_tiles, .tiles, .h_tiles, .v_tiles])

            guard case .help = parseCommand("layout tiles -h") else {
                Issue.record()
                return
            }
        }

        @Test func testSplitCommandAndFlattenContainersNormalization() {
            let errors = parseConfig(lua: """
                inlay.config({
                  enable_normalization_flatten_containers = true,
                  mode = {
                    main = { binding = {} },
                    foo = {
                      binding = { ['alt-s'] = 'split horizontal' },
                    },
                  },
                })
                """,
            ).strErrors
            let expected = """
                [ERROR] The config contains:
                1. usage of 'split' command
                2. enable_normalization_flatten_containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable_normalization_flatten_containers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """
            assertEquals(errors, [expected])
        }

        @Test func testParseWorkspaceToMonitorAssignment() {
            let result = parseConfig(lua: """
                inlay.config({
                  workspace_to_monitor_force_assignment = {
                    workspace_name_1 = 1,
                    workspace_name_2 = 'main',
                    workspace_name_3 = 'secondary',
                    workspace_name_4 = 'built-in',
                    workspace_name_5 = '^built-in retina display$',
                    workspace_name_6 = { 'secondary', 1 },
                    ['7'] = 'foo',
                    w7 = { '', 'main' },
                    w8 = 0,
                    workspace_name_x = '2',
                  },
                })
                """,
            )
            assertEquals(
                result.config.workspaceToMonitorForceAssignment,
                [
                    "workspace_name_1": [.sequenceNumber(1)],
                    "workspace_name_2": [.main],
                    "workspace_name_3": [.secondary],
                    "workspace_name_4": [.pattern("built-in")!],
                    "workspace_name_5": [.pattern("^built-in retina display$")!],
                    "workspace_name_6": [.secondary, .sequenceNumber(1)],
                    "workspace_name_x": [.sequenceNumber(2)],
                    "7": [.pattern("foo")!],
                    "w7": [.main],
                    "w8": [],
                ],
            )
            assertEquals([
                "[ERROR] workspace_to_monitor_force_assignment.w7[0]: Empty string is an illegal monitor description",
                "[ERROR] workspace_to_monitor_force_assignment.w8: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
            ], result.strErrors)
            assertEquals([:], Config().workspaceToMonitorForceAssignment)
        }

        @Test func testParseOnWindowDetected() {
            let result = parseConfig(lua: """
                inlay.config({
                  on_window_detected = {
                    { -- 0
                      match = 'true',
                      check_further_callbacks = true,
                      run = { 'layout floating', 'move-node-to-workspace W' },
                    },
                    { -- 1
                      match = { app_id = 'com.apple.systempreferences' },
                      run = {},
                    },
                    {}, -- 2
                    { -- 3
                      match = 'true', run = { 'move-node-to-workspace S', 'layout tiling' },
                    },
                    { -- 4
                      match = 'true', run = { 'move-node-to-workspace S', 'move-node-to-workspace W' },
                    },
                    { -- 5
                      match = 'true', run = { 'move-node-to-workspace S', 'layout h_tiles' },
                    },
                    { -- 6
                      match = 'test %{app-bundle-id} = org.alacritty',
                      run = { 'move-node-to-workspace T' },
                    },
                    { match = '', run = '' }, -- 7
                  },
                })
                """)
            let matcher6Args = TestCmdArgs(rawArgs: [])
                .copy(\.lhs, .initialized(.app(.appBundleId)))
                .copy(\.infixOperator, .initialized(.equals))
                .copy(\.rhs, .initialized("org.alacritty"))
            assertEquals(result.config.onWindowDetected, [
                WindowDetectedCallback( // 0
                    matcher: .command(.cmd(TrueCommand.instance)),
                    checkFurtherCallbacks: true,
                    rawRun: .seq([
                        .cmd(LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating]))),
                        .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W"))),
                    ]),
                ),
                WindowDetectedCallback( // 1
                    matcher: .legacy(LegacyWindowDetectedCallbackMatcher(
                        appId: "com.apple.systempreferences",
                    )),
                    rawRun: .empty,
                ),
                WindowDetectedCallback( // 3
                    matcher: .command(.cmd(TrueCommand.instance)),
                    rawRun: .seq([
                        .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S"))),
                        .cmd(LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiling]))),
                    ]),
                ),
                WindowDetectedCallback( // 4
                    matcher: .command(.cmd(TrueCommand.instance)),
                    rawRun: .seq([
                        .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S"))),
                        .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W"))),
                    ]),
                ),
                WindowDetectedCallback( // 5
                    matcher: .command(.cmd(TrueCommand.instance)),
                    rawRun: .seq([
                        .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S"))),
                        .cmd(LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.h_tiles]))),
                    ]),
                ),
                WindowDetectedCallback( // 6
                    matcher: .command(.cmd(TestCommand(args: matcher6Args))),
                    rawRun: .cmd(MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "T"))),
                ),
            ])

            assertEquals(result.strErrors, [
                "[ERROR] on_window_detected[2]: Omitting \'match\' is error prone. You can use `match = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'check_further_callbacks = true\'",
                "[ERROR] on_window_detected[2]: \'run\' is mandatory key",
                "[ERROR] on_window_detected[7]: Omitting \'match\' is error prone. You can use `match = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'check_further_callbacks = true\'",
            ])
        }

        @Test func testParseOnWindowDetected2() {
            let result = parseConfig(lua: """
                inlay.config({
                  on_window_detected = {
                    { check_further_callbacks = true, run = '' },
                  },
                })
                """)
            assertEquals(result.config.onWindowDetected, [
                WindowDetectedCallback(
                    matcher: .command(.empty),
                    checkFurtherCallbacks: true,
                    rawRun: .empty,
                ),
            ])

            assertEquals(result.errors, [])
        }

        @Test func testParseInlineTables() {
            let errors = parseConfig(lua: """
                inlay.config({
                  on_window_detected = {
                    {
                      check_further_callbacks = true,
                      run = { 'layout floating', 'move-node-to-workspace W' },
                    },
                    {
                      match = { app_id = 'com.apple.systempreferences' },
                      run = {},
                    },
                  },
                })
                """).errors
            assertEquals(errors, [])
        }

        /// A syntax error stops the reload, with its line
        @Test func testLuaSyntaxError() {
            let result = parseConfig(lua: """
                inlay.config({
                  on_window_detected = {
                    { match = { app_id = 'com.apple.findmy' }, run = 'layout floating' }
                    { match = { app_id = 'com.openai.chat' }, run = 'layout floating' },
                  },
                })
                """)
            assertFalse(result.allowReloadConfig)
            assertEquals(result.strErrors, ["[ERROR] inlay.lua:4: '}' expected (to close '{' at line 2) near '{'"])
        }

        @Test func testParseOnWindowDetectedRegex() {
            let result = parseConfig(lua: """
                inlay.config({
                  on_window_detected = {
                    {
                      match = { app_name_regex_substring = '^system settings$' },
                      run = {},
                    },
                  },
                })
                """,
            )
            let expected = WindowDetectedCallbackMatcher.legacy(LegacyWindowDetectedCallbackMatcher(appNameRegexSubstring: .new("^system settings$").getOrDie()))
            assertEquals(result.config.onWindowDetected.singleOrNil()!.matcher, expected)
            assertEquals(result.errors, [])
        }

        @Test func testRegex() {
            var devNull: [String] = []
            assertTrue("System Settings".contains(caseInsensitiveRegex: CaseInsensitiveRegex.new("settings").getOrNil(appendErrorTo: &devNull)!))
            assertTrue(!"System Settings".contains(caseInsensitiveRegex: CaseInsensitiveRegex.new("^settings^").getOrNil(appendErrorTo: &devNull)!))
        }

        @Test func testParseGaps() {
            let result1 = parseConfig(lua: """
                inlay.config({
                  gaps = {
                    inner = {
                      horizontal = 10,
                      vertical = {
                        {
                          monitor = { main = 1 },
                        },
                        {
                          monitor = { secondary = 2 },
                        },
                        5,
                      },
                    },
                    outer = {
                      left = 12,
                      bottom = 13,
                      top = {
                        {
                          monitor = { ['built-in'] = 3 },
                        },
                        {
                          monitor = { secondary = 4 },
                        },
                        6,
                      },
                      right = {
                        {
                          monitor = { ['2'] = 7 },
                        },
                        8,
                      },
                    },
                  },
                })
                """,
            )
            assertEquals(result1.errors, [])
            assertEquals(
                result1.config.gaps,
                Gaps(
                    inner: .init(
                        vertical: .perMonitor(
                            [PerMonitorValue(description: .main, value: 1), PerMonitorValue(description: .secondary, value: 2)],
                            default: 5,
                        ),
                        horizontal: .constant(10),
                    ),
                    outer: .init(
                        left: .constant(12),
                        bottom: .constant(13),
                        top: .perMonitor(
                            [
                                PerMonitorValue(description: .pattern("built-in")!, value: 3),
                                PerMonitorValue(description: .secondary, value: 4),
                            ],
                            default: 6,
                        ),
                        right: .perMonitor([PerMonitorValue(description: .sequenceNumber(2), value: 7)], default: 8),
                    ),
                ),
            )

            let result2 = parseConfig(lua: """
                inlay.config({
                  gaps = {
                    inner = {
                      horizontal = { true },
                      vertical = {
                        {
                          foo = { main = 1 },
                        },
                        {
                          monitor = { foo = 2, bar = 3 },
                        },
                        1,
                      },
                    },
                  },
                })
                """,
            )
            assertEquals(result2.strErrors, [
                "[ERROR] gaps.inner.horizontal: The last item in the array must be of type Int",
                "[ERROR] gaps.inner.vertical[0]: The table is expected to have a single key \'monitor\'",
                "[ERROR] gaps.inner.vertical[1].monitor: The table is expected to have a single key",
            ])
        }

        @Test func testOnFocusChangedAsSingleStringAndAsList() {
            let result = parseConfig(lua: """
                inlay.config({
                  on_focus_changed = 'focus left',
                  on_mode_changed = { 'focus right', 'focus up' },
                  on_focused_monitor_changed = 'focus down',
                })
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.onFocusChanged.flatten().count, 1)
            assertTrue(result.config.onFocusChanged.flatten()[0] is FocusCommand)
            assertEquals(result.config.onModeChanged.flatten().count, 2)
            assertEquals(result.config.onFocusedMonitorChanged.flatten().count, 1)
        }

        @Test func testOnFocusChangedTypeError() {
            let result = parseConfig(lua: """
                inlay.config({ on_focus_changed = 1 })
                """,
            )
            assertEquals(
                result.strErrors,
                ["[ERROR] on_focus_changed: Expected types are \'string\' or \'array\'. But actual type is \'int\'"],
            )
        }

        @Test func testParseDefaultRootContainerLayout() {
            let result = parseConfig(lua: """
                inlay.config({ default_root_container_layout = 'tiles' })
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.defaultRootContainerLayout, .tiles)

            let listResult = parseConfig(lua: """
                inlay.config({ default_root_container_layout = 'list' })
                """,
            )
            assertEquals(listResult.errors, [])
            assertEquals(listResult.config.defaultRootContainerLayout, .tiles)

            let bad = parseConfig(lua: """
                inlay.config({ default_root_container_layout = 'bogus' })
                """,
            )
            assertEquals(
                bad.strErrors,
                ["[ERROR] default_root_container_layout: Can\'t parse layout \'bogus\'"],
            )
        }

        @Test func testParseDefaultRootContainerOrientation() {
            let result = parseConfig(lua: """
                inlay.config({ default_root_container_orientation = 'vertical' })
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.defaultRootContainerOrientation, .vertical)

            let bad = parseConfig(lua: """
                inlay.config({ default_root_container_orientation = 'diagonal' })
                """,
            )
            assertEquals(
                bad.strErrors,
                ["[ERROR] default_root_container_orientation: Can\'t parse default container orientation \'diagonal\'"],
            )
        }

        @Test func testTopLevelTypeIsNotTable() {
            // A config that doesn't return a table of keys isn't applied
            assertFalse(parseConfig(lua: "inlay.config({ 'a' })").allowReloadConfig)
            assertFalse(parseConfig(lua: "return 'a'").allowReloadConfig)
        }

        @Test func testParseKeyMapping() {
            let result = parseConfig(lua: """
                inlay.config({
                  key_mapping = {
                    key_notation_to_key_code = { q = 'q', unicorn = 'u' },
                  },
                  mode = {
                    main = {
                      binding = { ['alt-unicorn'] = 'workspace wonderland' },
                    },
                  },
                })
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.keyMapping, KeyMapping(preset: .qwerty, rawKeyNotationToKeyCode: [
                "q": .q,
                "unicorn": .u,
            ]))
            let binding = HotkeyBinding(.option, .u, .cmd(WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("wonderland").getOrDie())))))
            assertEquals(result.config.modes[mainModeId]?.bindings, [binding.descriptionWithKeyCode: binding])

            let errors1 = parseConfig(lua: """
                inlay.config({
                  key_mapping = {
                    key_notation_to_key_code = { q = 'qw', [' f'] = 'f' },
                  },
                })
                """,
            ).strErrors
            assertEquals(errors1, [
                "[ERROR] key_mapping.key_notation_to_key_code: ' f' is invalid key notation",
                "[ERROR] key_mapping.key_notation_to_key_code.q: 'qw' is invalid key code",
            ])

            let dvorakResult = parseConfig(lua: """
                inlay.config({
                  key_mapping = { preset = 'dvorak' },
                })
                """,
            )
            assertEquals(dvorakResult.errors, [])
            assertEquals(dvorakResult.config.keyMapping, KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
            assertEquals(dvorakResult.config.keyMapping.resolve()["quote"], .q)
            let colemakResult = parseConfig(lua: """
                inlay.config({
                  key_mapping = { preset = 'colemak' },
                })
                """,
            )
            assertEquals(colemakResult.errors, [])
            assertEquals(colemakResult.config.keyMapping, KeyMapping(preset: .colemak, rawKeyNotationToKeyCode: [:]))
            assertEquals(colemakResult.config.keyMapping.resolve()["f"], .e)
        }
    }
}

extension ParseConfigResult {
    var strErrors: [String] {
        errors.map { $0.description(.error) }
    }

    var strWarnings: [String] {
        warnings.map { $0.description(.warning) }
    }
}

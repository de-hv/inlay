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
            let result = parseConfig(lua: "return {}")
            assertEquals(result.errors, [])
            assertTrue(result.allowReloadConfig)
            assertEquals(result.warnings.count, 1)
            assertTrue(result.strWarnings.first?.starts(with: "[WARNING] The current 'configVersion = 1' is outdated.") == true)
        }

        @Test func testParseDefaultConfig() {
            let result = parseConfig(LuaConfigLoader.load(file: projectRoot.appending(component: "inlay.lua")))
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
        }

        @Test func testConfigVersionOutOfBounds() {
            let result = parseConfig(lua: """
                return { configVersion = 0 }
                """,
            )
            assertTrue(result.allowReloadConfig)
            assertEquals(result.strErrors, ["[ERROR] configVersion: configVersion must be in [1, 2] range"])
        }

        @Test func testConfigVersionOutdatedWarning() {
            let result = parseConfig(lua: """
                return { configVersion = 1 }
                """,
            )
            assertTrue(result.allowReloadConfig)
            assertEquals(result.errors, [])
            assertEquals(result.strWarnings, [
                "[WARNING] The current 'configVersion = 1' is outdated. " +
                    "Please consider migrating to 'configVersion = \(ConfigVersion.max)'. " +
                    "See https://nikitabobko.github.io/AeroSpace/guide#config-version for the migration guide.",
            ])
        }

        @Test func testLatestConfigVersionNoWarning() {
            let result = parseConfig(lua: """
                return { configVersion = \(ConfigVersion.max) }
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.warnings, [])
        }

        @Test func testExecOnWorkspaceChangeDifferentTypesError() {
            let errors = parseConfig(lua: """
                return { execOnWorkspaceChange = { '', 1 } }
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] execOnWorkspaceChange[1]: Expected type is \'String\'. But actual type is \'Int\'"])
        }

        @Test func testDuplicatedPersistentWorkspaces() {
            let errors = parseConfig(lua: """
                return { configVersion = 2, persistentWorkspaces = { 'a', 'a' } }
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] persistentWorkspaces: Contains duplicated workspace names"])
        }

        @Test func testPersistentWorkspacesAreAvailableOnlySinceVersion2() {
            let errors = parseConfig(lua: """
                return { persistentWorkspaces = { 'a' } }
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] persistentWorkspaces: This config option is only available since \'configVersion = 2\'"])
        }

        @Test func testWrongTypeForCommand() {
            let errors = parseConfig(lua: """
                return {
                  mode = {
                    main = {
                      binding = { ['alt-a'] = { 1, 'focus right' } },
                    },
                  },
                }
                """,
            ).strErrors
            assertEquals(errors, ["[ERROR] mode.main.binding.alt-a[0]: Expected type is \'String\'. But actual type is \'Int\'"])
        }

        @Test func testDropBindings() {
            let result = parseConfig(lua: """
                return {
                  mode = { main = {} },
                }
                """,
            )
            assertTrue(result.allowReloadConfig)
            assertEquals(result.errors, [])
            assertTrue(result.config.modes[mainModeId]?.bindings.isEmpty == true)
        }

        @Test func testParseMode() {
            let result = parseConfig(lua: """
                return {
                  mode = {
                    main = {
                      binding = { ['alt-h'] = 'focus left' },
                    },
                  },
                }
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
                return {
                  mode = {
                    foo = {
                      binding = { ['alt-h'] = 'focus left' },
                    },
                  },
                }
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
                return {
                  mode = {
                    main = {
                      binding = {
                        ['alt-hh'] = 'focus left',
                        ['aalt-j'] = 'focus down',
                        ['alt-k'] = 'focus up',
                      },
                    },
                  },
                }
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

        @Test func testPermanentWorkspaceNames() {
            let result = parseConfig(lua: """
                return {
                  mode = {
                    main = {
                      binding = {
                        ['alt-1'] = 'workspace 1',
                        ['alt-2'] = 'workspace 2',
                        ['alt-3'] = { 'workspace 3' },
                        ['alt-4'] = { 'workspace 4', 'focus left' },
                      },
                    },
                  },
                }
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.persistentWorkspaces.sorted(), ["1", "2", "3", "4"])
        }

        @Test func testUnknownTopLevelKeyParseError() {
            let result = parseConfig(lua: """
                return { unknownKey = true, enableNormalizationFlattenContainers = false }
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
                return {
                  enableNormalizationFlattenContainers = false,
                  gaps = { unknownKey = true },
                }
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
                return { enableNormalizationFlattenContainers = 'true' }
                """,
            ).strErrors
            assertEquals(
                errors,
                ["[ERROR] enableNormalizationFlattenContainers: Expected type is \'Bool\'. But actual type is \'String\'"],
            )
        }

        @Test func testConfigParseError() {
            assertFalse(parseConfig(lua: "return {").allowReloadConfig)
            assertEquals(
                parseConfig(lua: "return {").strErrors,
                ["[ERROR] inlay.lua:1: unexpected symbol near <eof>"],
            )

            assertEquals(
                parseConfig(lua: "\nreturn 1").strErrors,
                ["[ERROR] inlay.lua must return the table of the config. It returns: number"],
            )

            assertEquals(
                parseConfig(lua: "return { foo: 1 }").strErrors,
                ["[ERROR] inlay.lua:1: <name> expected near '1'"],
            )

            assertEquals(
                parseConfig(lua: "return { foo = function() end }").strErrors,
                ["[ERROR] foo: Unsupported Lua type: function"],
            )

            assertEquals(
                parseConfig(lua: "return { foo = { bar = print } }").strErrors,
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
                return {
                  enableNormalizationFlattenContainers = true,
                  mode = {
                    main = { binding = {} },
                    foo = {
                      binding = { ['alt-s'] = 'split horizontal' },
                    },
                  },
                }
                """,
            ).strErrors
            let expected = """
                [ERROR] The config contains:
                1. usage of 'split' command
                2. enableNormalizationFlattenContainers = true
                These two settings don't play nicely together. 'split' command has no effect when enableNormalizationFlattenContainers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """
            assertEquals(errors, [expected])
        }

        @Test func testParseWorkspaceToMonitorAssignment() {
            let result = parseConfig(lua: """
                return {
                  workspaceToMonitorForceAssignment = {
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
                }
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
                "[ERROR] workspaceToMonitorForceAssignment.w7[0]: Empty string is an illegal monitor description",
                "[ERROR] workspaceToMonitorForceAssignment.w8: Monitor sequence numbers uses 1-based indexing. Values less than 1 are illegal",
            ], result.strErrors)
            assertEquals([:], Config().workspaceToMonitorForceAssignment)
        }

        @Test func testParseOnWindowDetected() {
            let result = parseConfig(lua: """
                return {
                  onWindowDetected = {
                    { -- 0
                      match = 'true',
                      checkFurtherCallbacks = true,
                      run = { 'layout floating', 'move-node-to-workspace W' },
                    },
                    { -- 1
                      match = { appId = 'com.apple.systempreferences' },
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
                }
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
                "[ERROR] onWindowDetected[2]: Omitting \'match\' is error prone. You can use `match = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'checkFurtherCallbacks = true\'",
                "[ERROR] onWindowDetected[2]: \'run\' is mandatory key",
                "[ERROR] onWindowDetected[7]: Omitting \'match\' is error prone. You can use `match = \'true\'` to preserve the previous behavior.\nBut heads up! You may have missed \'checkFurtherCallbacks = true\'",
            ])
        }

        @Test func testParseOnWindowDetected2() {
            let result = parseConfig(lua: """
                return {
                  onWindowDetected = {
                    { checkFurtherCallbacks = true, run = '' },
                  },
                }
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
                return {
                  onWindowDetected = {
                    {
                      checkFurtherCallbacks = true,
                      run = { 'layout floating', 'move-node-to-workspace W' },
                    },
                    {
                      match = { appId = 'com.apple.systempreferences' },
                      run = {},
                    },
                  },
                }
                """).errors
            assertEquals(errors, [])
        }

        /// A syntax error stops the reload, with its line
        @Test func testLuaSyntaxError() {
            let result = parseConfig(lua: """
                return {
                  onWindowDetected = {
                    { match = { appId = 'com.apple.findmy' }, run = 'layout floating' }
                    { match = { appId = 'com.openai.chat' }, run = 'layout floating' },
                  },
                }
                """)
            assertFalse(result.allowReloadConfig)
            assertEquals(result.strErrors, ["[ERROR] inlay.lua:4: '}' expected (to close '{' at line 2) near '{'"])
        }

        @Test func testParseOnWindowDetectedRegex() {
            let result = parseConfig(lua: """
                return {
                  onWindowDetected = {
                    {
                      match = { appNameRegexSubstring = '^system settings$' },
                      run = {},
                    },
                  },
                }
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
                return {
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
                }
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
                return {
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
                }
                """,
            )
            assertEquals(result2.strErrors, [
                "[ERROR] gaps.inner.horizontal: The last item in the array must be of type Int",
                "[ERROR] gaps.inner.vertical[0]: The table is expected to have a single key \'monitor\'",
                "[ERROR] gaps.inner.vertical[1].monitor: The table is expected to have a single key",
            ])
        }

        @Test func testAfterLoginCommandDeprecation() {
            let result = parseConfig(lua: """
                return { afterLoginCommand = { 'exec-and-forget echo hi' } }
                """,
            )
            assertEquals(
                result.strErrors,
                ["[ERROR] afterLoginCommand: afterLoginCommand is deprecated since AeroSpace 0.19.0. https://github.com/nikitabobko/AeroSpace/issues/1482"],
            )

            // Empty array is still accepted
            let okResult = parseConfig(lua: """
                return { afterLoginCommand = {} }
                """,
            )
            assertEquals(okResult.errors, [])
        }

        @Test func testOnFocusChangedAsSingleStringAndAsList() {
            let result = parseConfig(lua: """
                return {
                  onFocusChanged = 'focus left',
                  onModeChanged = { 'focus right', 'focus up' },
                  onFocusedMonitorChanged = 'focus down',
                }
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
                return { onFocusChanged = 1 }
                """,
            )
            assertEquals(
                result.strErrors,
                ["[ERROR] onFocusChanged: Expected types are \'string\' or \'array\'. But actual type is \'int\'"],
            )
        }

        @Test func testParseDefaultRootContainerLayout() {
            let result = parseConfig(lua: """
                return { defaultRootContainerLayout = 'tiles' }
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.defaultRootContainerLayout, .tiles)

            let listResult = parseConfig(lua: """
                return { defaultRootContainerLayout = 'list' }
                """,
            )
            assertEquals(listResult.errors, [])
            assertEquals(listResult.config.defaultRootContainerLayout, .tiles)

            let bad = parseConfig(lua: """
                return { defaultRootContainerLayout = 'bogus' }
                """,
            )
            assertEquals(
                bad.strErrors,
                ["[ERROR] defaultRootContainerLayout: Can\'t parse layout \'bogus\'"],
            )
        }

        @Test func testParseDefaultRootContainerOrientation() {
            let result = parseConfig(lua: """
                return { defaultRootContainerOrientation = 'vertical' }
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.config.defaultRootContainerOrientation, .vertical)

            let bad = parseConfig(lua: """
                return { defaultRootContainerOrientation = 'diagonal' }
                """,
            )
            assertEquals(
                bad.strErrors,
                ["[ERROR] defaultRootContainerOrientation: Can\'t parse default container orientation \'diagonal\'"],
            )
        }

        @Test func testDeprecatedIndentForNestedContainers() {
            let errors = parseConfig(lua: """
                return { indentForNestedContainersWithTheSameOrientation = 30 }
                """,
            ).strErrors
            assertEquals(
                errors,
                ["[ERROR] indentForNestedContainersWithTheSameOrientation: Deprecated. Please drop it from the config. See https://github.com/nikitabobko/AeroSpace/issues/96"],
            )
        }

        @Test func testDeprecatedNonEmptyWorkspacesRootContainersLayoutOnStartup() {
            // The 'smart' value used to be accepted and is silently dropped now
            let smart = parseConfig(lua: """
                return { nonEmptyWorkspacesRootContainersLayoutOnStartup = 'smart' }
                """,
            )
            assertEquals(smart.errors, [])

            let bad = parseConfig(lua: """
                return { nonEmptyWorkspacesRootContainersLayoutOnStartup = 'tiles' }
                """,
            ).strErrors
            assertEquals(
                bad,
                ["[ERROR] nonEmptyWorkspacesRootContainersLayoutOnStartup: \'nonEmptyWorkspacesRootContainersLayoutOnStartup\' is deprecated. Please drop it from your config"],
            )
        }

        @Test func testOutdatedConfigVersionWarning() {
            let result = parseConfig(lua: """
                return { configVersion = 1 }
                """,
            )
            assertEquals(result.errors, [])
            assertEquals(result.warnings.count, 1)
            assertTrue(result.warnings[0].message.contains("'configVersion = 1' is outdated"))

            // configVersion = 2 (the current max) should not produce the outdated warning
            let v2 = parseConfig(lua: """
                return { configVersion = 2 }
                """,
            )
            assertEquals(v2.errors, [])
            assertEquals(v2.warnings, [])
        }

        @Test func testTopLevelTypeIsNotTable() {
            // A config that doesn't return a table of keys isn't applied
            assertFalse(parseConfig(lua: "return { 'a' }").allowReloadConfig)
            assertFalse(parseConfig(lua: "return 'a'").allowReloadConfig)
        }

        @Test func testParseKeyMapping() {
            let result = parseConfig(lua: """
                return {
                  keyMapping = {
                    keyNotationToKeyCode = { q = 'q', unicorn = 'u' },
                  },
                  mode = {
                    main = {
                      binding = { ['alt-unicorn'] = 'workspace wonderland' },
                    },
                  },
                }
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
                return {
                  keyMapping = {
                    keyNotationToKeyCode = { q = 'qw', [' f'] = 'f' },
                  },
                }
                """,
            ).strErrors
            assertEquals(errors1, [
                "[ERROR] keyMapping.keyNotationToKeyCode: ' f' is invalid key notation",
                "[ERROR] keyMapping.keyNotationToKeyCode.q: 'qw' is invalid key code",
            ])

            let dvorakResult = parseConfig(lua: """
                return {
                  keyMapping = { preset = 'dvorak' },
                }
                """,
            )
            assertEquals(dvorakResult.errors, [])
            assertEquals(dvorakResult.config.keyMapping, KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
            assertEquals(dvorakResult.config.keyMapping.resolve()["quote"], .q)
            let colemakResult = parseConfig(lua: """
                return {
                  keyMapping = { preset = 'colemak' },
                }
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

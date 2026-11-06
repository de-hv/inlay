-- Inlay config: only what is yours. It goes over the built-in config of Inlay, which has the rest:
-- 7 workspaces, the key bindings, the window rules, the gaps, the animations, the menu bar item…
--
--     inlay config --show [<key>]       the config in use, and where each value comes from
--     inlay config --show --mine        only what your files change
--     inlay config --files              the files of the config: Inlay's and yours
--     inlay config --explain [<key>]    what a key or a function does, its values and its default
--     inlay config --types              autocompletion of the keys in your editor
--
-- The config is made of calls: inlay.config({ … }) for the keys (merged key by key with the ones of
-- Inlay: inlay.config({ menuBar = { perMonitor = true } }) changes that key alone), inlay.bind and
-- inlay.unbind for the key bindings, inlay.window_rule for the rules (yours go before the ones of
-- Inlay), inlay.workspace for the workspaces, inlay.on for the events.
-- To split this file, put a part in a file of this folder and require('<name>') it.

-- The look of the borders and of the menu bar.
-- catppuccin | everforest | gruvbox | kanagawa | material | nord | rose-pine | tokyo-night,
-- yours in themes/<name>.lua of this folder, or { dark = 'tokyo-night', light = 'rose-pine' }
inlay.theme('material')

-- Your workspaces, with your apps: they replace the 7 of Inlay (1 to 7 on h j k l u i o).
-- cmd-alt-ctrl-<key> goes to a workspace, cmd-alt-shift-<key> moves the window there, and the
-- windows of its apps go to it. monitor: 'main' (without it) | 'secondary' | a list, in order
-- inlay.workspace({ id = '1', name = 'Terminals', key = 'h', apps = { 'com.mitchellh.ghostty' } })
-- inlay.workspace({ id = '2', name = 'Code',      key = 'j', apps = { 'dev.zed.Zed' } })
-- inlay.workspace({ id = '3', name = 'Browsers',  key = 'k', apps = { 'com.google.Chrome' } })
-- inlay.workspace({ id = '4', name = 'Chats',     key = 'l', apps = { 'com.tinyspeck.slackmacgap' } })
-- inlay.workspace({ id = '5', name = 'AI',        key = 'u' })
-- inlay.workspace({ id = '6', name = 'Other',     key = 'i', monitor = { 'secondary', 'main' } })
-- inlay.workspace({ id = '7', name = 'Free',      key = 'o' })

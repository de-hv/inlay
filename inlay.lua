-- Inlay config: only what is yours. It goes over the built-in config of Inlay, which has the rest:
-- 7 workspaces, the key bindings, the window rules, the gaps, the animations, the menu bar item…
--
--     inlay config --show [<key>]       the config in use, and where each value comes from
--     inlay config --show --mine        only what this file changes
--     inlay config --explain [<key>]    what a key does, its values and its default
--     inlay config --types              autocompletion of the keys in your editor
--
-- A table of yours is merged with the one of Inlay key by key: menuBar = { perMonitor = true }
-- changes that key alone. A value or a list replaces the one of Inlay, your window rules go before
-- the ones of Inlay, and ['<key>'] = false removes a key binding of Inlay.
-- To split this file, put a part in a file of this folder and pass require('<name>') to inlay.merge.

return {
  -- The look of the borders and of the menu bar.
  -- catppuccin | everforest | gruvbox | kanagawa | material | nord | rose-pine | tokyo-night,
  -- yours in themes/<name>.lua of this folder, or { dark = 'tokyo-night', light = 'rose-pine' }
  theme = 'material',

  -- Your workspaces, with your apps: they replace the 7 of Inlay (1 to 7 on h j k l u i o).
  -- cmd-alt-ctrl-<key> goes to a workspace, cmd-alt-shift-<key> moves the window there, and the
  -- windows of its apps go to it. monitor: 'main' (without it) | 'secondary' | a list, in order
  -- workspaces = {
  --   { id = '1', name = 'Terminals', key = 'h', apps = { 'com.mitchellh.ghostty' } },
  --   { id = '2', name = 'Code',      key = 'j', apps = { 'dev.zed.Zed' } },
  --   { id = '3', name = 'Browsers',  key = 'k', apps = { 'com.google.Chrome' } },
  --   { id = '4', name = 'Chats',     key = 'l', apps = { 'com.tinyspeck.slackmacgap' } },
  --   { id = '5', name = 'AI',        key = 'u' },
  --   { id = '6', name = 'Other',     key = 'i', monitor = { 'secondary', 'main' } },
  --   { id = '7', name = 'Free',      key = 'o' },
  -- },
}

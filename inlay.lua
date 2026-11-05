-- Inlay config
--
-- Inlay reloads this file when you save it. Every key, its values and its default:
--     inlay config --explain [<key>]          (also in docs/config-reference.lua)
--
-- The file returns the table of the config. Each section below is a table of its own, and
-- inlay.merge puts them together at the end: the tables of the same key are merged, and the
-- arrays (the window rules) are put one after the other.
--
-- To split the config, move a section to a file of this folder, which returns it:
--     -- borders.lua
--     return { borders = { width = 2 } }
-- and pass require('borders') to inlay.merge in place of the section.
--
-- Sections
--    1  General                 6  Menu bar
--    2  Callbacks               7  Borders
--    3  Workspaces & monitors   8  Programs
--    4  Layout                  9  Key bindings
--    5  Animations             10  Window rules

-- ━━ 1 · General ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local general = {
  configVersion    = 2,
  startAtLogin     = true,
  autoReloadConfig = true,    -- reload when one of the files of the config is saved

  -- The look of the borders and of the menu bar: their colors, the glow and systemColors.
  -- A theme of Inlay: catppuccin | everforest | gruvbox | kanagawa | material | nord |
  -- rose-pine | tokyo-night; one of yours (themes/<name>.lua of this folder); or one for each
  -- appearance of macOS: { dark = 'tokyo-night', light = 'rose-pine' }. Without it: 'material'.
  -- A color written in 6 or 7 wins over the theme. The wallpaper is yours: Inlay never changes it
  theme = 'material',

  -- Commands that run after Inlay starts
  afterStartupCommand = {},

  -- Show again the apps hidden with cmd-h, if you hit it by accident
  automaticallyUnhideMacosHiddenApps = false,

  -- Normalizations: https://nikitabobko.github.io/AeroSpace/guide#normalization
  enableNormalizationFlattenContainers                      = true,
  enableNormalizationOppositeOrientationForNestedContainers = true,

  -- tiles · horizontal | vertical | auto (by the shape of the monitor)
  defaultRootContainerLayout      = 'tiles',
  defaultRootContainerOrientation = 'horizontal',
}

-- ━━ 2 · Callbacks ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local callbacks = {
  -- The mouse follows the focus. Empty them to turn it off
  onFocusedMonitorChanged = { 'move-mouse monitor-lazy-center' },
  onFocusChanged          = { 'move-mouse window-lazy-center' },

  -- Commands that run when the binding mode changes
  onModeChanged = {},

  -- A program (and its arguments) that runs when the focused workspace changes. For example:
  --     { '/bin/bash', '-c', 'echo $INLAY_FOCUSED_WORKSPACE >> /tmp/workspaces' }
  execOnWorkspaceChange = {},
}

-- ━━ 3 · Workspaces & monitors ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Each workspace in one place: its key, its monitor and its apps. The key bindings of section 9
-- and the window rules of section 10 are made from this list.
--
-- The keys follow the right hand:   u i o -> 5 6 7
--                                 h j k l -> 1 2 3 4
--   cmd-alt-ctrl-<key> goes to the workspace, cmd-alt-shift-<key> moves the window there.
--
-- Monitors by role, not by name: the same rules hold whatever display is plugged in.
-- 'secondary' only matches with exactly two displays, hence the 'main' fallback for 6.
-- The main display is set in System Settings › Displays.
-- 7 has no apps: there is (almost) always a free workspace.
local workspaceList = {
  { id = '1', name = 'Terminals', key = 'h', apps = {
    'com.mitchellh.ghostty',                -- Ghostty
  } },
  { id = '2', name = 'Code',      key = 'j', apps = {
    'dev.zed.Zed',                          -- Zed
    'com.microsoft.VSCode',                 -- VS Code
  } },
  { id = '3', name = 'Browsers',  key = 'k', apps = {
    'com.google.Chrome',                    -- Chrome
    'app.zen-browser.zen',                  -- Zen
  } },
  { id = '4', name = 'Chats',     key = 'l', apps = {
    'com.tinyspeck.slackmacgap',            -- Slack
    'com.microsoft.teams2',                 -- Teams
    'ru.keepcoder.Telegram',                -- Telegram
    'net.whatsapp.WhatsApp',                -- WhatsApp
  } },
  { id = '5', name = 'AI',        key = 'u', apps = {
    'com.anthropic.claudefordesktop',       -- Claude
  } },
  { id = '6', name = 'Other',     key = 'i', monitor = { 'secondary', 'main' } },
  { id = '7', name = 'Free',      key = 'o' },
}

local workspaces = { persistentWorkspaces = {}, workspaceToMonitorForceAssignment = {} }
for _, ws in ipairs(workspaceList) do
  table.insert(workspaces.persistentWorkspaces, ws.id)
  workspaces.workspaceToMonitorForceAssignment[ws.id] = ws.monitor or 'main'
end

-- ━━ 4 · Layout ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local layout = {
  -- In points. The borders are drawn in the gaps: keep a gap at least twice borders.width,
  -- or the borders of two neighbor windows overlap
  gaps = {
    inner = { horizontal = 8, vertical = 8 },
    outer = { left = 8, right = 8, top = 8, bottom = 8 },
  },

  tiling = {
    newWindowPlacement = 'dwindle',    -- dwindle | after-focused (i3 style)
    splitTarget        = 'focused',    -- the window a new one splits: focused | cursor
    splitRatio         = 0.5,          -- what the split window keeps: 0.1 … 0.9
    startupLayout      = 'dwindle',    -- the windows open at startup: grid | row | dwindle
    minWindowSize      = 100,          -- points left by resizing: 20 … 500
  },

  focusFollowsMouse = { enabled = false },
}

-- ━━ 5 · Animations ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Curves: quint | expo | quick | ease-out | linear | ease | ease-in-out | snappy | overshot,
-- or one of animations.curves. A strong ease-out hides the frames that other apps skip;
-- a curve that overshoots makes them lay out again
local animations = {
  animations = {
    enabled         = true,
    duration        = 160,             -- ms: 0 … 500
    curve           = 'quint',
    workspaceSwitch = 'horizontal',    -- horizontal | vertical | auto | off

    -- Per kind of animation; without them, curve and duration above
    open       = { curve = 'quint', duration = 200 },
    move       = { curve = 'quint', duration = 160 },
    fullscreen = { curve = 'expo',  duration = 220 },
    workspace  = { curve = 'expo',  duration = 140 },    -- workspaceSwitch = 'off' if it stutters

    -- Curves of your own: name = { x1, y1, x2, y2 }
    curves = {
      -- bounce = { 0.34, 1.56, 0.64, 1 },
    },
  },
}

-- ━━ 6 · Menu bar ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local menuBar = {
  menuBar = {
    enabled            = true,
    -- pills | chips | hypr | minimal | dots | underline | liquid | dms
    theme              = 'hypr',
    dimEmptyWorkspaces = true,
    showMode           = true,     -- the initial of the binding mode on the focused workspace
    perMonitor         = false,    -- group the workspaces by monitor
    -- The colors and systemColors come from the theme (section 1)
  },
}

-- ━━ 7 · Borders ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- The colors and the glow come from the theme (section 1)
local borders = {
  borders = {
    enabled       = true,
    width         = 2,                -- points: 1 … 20
    cornerRadius  = 16,               -- points: 0 … 40
    squareCorners = false,            -- fill the rounded corners of the windows

    -- A window alone in its workspace, or in fullscreen: a thin border and a small gap.
    -- enabled = false: it fills the screen without a border
    singleWindow = {
      enabled = true,
      width   = 2,                    -- points: 1 … 20
      gap     = 2,                    -- points: 0 … 40, never less than width
    },
  },
}

-- ━━ 8 · Programs ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- The environment of exec-and-forget and execOnWorkspaceChange
local programs = {
  exec = {
    inheritEnvVars = true,
    -- ${NAME} is replaced by the value of the variable
    envVars = {
      PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}',
    },
  },
}

-- ━━ 9 · Key bindings ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--   cmd-alt-ctrl  + right hand   go to a workspace        (see section 3)
--   cmd-alt-shift + right hand   move the window there
--   cmd-alt-shift + left hand    an action
--   arrows: cmd-alt focus · cmd-alt-ctrl swap · cmd-alt-shift move

local main = {
  -- ── Actions
  ['cmd-alt-shift-b']     = 'balance-sizes',                                -- [b]alance
  ['cmd-alt-shift-d']     = 'arrange-workspace dwindle',                    -- [d]windle (or grid, row)
  ['cmd-alt-shift-f']     = { 'fullscreen off', 'layout floating tiling' }, -- [f]loating ⇄ tiling
  ['cmd-alt-shift-enter'] = 'fullscreen',
  ['cmd-alt-shift-s']     = 'mode service',                                 -- [s]ervice mode
  ['cmd-alt-shift-r']     = 'mode resize',                                  -- [r]esize mode
}

-- ── Workspaces: go there, or move the window there. It keeps floating or tiling; fullscreen ends
for _, ws in ipairs(workspaceList) do
  main['cmd-alt-ctrl-' .. ws.key]  = { 'workspace ' .. ws.id, 'mode main' }
  main['cmd-alt-shift-' .. ws.key] = 'move-node-to-workspace ' .. ws.id
end

-- ── Arrows. Swap: the layout keeps its shape. Move: the window leaves its column or row
for _, direction in ipairs({ 'left', 'down', 'up', 'right' }) do
  main['cmd-alt-' .. direction]       = 'focus ' .. direction
  main['cmd-alt-ctrl-' .. direction]  = 'swap ' .. direction
  main['cmd-alt-shift-' .. direction] = 'move ' .. direction
end

local service = {
  esc               = { 'reload-config', 'mode main' },
  ['cmd-alt-shift-s'] = 'mode main',                                -- leave (toggle)
  r                 = { 'flatten-workspace-tree', 'mode main' },    -- reset the layout
  f                 = { 'layout floating tiling', 'mode main' },    -- rescue a "popup"
  -- Every window back to the workspace of its app (after waking up with an external display).
  -- It runs every rule: windows moved or floated on purpose go back too
  w                 = { 'run-callback onWindowDetected --for-every-window', 'mode main' },
}
for _, direction in ipairs({ 'left', 'down', 'up', 'right' }) do
  service['cmd-alt-ctrl-' .. direction] = { 'join-with ' .. direction, 'mode main' }
end

local resize = {
  esc                   = { 'reload-config', 'mode main' },
  ['cmd-alt-shift-r']   = 'mode main',                              -- leave (toggle)
  r                     = { 'flatten-workspace-tree', 'mode main' },  -- reset the layout
  ['cmd-alt-ctrl-up']   = 'resize smart +50',
  ['cmd-alt-ctrl-down'] = 'resize smart -50',
}

local bindings = {
  -- The layout the names of the keys refer to: qwerty | dvorak | colemak
  keyMapping = {
    preset = 'qwerty',
    keyNotationToKeyCode = {},    -- names of your own, e.g. { unicorn = 'q' }
  },
  mode = {
    main    = { binding = main },
    service = { binding = service },
    resize  = { binding = resize },
  },
}

-- ━━ 10 · Window rules ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- They run for every new window and for the ones open at startup. The first rule that matches
-- is the only one that runs, so the order matters:
--   a. File dialogs float
--   b. Apps with a workspace go to it (1 to 5, from section 3)
--   c. Quick apps and settings windows float
--   d. Everything else floats where it opens (cmd-alt-shift-f tiles it)
-- 'layout tiling' first: some apps (Zen, Teams) look like popups while they restore their windows.

local rules = {}

-- ── a · File dialogs
-- The whole title, in English and Spanish: a document that only starts with "Open" still tiles
table.insert(rules, {
  match = { windowTitleRegexSubstring = [[(?i)^(open|open file|open folder|open file or folder|open workspace from file|add folder to workspace|save|save as|save workspace|choose|select|abrir|abrir archivo|abrir carpeta|guardar|guardar como|elegir|seleccionar)( ?…|\.\.\.)?$]] },
  run = { 'layout floating' },
})

-- ── b · Apps with a workspace
for _, ws in ipairs(workspaceList) do
  for _, app in ipairs(ws.apps or {}) do
    table.insert(rules, { match = { appId = app }, run = { 'layout tiling', 'move-node-to-workspace ' .. ws.id } })
  end
end

-- ── c · Floating apps
-- Quick, fixed-size or occasional windows: no workspace, and the tiling around them stays
for _, app in ipairs({
  'com.apple.finder',                       -- Finder
  'com.apple.systempreferences',            -- System Settings
  'com.apple.SystemProfiler',               -- System Information
  'com.apple.ActivityMonitor',              -- Activity Monitor
  'com.apple.Stickies',                     -- Stickies
  'com.apple.calculator',                   -- Calculator
  'com.apple.Preview',                      -- Preview
  'com.apple.DiskUtility',                  -- Disk Utility
  'com.apple.QuickTimePlayerX',             -- QuickTime Player
  'com.apple.archiveutility',               -- Archive Utility
  'com.1password.1password',                -- 1Password
  'com.raycast.macos',                      -- Raycast (its settings window)
  'com.if.Amphetamine',                     -- Amphetamine
  'info.marcel-dierkes.KeepingYouAwake',    -- KeepingYouAwake
  'net.freemacsoft.AppCleaner',             -- AppCleaner
  'cx.c3.theunarchiver',                    -- The Unarchiver
}) do
  table.insert(rules, { match = { appId = app }, run = { 'layout floating' } })
end

-- The settings windows of any other app, by title
table.insert(rules, { match = { windowTitleRegexSubstring = '(?i)(settings|preferences)' }, run = { 'layout floating' } })

-- ── d · Everything else
-- Must be the last rule. A tiling window of an app without a rule floats where it opens.
-- Dialogs already float and popups never get here. Delete it to tile everything, like AeroSpace
table.insert(rules, { match = 'test %{window-layout} ~= _tiles', run = 'layout floating' })

return inlay.merge(
  general,
  callbacks,
  workspaces,
  layout,
  animations,
  menuBar,
  borders,
  programs,
  bindings,
  { onWindowDetected = rules }
)

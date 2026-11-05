-- The built-in config of Inlay
--
-- It travels inside the app (Inlay.app/Contents/Resources/builtin-config.lua) and it is the base of
-- your config: your inlay.lua goes over it, and only says what is yours. Don't edit this file; set
-- in your inlay.lua what you want different. A table of yours is merged with the one of here key by
-- key, a value or a list of yours replaces the one of here, and your window rules go first.
--     inlay config --show [<key>]       the config in use, and where each value comes from
--     inlay config --explain [<key>]    what a key does, its values and its default
--
-- Each section below is a table of its own, put together by inlay.merge at the end.
--
-- Sections
--    1  General                 6  Menu bar
--    2  Callbacks               7  Borders
--    3  Workspaces & monitors   8  Programs
--    4  Layout                  9  Key bindings
--    5  Animations             10  Window rules

-- ━━ 1 · General ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

local general = {
  startAtLogin     = true,
  autoReloadConfig = true,    -- reload when one of the files of the config is saved

  -- The look of the borders and of the menu bar comes from the theme: 'material' without the key
  -- 'theme' (see the inlay.lua of a new install)

  -- Commands that run after Inlay starts
  afterStartupCommand = {},

  -- Show again the apps hidden with cmd-h, if you hit it by accident
  automaticallyUnhideMacosHiddenApps = false,

  -- Normalizations: a container with one child is flattened, and a container in another one takes
  -- the opposite orientation
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

-- 7 workspaces without apps: put your own, with your apps, in 'workspaces' of your inlay.lua (yours
-- replace these). Inlay makes from the list the persistent workspaces, the monitor of each one, two
-- key bindings for each one (workspaceKeys) and a window rule for each app.
--
-- The keys follow the right hand:   u i o -> 5 6 7
--                                 h j k l -> 1 2 3 4
--   cmd-alt-ctrl-<key> goes to the workspace, cmd-alt-shift-<key> moves the window there.
--
-- Monitors by role, not by name: the same rules hold whatever display is plugged in.
-- 'secondary' only matches with exactly two displays, hence the 'main' fallback for 6.
-- The main display is set in System Settings › Displays. Without monitor: 'main'.
local workspaces = {
  workspaces = {
    { id = '1', key = 'h' },
    { id = '2', key = 'j' },
    { id = '3', key = 'k' },
    { id = '4', key = 'l' },
    { id = '5', key = 'u' },
    { id = '6', key = 'i', monitor = { 'secondary', 'main' } },
    { id = '7', key = 'o' },
  },
  -- The modifiers of the key bindings of each workspace: go to it, and move the window there
  workspaceKeys = { focus = 'cmd-alt-ctrl', move = 'cmd-alt-shift' },
}

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

--   cmd-alt-ctrl  + right hand   go to a workspace        (made from section 3)
--   cmd-alt-shift + right hand   move the window there    (the same)
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
--   b. The apps of the workspaces go to theirs (made from 'workspaces': the item 'workspaces')
--   c. The apps of macOS that are quick or occasional, and settings windows, float
--   d. Everything else floats where it opens (cmd-alt-shift-f tiles it)
-- 'layout tiling' first: some apps (Zen, Teams) look like popups while they restore their windows.

local rules = {}

-- ── a · File dialogs
-- The whole title, in English and Spanish: a document that only starts with "Open" still tiles
table.insert(rules, {
  match = { windowTitleRegexSubstring = [[(?i)^(open|open file|open folder|open file or folder|open workspace from file|add folder to workspace|save|save as|save workspace|choose|select|abrir|abrir archivo|abrir carpeta|guardar|guardar como|elegir|seleccionar)( ?…|\.\.\.)?$]] },
  run = { 'layout floating' },
})

-- ── b · The apps of the workspaces: their rules take the place of this item
table.insert(rules, 'workspaces')

-- ── c · Floating apps of macOS
-- Quick, fixed-size or occasional windows: no workspace, and the tiling around them stays.
-- The apps of others that you want floating go in the window rules of your inlay.lua
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
}) do
  table.insert(rules, { match = { appId = app }, run = { 'layout floating' } })
end

-- The settings windows of any other app, by title
table.insert(rules, { match = { windowTitleRegexSubstring = '(?i)(settings|preferences)' }, run = { 'layout floating' } })

-- ── d · Everything else
-- Must be the last rule. A tiling window of an app without a rule floats where it opens.
-- Dialogs already float and popups never get here. Your rules go before it: a rule of yours
-- for an app is the way to tile it
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

-- Reference of the config of Inlay: every key, what it does, its possible values and its default.
--
-- It is a documentation file, and it is also a valid config: every key is written with its default value
-- (a few of them, with an example, where the default is an empty list or table).
-- 'inlay config --explain' prints it, and 'inlay config --explain <key>' prints the part of a key or a table:
--
--   inlay config --explain borders.width
--   inlay config --explain tiling
--   inlay config --explain gaps
--
-- The config that Inlay ships with is another file: inlay.lua, at the root of the repo.
-- Inlay reads ~/.config/inlay/inlay.lua (or $XDG_CONFIG_HOME/inlay/inlay.lua), or else ~/.inlay.lua.
-- With both files it reports an ambiguity and keeps the config it had.
--
-- The config is a Lua file that returns a table, like this one. It can be split into files of its folder:
-- require('name') runs name.lua, once, and gives what it returns. inlay.merge(...) puts tables together: the
-- tables of the same key are merged, the arrays are put one after the other, and for anything else the last
-- one wins. The inlay.lua that Inlay ships with is written that way. Inlay reloads the config when one of its
-- files is saved.
--
-- Inlay is a fork of AeroSpace: the keys that come from it keep their meaning, with camelCase names
-- (default-root-container-layout is defaultRootContainerLayout). The links below point to the documentation
-- of AeroSpace, which applies to those keys. All the commands: https://nikitabobko.github.io/AeroSpace/commands

return {
  -- Config version for compatibility and deprecations. Version 1 still loads, with a warning.
  -- 'persistentWorkspaces' needs version 2
  -- See: https://nikitabobko.github.io/AeroSpace/guide#config-version
  -- Possible values: 1|2
  -- Fallback value (if you omit the key): configVersion = 1
  configVersion = 2,

  -- Commands that run after Inlay starts, once the windows that were already open are in their places.
  -- A command, or a list of commands
  -- Fallback value (if you omit the key): afterStartupCommand = {}
  afterStartupCommand = {},

  -- Start Inlay at login. Inlay adds itself to the login items of macOS, or removes itself from them,
  -- every time the config is loaded
  -- Possible values: true|false
  -- Fallback value (if you omit the key): startAtLogin = false
  startAtLogin = false,

  -- Reload the config when the config file is saved. With it, the menu bar item and the borders follow what you
  -- write in the file. It works when the config is a symbolic link, and with the editors that save by replacing
  -- the file. Without it, use 'inlay reload-config' or the menu
  -- Possible values: true|false
  -- Fallback value (if you omit the key): autoReloadConfig = true
  autoReloadConfig = true,

  -- Normalization: containers with a single child are flattened
  -- See: https://nikitabobko.github.io/AeroSpace/guide#normalization
  -- Possible values: true|false
  -- Fallback value (if you omit the key): enableNormalizationFlattenContainers = true
  enableNormalizationFlattenContainers = true,

  -- Normalization: a container nested in another one gets the opposite orientation
  -- See: https://nikitabobko.github.io/AeroSpace/guide#normalization
  -- Possible values: true|false
  -- Fallback value (if you omit the key): enableNormalizationOppositeOrientationForNestedContainers = true
  enableNormalizationOppositeOrientationForNestedContainers = true,

  -- The layout of the root container of a new workspace.
  -- Inlay has no accordion layout: 'accordion' is accepted with a warning and treated as 'tiles'
  -- See: https://nikitabobko.github.io/AeroSpace/guide#layouts
  -- Possible values: tiles
  -- Fallback value (if you omit the key): defaultRootContainerLayout = 'tiles'
  defaultRootContainerLayout = 'tiles',

  -- The orientation of the root container of a new workspace
  -- Possible values: horizontal|vertical|auto
  -- 'auto' means: wide monitor (anything wider than high) gets horizontal orientation,
  --               tall monitor (anything higher than wide) gets vertical orientation
  -- Fallback value (if you omit the key): defaultRootContainerOrientation = 'auto'
  defaultRootContainerOrientation = 'auto',

  -- Commands that run when the focused monitor changes. A command, or a list of commands.
  -- The example makes the mouse follow the focus
  -- See https://nikitabobko.github.io/AeroSpace/guide#on-focus-changed-callbacks
  -- See https://nikitabobko.github.io/AeroSpace/commands#move-mouse
  -- Fallback value (if you omit the key): onFocusedMonitorChanged = {}
  onFocusedMonitorChanged = { 'move-mouse monitor-lazy-center' },

  -- Commands that run when the focused window changes. A command, or a list of commands.
  -- For example: onFocusChanged = { 'move-mouse window-lazy-center' }
  -- See https://nikitabobko.github.io/AeroSpace/guide#on-focus-changed-callbacks
  -- Fallback value (if you omit the key): onFocusChanged = {}
  onFocusChanged = {},

  -- Commands that run every time the binding mode changes. A command, or a list of commands
  -- See: https://nikitabobko.github.io/AeroSpace/guide#binding-modes
  -- See: https://nikitabobko.github.io/AeroSpace/commands#mode
  -- Fallback value (if you omit the key): onModeChanged = {}
  onModeChanged = {},

  -- A program that Inlay runs every time the focused workspace changes: the program and its arguments.
  -- It gets the INLAY_FOCUSED_WORKSPACE and INLAY_PREV_WORKSPACE variables (and the AEROSPACE_* ones).
  -- For example: execOnWorkspaceChange = { '/bin/bash', '-c', 'echo $INLAY_FOCUSED_WORKSPACE >> /tmp/workspaces' }
  -- See: https://nikitabobko.github.io/AeroSpace/guide#exec-on-workspace-change-callback
  -- Fallback value (if you omit the key): execOnWorkspaceChange = {}
  execOnWorkspaceChange = {},

  -- You can effectively turn off macOS "Hide application" (cmd-h) feature by toggling this flag
  -- Useful if you don't use this macOS feature, but accidentally hit cmd-h or cmd-alt-h key
  -- Also see: https://nikitabobko.github.io/AeroSpace/goodies#disable-hide-app
  -- Possible values: true|false
  -- Fallback value (if you omit the key): automaticallyUnhideMacosHiddenApps = false
  automaticallyUnhideMacosHiddenApps = false,

  -- List of workspaces that should stay alive even when they contain no windows,
  -- even when they are invisible. They are the workspaces that the menu bar item always shows.
  -- The other workspaces exist while they have windows or they are the visible one.
  -- This config option is only available since 'configVersion = 2'
  -- Fallback value (if you omit the key): persistentWorkspaces = {}
  persistentWorkspaces = { '1', '2', '3', '4', '5', '6' },

  focusFollowsMouse = {
    -- The window under the mouse cursor gets the focus
    -- Possible values: true|false
    -- Fallback value (if you omit the key): focusFollowsMouse.enabled = false
    enabled = false,
  },

  keyMapping = {
    -- The keyboard layout that the names of the keys in the bindings refer to
    -- See https://nikitabobko.github.io/AeroSpace/guide#key-mapping
    -- Possible values: qwerty|dvorak|colemak
    -- Fallback value (if you omit the key): keyMapping.preset = 'qwerty'
    preset = 'qwerty',

    -- Names of keys of your own, on top of the preset: the name to use in the bindings = the key it stands for.
    -- A name can't contain spaces or dashes. The example calls the 'q' key 'unicorn'
    -- See https://nikitabobko.github.io/AeroSpace/guide#key-mapping
    -- Fallback value (if you omit the key): keyMapping.keyNotationToKeyCode = {}
    keyNotationToKeyCode = { unicorn = 'q' },
  },

  -- Not a key of Inlay: 'afterLoginCommand' is deprecated since AeroSpace 0.19.0. Only an empty list is
  -- accepted; anything else is an error. Use 'afterStartupCommand' and 'startAtLogin'
  -- afterLoginCommand = {}

  -- Not a key of Inlay: it has no accordion layout. The key of AeroSpace is accepted with a warning and
  -- ignored. Drop it from your config
  -- accordionPadding = 30

  -- Deprecated key of AeroSpace. Only 'smart' is accepted; anything else is an error. Drop it from your config
  -- nonEmptyWorkspacesRootContainersLayoutOnStartup = 'smart'

  -- Deprecated key of AeroSpace: it is always an error. Drop it from your config
  -- indentForNestedContainersWithTheSameOrientation = 30

  -- Not a table of Inlay anymore: the palettes are gone, and every color is set on its own in 'menuBar.colors' and
  -- 'borders'. The table is accepted with a warning and ignored, so that a config of a previous version still loads.
  -- Drop it from your config
  -- theme = {}

  -- Not a table of Inlay anymore: the notice after a reload is gone. The table is accepted with a warning and
  -- ignored. Drop it from your config
  -- notifications = {}

  -- Not a table of Inlay anymore: the Settings window is gone, and the config is only the file. The table is
  -- accepted with a warning and ignored. Drop it from your config
  -- settings = {}

  -- Gaps between windows (inner.*) and between the windows and the edges of the monitor (outer.*), in points.
  -- Possible values:
  -- - Constant:     outer = { top = 8 }
  -- - Per monitor:  outer = { top = { { monitor = { main = 16 } }, { monitor = { ['some-pattern'] = 32 } }, 24 } }
  --                 In this example, 24 is a default value when there is no match.
  --                 Monitor pattern is the same as for 'workspaceToMonitorForceAssignment'.
  -- The window borders (see 'borders') are drawn outside of the windows, in the gaps.
  -- Keep the gaps at least twice as big as borders.width, or the borders of neighbor windows touch.
  -- The outer gaps must be at least as big as borders.width, or the border is cut by the edge of the screen.
  -- Fallback value (if you omit the keys): 0
  gaps = {
    inner = {
      -- The gap between two windows that are side by side
      -- Fallback value (if you omit the key): inner.horizontal = 0
      horizontal = 0,

      -- The gap between two windows that are one above the other
      -- Fallback value (if you omit the key): inner.vertical = 0
      vertical = 0,
    },

    outer = {
      -- The gap between the windows and the left edge of the monitor
      -- Fallback value (if you omit the key): outer.left = 0
      left = 0,

      -- The gap between the windows and the bottom edge of the monitor
      -- Fallback value (if you omit the key): outer.bottom = 0
      bottom = 0,

      -- The gap between the windows and the top edge of the monitor (under the menu bar)
      -- Fallback value (if you omit the key): outer.top = 0
      top = 0,

      -- The gap between the windows and the right edge of the monitor
      -- Fallback value (if you omit the key): outer.right = 0
      right = 0,
    },

    -- Not a key of Inlay anymore: 'borders.singleWindow' decides the gap and the border of a window alone in its
    -- workspace. The key is accepted with a warning and ignored. Drop it from your config
    -- smart = true
  },

  -- The environment of the programs that Inlay starts (exec-and-forget, execOnWorkspaceChange).
  -- They also get INLAY_WINDOW_ID, INLAY_WORKSPACE, INLAY_FOCUSED_WORKSPACE and INLAY_PREV_WORKSPACE
  -- (and the same variables under their AEROSPACE_* names)
  -- See: https://nikitabobko.github.io/AeroSpace/guide#exec-env-vars
  exec = {
    -- The programs inherit the environment of Inlay
    -- Possible values: true|false
    -- Fallback value (if you omit the key): inheritEnvVars = true
    inheritEnvVars = true,

    -- Variables that are set or replaced. ${NAME} is replaced by the value of the variable. 'PWD' can't be set
    -- Fallback value (if you omit the table): PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}'
    envVars = {
      PATH = '/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}',
    },
  },

  -- Where the tiling windows are placed
  tiling = {
    -- Possible values: dwindle|after-focused
    -- - dwindle.       The new window splits the focused window in two (inspired by the dwindle layout of Hyprland).
    --                  A window wider than tall is split side by side, otherwise the two windows are stacked.
    --                  The new window is the right/bottom one.
    --                  When a window is closed, its neighbor gets the space back.
    -- - after-focused. AeroSpace behavior. The new window is placed after the focused window in the same container,
    --                  and all the windows of the container share the space.
    -- Fallback value (if you omit the key): newWindowPlacement = 'dwindle'
    newWindowPlacement = 'dwindle',

    -- Only for 'dwindle'. The fraction of its space that the split window keeps.
    -- 0.5 = two halves. 0.6 = the split window keeps 60%, the new window gets 40%
    -- Possible values: 0.1 ... 0.9
    -- Fallback value (if you omit the key): splitRatio = 0.5
    splitRatio = 0.5,

    -- Only for 'dwindle'. Which window the new window splits.
    -- Possible values: focused|cursor
    -- - focused. The focused window. If it isn't a tiling window of the workspace (it floats, or the new window
    --            goes to another workspace), the most recently used tiling window of the workspace.
    -- - cursor.  The tiling window under the mouse cursor, like Hyprland. If there is none (the cursor is in a gap,
    --            on another monitor, over a fullscreen window, or the workspace isn't visible), the same as 'focused'.
    -- Fallback value (if you omit the key): splitTarget = 'focused'
    splitTarget = 'focused',

    -- How the windows that are already open when Inlay starts (or when 'enable on' resumes it) are arranged,
    -- in every workspace. The 'onWindowDetected' rules run for those windows first, so every window is
    -- arranged in the workspace that its rule sends it to. The windows that are opened later follow
    -- 'newWindowPlacement'
    -- Possible values: grid|row|dwindle
    -- - grid.    A balanced grid: ceil(sqrt(n)) columns for n windows, and as many rows as needed.
    --            The windows of the last row share its width: 5 windows are 3 on top of 2.
    -- - row.     One row. All the windows get the same width.
    -- - dwindle. No arrangement: the windows are placed one after another, like new windows. With
    --            newWindowPlacement = 'dwindle' that is a spiral, and the last windows are small.
    -- Fallback value (if you omit the key): startupLayout = 'grid'
    startupLayout = 'grid',

    -- The smallest width and height, in points, that resizing leaves to a tiling window. The 'resize' command and
    -- dragging an edge with the mouse stop there: the window isn't shrunk further, and its neighbors aren't either
    -- when it is the window that grows. Reaching the limit isn't an error: 'resize' still exits with 0.
    -- It only limits resizing. When the windows of a workspace don't fit with this size (many windows on a small
    -- monitor), the layout still gives every window its part, however small
    -- Possible values: 20 ... 500
    -- Fallback value (if you omit the key): minWindowSize = 100
    minWindowSize = 100,
  },

  -- The menu bar item
  menuBar = {
    -- Show the menu bar item. With 'false' Inlay keeps working: use the key bindings and the CLI. Opening Inlay
    -- again from Applications opens this file in an editor
    -- Possible values: true|false
    -- Fallback value (if you omit the key): enabled = true
    enabled = true,

    -- The shape of the item. All the existing workspaces are shown, and the focused one is marked
    -- Possible values: pills|chips|hypr|minimal|dots|underline|liquid|dms
    -- - pills.   Round workspaces, and the focused one a wider pill, like the workspace indicator of GNOME
    --            and of many Hyprland setups. Otherwise like chips.
    -- - chips.   The workspaces alone. The ones with windows have a faint background,
    --            the focused one has a solid background, and the empty ones are dimmed.
    -- - hypr.    The names of the workspaces in slots of the same width, and a square in place of the focused
    --            workspace, like the Monitor Workspaces plugin of the Omarchy bar (Hyprland). With 'perMonitor'
    --            a frame goes around the workspace that another monitor shows, and a bolder line divides the
    --            monitors. In a binding mode other than 'main' the square shows the initial of the mode.
    -- - minimal. Only the focused workspace.
    -- - dots.    A dot per workspace, without names: a disc if it has windows, a ring if it is empty.
    --            The focused one is a pill, which stretches on its way to the next one, like the page
    --            indicator of iOS. In a binding mode the pill grows to hold the initial of the mode.
    -- - underline. The names of the workspaces, and a bar under the focused one, in its color. The bar
    --            stretches towards the next workspace and then shrinks into it. In a binding mode the
    --            initial of the mode takes the place of the name.
    -- - liquid.  A dot per workspace, and a drop with the name of the focused one, which flows to the next
    --            workspace leaving a trail behind. In a binding mode the drop shows the initial of the mode.
    -- - dms.     Small round workspaces on a faint track, and the focused one a wider pill with its name,
    --            like the workspace switcher of Dank Material Shell. With 'perMonitor' each monitor gets its
    --            own track. Material 3 colors suit it:
    --            focused = '#D0BCFF', occupied = '#CCC2DC', empty = '#938F99', accent = '#EFB8C8'
    -- ('chips-icons', a theme of a previous version, is accepted with a warning and treated as 'chips')
    -- Fallback value (if you omit the key): theme = 'liquid'
    theme = 'liquid',

    -- Not a key of Inlay anymore: the menu bar item doesn't show the icons of the apps. The key is accepted
    -- with a warning and ignored, so that a config written for a previous version still loads. Drop it from your config
    -- showAppIcons = false

    -- Draw the workspaces without windows fainter
    -- Possible values: true|false
    -- Fallback value (if you omit the key): dimEmptyWorkspaces = true
    dimEmptyWorkspaces = true,

    -- Show the binding mode when it isn't 'main': its initial ('R' for 'resize') on the marker of the focused
    -- workspace. In 'chips', 'pills', 'minimal', 'underline', 'liquid' and 'dms' the initial takes the place of the name; in
    -- 'hypr' and 'dots' the marker grows to hold it. The item keeps its width: nothing moves when the mode changes
    -- Possible values: true|false
    -- Fallback value (if you omit the key): showMode = true
    showMode = true,

    -- Group the workspaces by monitor, from left to right, with a line between the monitors, and draw a hollow
    -- marker on the workspace that another monitor shows ('hypr': a frame around its name; 'dms': a track per monitor
    -- instead of the line). With one monitor it changes nothing
    -- Possible values: true|false
    -- Fallback value (if you omit the key): perMonitor = false
    perMonitor = false,

    -- Draw the item like the other icons of the menu bar: in the color of the menu bar text, as a template image that
    -- macOS colors (and dims on a display that isn't the active one), whatever 'menuBar.colors' says. The colors of
    -- that table stay in the config and apply again when this is 'false'
    -- Possible values: true|false
    -- Fallback value (if you omit the key): systemColors = false
    systemColors = false,

    -- Colors of the item.
    -- Possible values:
    -- - '#RRGGBB' or '#RRGGBBAA'
    -- - 'system-accent'. System Settings -> Appearance -> Accent color
    -- - 'auto'.          The color of the menu bar text: white on a dark menu bar, black on a light one.
    --                    For 'accent': the same as 'focused'
    -- With a fixed color in 'focused', the name of the workspace is drawn in black or white,
    -- whichever has more contrast. A fixed color doesn't adapt to the menu bar: it is the same in the light and
    -- in the dark appearance. 'systemColors = true' overrides them all
    colors = {
      -- The marker of the focused workspace while it shows the binding mode (see 'showMode').
      -- With a fixed color, the initial is drawn in white, or in black over a light color
      -- Fallback value (if you omit the key): accent = 'auto'
      accent = 'auto',

      -- The background of the focused workspace
      -- Fallback value (if you omit the key): focused = 'auto'
      focused = 'auto',

      -- The workspaces with windows: the color of the name and, at 16%, of its background
      -- Fallback value (if you omit the key): occupied = 'auto'
      occupied = 'auto',

      -- The workspaces without windows
      -- Fallback value (if you omit the key): empty = 'auto'
      empty = 'auto',
    },
  },

  -- The animations of the tiling windows. A window slides to its new frame, and its border goes with it, when:
  -- - a window opens (it grows from the center of its tile, from 87% of its size, while its neighbor makes room) or closes,
  -- - a window is moved with 'swap' or 'move' (the key bindings, the CLI),
  -- - the 'fullscreen' command makes a window grow from its tile to the screen, or shrink back to its tile,
  -- - the screen switches workspaces (see workspaceSwitch).
  -- Nothing else is animated: resizing, balance-sizes, the startup, the mouse.
  -- With "Reduce motion" (System Settings -> Accessibility -> Display) nothing is animated.
  -- Inlay moves and resizes the windows of other apps through the Accessibility API: a window that is slow to
  -- resize (some browsers, Electron apps) skips frames of the animation, but it always ends in its exact frame
  animations = {
    -- Possible values: true|false
    -- Fallback value (if you omit the key): enabled = true
    enabled = true,

    -- How long a window takes to get to its new frame, in milliseconds. 0 = no animation
    -- Possible values: 0 ... 500
    -- Fallback value (if you omit the key): duration = 160
    duration = 160,

    -- How switching workspaces slides the windows, in the same duration: the windows of the workspace that is left
    -- go out of the screen, and the ones of the workspace that is shown come in. Only the tiling windows slide: the
    -- floating ones appear and disappear as before. The windows never cross another screen, and each screen of
    -- the ones that switch workspace decides on its own:
    -- - 'horizontal': from side to side. Toward a later workspace (in the order of the menu bar item) they move to the
    --   left, toward an earlier one to the right. A screen with another screen on one side uses the other side for
    --   both, in and out; one with screens on both sides doesn't slide.
    -- - 'vertical': through the bottom of the screen, out downwards and in from below (macOS doesn't let a window
    --   above the menu bar, so the top can't be used). A screen with another screen below it doesn't slide.
    -- - 'auto': 'horizontal' on a screen without screens on its sides, else 'vertical'.
    -- - 'off': no slide. The other animations stay.
    -- true and false, what an earlier version wrote, mean 'horizontal' and 'off'
    -- Possible values: 'horizontal' | 'vertical' | 'auto' | 'off'
    -- Fallback value (if you omit the key): workspaceSwitch = 'horizontal'
    workspaceSwitch = 'horizontal',

    -- How the movement is spread over the duration: a cubic Bézier curve, like the 'bezier' of Hyprland and the
    -- cubic-bezier() of CSS. The presets:
    -- - 'quint'. easeOutQuint, the curve of the windows in Hyprland and Omarchy: most of the movement at the start
    -- - 'expo'. easeOutExpo: fast to leave and very gentle to arrive, like the animations of macOS
    -- - 'quick'. The 'quick' curve of Hyprland
    -- - 'ease-out'. Quick to leave, gentle to arrive: the curve of Inlay before there were curves
    -- - 'linear', 'ease', 'ease-in-out'. The ones of CSS
    -- - 'snappy'. Fast, and a soft landing
    -- - 'overshot'. It goes a bit past its frame and comes back: the popin of a Hyprland setup
    -- or the name of a curve of 'animations.curves'. A curve that overshoots also resizes the window past its tile
    -- for a moment: some apps (browsers, Electron) are slow to redraw that
    -- Fallback value (if you omit the key): curve = 'quint'
    curve = 'quint',

    -- The curve and the duration of a new window, that grows from the center of its tile: { curve = '...', duration = ... },
    -- both optional: the one left out is the one of 'animations'
    -- Fallback value (if you omit the key): open = { curve = 'quint', duration = 200 }
    open = { curve = 'quint', duration = 200 },

    -- The same for the windows that make room for a new one, take the space of one that closed, or move with 'swap'
    -- or 'move'. Fallback value (if you omit the key): move = { curve = 'quint', duration = 160 }
    move = { curve = 'quint', duration = 160 },

    -- The same for the 'fullscreen' command, in and out.
    -- Fallback value (if you omit the key): fullscreen = { curve = 'expo', duration = 220 }
    fullscreen = { curve = 'expo', duration = 220 },

    -- The same for switching workspaces: the windows that slide out and in. They all move at once: 'off' in
    -- workspaceSwitch if it stutters. Fallback value (if you omit the key): workspace = { curve = 'expo', duration = 140 }
    workspace = { curve = 'expo', duration = 140 },

    -- Curves of your own: the name = { x1, y1, x2, y2 }, the control points of the curve. x1 and x2 must be in
    -- 0 ... 1; y1 and y2 can be below 0 or above 1 (an overshoot). A name of a preset is replaced by yours
    curves = {
      -- bounce = { 0.34, 1.56, 0.64, 1 },
    },
  },

  -- The borders of the windows
  borders = {
    -- Draw a border around every normal window of the visible workspaces, tiling or floating.
    -- A fullscreen window (the 'fullscreen' command) keeps its border: where the outer gaps leave no room for it,
    -- it is drawn just inside of the screen.
    -- No border for: the windows in the native fullscreen of macOS, the tiling windows that a fullscreen window
    -- covers, minimized windows, windows of hidden apps, popups, and the dialogs and sheets that float on their own
    -- (what Inlay detects as a dialog: see 'inlay debug-windows'). A normal window that you make floating,
    -- with 'layout floating' or with an 'onWindowDetected' rule, keeps its border
    -- Possible values: true|false
    -- Fallback value (if you omit the key): enabled = true
    enabled = true,

    -- The thickness of the border, in points. The border is drawn outside of the frame of the window:
    -- it never covers the content of the window, it takes a part of the gap. See 'gaps'
    -- Possible values: 1 ... 20
    -- Fallback value (if you omit the key): width = 4
    width = 4,

    -- The radius of the corners, in points. Inlay can't read the real radius of the windows of other apps,
    -- so tune it by eye. 16 is close to the windows of macOS 26 and later, 10 to the ones of macOS 14 and 15.
    -- It is the radius of the inner edge of the border. Its outer edge is square with squareCorners, and
    -- rounded (cornerRadius + width) without it. 0 = a square border that doesn't cover the corners of the windows
    -- Possible values: 0 ... 40
    -- Fallback value (if you omit the key): cornerRadius = 16
    cornerRadius = 16,

    -- The border fills the rounded corners of the windows, so that they look square. The outer edge of the border
    -- is square, and its inner edge follows the corners of the window (cornerRadius): the corners that the window
    -- leaves empty take the color of the border. Set cornerRadius to the radius of the windows, or a bit more:
    -- with less, a bit of what is behind the window shows in its corners. A border with a translucent color fills
    -- the corners with that same color, and a window without a border (a transparent color) keeps its round corners.
    -- The shadow of the window stays round: macOS draws it.
    -- false: the border follows the rounded corners of the windows
    -- Possible values: true|false
    -- Fallback value (if you omit the key): squareCorners = true
    squareCorners = true,

    -- The color of the border of the focused window, if it is a tiling one.
    -- A fully transparent color ('#00000000') means "no border"
    -- Possible values: '#RRGGBB', '#RRGGBBAA' or 'system-accent' (System Settings -> Appearance -> Accent color)
    -- Fallback value (if you omit the key): activeColor = 'system-accent'
    activeColor = 'system-accent',

    -- The color of the border of the windows that aren't focused.
    -- With inactiveColor = '#00000000' only the focused window has a border
    -- Possible values: '#RRGGBB', '#RRGGBBAA' or 'system-accent'
    -- Fallback value (if you omit the key): inactiveColor = '#8E8E9373'
    inactiveColor = '#8E8E9373',

    -- The color of the border of the focused window, if it is a floating one
    -- Possible values: '#RRGGBB', '#RRGGBBAA' or 'system-accent'
    -- Fallback value (if you omit the key): floatingColor = '#BF5AF2'
    floatingColor = '#BF5AF2',

    -- A glow around the focused window: a halo of the color of its border (the active, the floating or the mode
    -- color) that fades out outwards, outside of the border. The windows that aren't focused never glow
    -- Possible values: true|false
    -- Fallback value (if you omit the key): glow = false
    glow = false,

    -- The blur radius of the glow, in points: about how far from the border the glow reaches. It is drawn
    -- over whatever is around the window: the gaps and, if it is wide enough, the edges of the neighbor windows
    -- Possible values: 1 ... 40
    -- Fallback value (if you omit the key): glowRadius = 12
    glowRadius = 12,

    -- Not a key of Inlay anymore: 'borders.singleWindow' enabled = false leaves a window alone in its workspace
    -- without a border. The key is accepted with a warning and ignored. Drop it from your config
    -- hideWhenSingle = false

    -- The color of the border of the focused window while a binding mode is active: the name of the mode =
    -- the color. It wins over activeColor and floatingColor. A mode without an entry keeps the normal color
    -- Possible values: '#RRGGBB', '#RRGGBBAA' or 'system-accent'
    -- Fallback value (if you omit the table): empty
    modeColors = {
      service = '#FF453A',
    },

    -- The tiling window alone in its workspace, and the window in fullscreen (the 'fullscreen' command, also when
    -- other windows are behind it), look the same: a border of their own, in the colors of the other borders, and a
    -- gap around the window, between it and the edges of the visible part of the screen (under the menu bar, above
    -- the Dock). The outer gaps of 'gaps' don't apply to them. As soon as a second tiling window joins it, the window
    -- gets the outer gaps and the border of 'borders' again. Floating windows don't count, and keep their borders;
    -- a floating window made fullscreen looks like the others. 'fullscreen --no-outer-gaps' fills the screen, without
    -- a border, and so does the macOS native fullscreen
    singleWindow = {
      -- The border and the gap. With 'false' the window fills the screen, without a border
      -- Possible values: true|false
      -- Fallback value (if you omit the key): enabled = true
      enabled = true,

      -- The width of the border, in points
      -- Possible values: 1 ... 20
      -- Fallback value (if you omit the key): width = 1
      width = 1,

      -- The room between the window and the edges of the screen, in points. Never less than 'width': with a gap
      -- narrower than the border, the gap is as wide as the border, so that the edge of the screen doesn't cut it
      -- Possible values: 0 ... 40
      -- Fallback value (if you omit the key): gap = 2
      gap = 2,
    },
  },

  -- The key bindings of a binding mode: [mode.<name>.binding]. Every entry is: the key = a command, or a
  -- list of commands. Only the bindings of the active mode work; the 'mode' command switches the mode.
  -- The 'main' mode must always exist, and it is the active one when Inlay starts.
  --
  -- All possible keys:
  -- - Letters.        a, b, c, ..., z
  -- - Numbers.        0, 1, 2, ..., 9
  -- - Keypad numbers. keypad0, keypad1, keypad2, ..., keypad9
  -- - F-keys.         f1, f2, ..., f20
  -- - Special keys.   minus, equal, period, comma, slash, backslash, quote, semicolon,
  --                   backtick, leftSquareBracket, rightSquareBracket, space, enter, esc,
  --                   backspace, tab, pageUp, pageDown, home, end, forwardDelete,
  --                   sectionSign (ISO keyboards only, european keyboards only)
  -- - Keypad special. keypadClear, keypadDecimalMark, keypadDivide, keypadEnter, keypadEqual,
  --                   keypadMinus, keypadMultiply, keypadPlus
  -- - Arrows.         left, down, up, right
  --
  -- All possible modifiers: cmd, alt, ctrl, shift
  --
  -- All possible commands: https://nikitabobko.github.io/AeroSpace/commands
  -- See: https://nikitabobko.github.io/AeroSpace/guide#binding-modes
  -- Fallback value (if you omit the table): no bindings
  mode = {
    main = {
      binding = {
        -- See: https://nikitabobko.github.io/AeroSpace/commands#layout
        ['alt-slash'] = 'layout tiles horizontal vertical',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#balance-sizes
        ['cmd-alt-comma'] = 'balance-sizes',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#focus
        ['alt-h'] = 'focus left',
        ['alt-j'] = 'focus down',
        ['alt-k'] = 'focus up',
        ['alt-l'] = 'focus right',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#move
        ['alt-shift-h'] = 'move left',
        ['alt-shift-j'] = 'move down',
        ['alt-shift-k'] = 'move up',
        ['alt-shift-l'] = 'move right',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#resize
        ['alt-minus'] = 'resize smart -50',
        ['alt-equal'] = 'resize smart +50',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#workspace
        ['alt-1'] = 'workspace 1',
        ['alt-2'] = 'workspace 2',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#move-node-to-workspace
        ['alt-shift-1'] = 'move-node-to-workspace 1',
        ['alt-shift-2'] = 'move-node-to-workspace 2',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#workspace-back-and-forth
        ['alt-tab'] = 'workspace-back-and-forth',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#exec-and-forget
        ['alt-enter'] = 'exec-and-forget open -a Terminal',

        -- See: https://nikitabobko.github.io/AeroSpace/commands#mode
        ['alt-shift-semicolon'] = 'mode service',
      },
    },

    -- A binding mode of your own. The name is free: 'service' is only an example
    -- See: https://nikitabobko.github.io/AeroSpace/guide#binding-modes
    service = {
      binding = {
        esc = { 'reload-config', 'mode main' },
        r = { 'flatten-workspace-tree', 'mode main' }, -- reset layout
        f = { 'layout floating tiling', 'mode main' }, -- Toggle between floating and tiling layout
        backspace = { 'close-all-windows-but-current', 'mode main' },
        -- Run the 'onWindowDetected' rules again for every open window
        w = { 'run-callback onWindowDetected --for-every-window', 'mode main' },
      },
    },
  },

  -- A rule that runs commands for every window that Inlay detects: the new windows and, when Inlay starts
  -- (or 'enable on' resumes it), the windows that are already open. One table in onWindowDetected per rule.
  -- The rules are checked in their order, and the first one that matches wins, unless it has
  -- 'checkFurtherCallbacks = true'. 'inlay run-callback onWindowDetected --for-every-window' runs the
  -- rules again for all the open windows
  -- 'layout tiling' in a rule doesn't tile the windows that Inlay detects as dialogs (the Save and Open panels,
  -- alerts): they stay floating, so a rule can tile every window of an app. A 'layout tiling' of your own,
  -- like the 'f' key of the service mode, still tiles them
  -- See: https://nikitabobko.github.io/AeroSpace/guide#on-window-detected-callback
  -- Fallback value (if you omit the tables): no rules
  onWindowDetected = {
    {
      match = {
        -- The rule matches the windows of the app with this bundle id. See: inlay list-apps
        -- All the conditions of 'match' that are present must hold. A condition that is omitted always holds
        appId = 'com.apple.systempreferences',

        -- The rule matches the windows whose app has a name that contains a match of the regex (case insensitive)
        appNameRegexSubstring = 'settings',

        -- The rule matches the windows whose title contains a match of the regex (case insensitive)
        windowTitleRegexSubstring = 'substring',

        -- The rule matches the windows that are detected in this workspace
        workspace = '1',

        -- true: only the windows that are already open when Inlay starts. false: only the windows detected later
        duringInlayStartup = true,
      },

      -- The name that AeroSpace gives to 'match.duringInlayStartup'. It is accepted too
      -- match.duringAerospaceStartup = true

      -- Check the rules that follow this one too, instead of stopping here
      -- Possible values: true|false
      -- Fallback value (if you omit the key): checkFurtherCallbacks = false
      checkFurtherCallbacks = false,

      -- Mandatory. The commands to run for the window: a command, or a list of commands
      run = { 'layout floating', 'move-node-to-workspace 1' },
    },

    -- 'match' can also be a command instead of conditions: the rule matches when the command succeeds.
    -- The command gets the window in the variables of 'test' and of the '--format' options. 'true' always matches
    {
      match = 'true',
      checkFurtherCallbacks = true,
      run = {},
    },

    -- A catch-all rule, as the last one: the tiling windows that no rule above matched go to a workspace, or float
    -- ('layout floating', what inlay.lua, the config that Inlay ships with, ends with: its cmd-alt-shift keys tile
    -- them again). '%{window-layout}' is 'h_tiles' or 'v_tiles' for a tiling window and 'floating' for a floating
    -- one, so the dialogs, which Inlay makes floating before the rules run, stay where they open
    {
      match = 'test %{window-layout} ~= _tiles',
      run = 'move-node-to-workspace 6',
    },
  },

  -- Force a workspace to a monitor: the name of the workspace = a monitor pattern, or a list of patterns
  -- (the first one that matches a connected monitor wins).
  -- Possible patterns:
  -- - 'main'.      The main monitor (System Settings -> Displays)
  -- - 'secondary'. The monitor that isn't the main one. It only matches with exactly two monitors
  -- - 1, 2, ...    The number of the monitor, from left to right
  -- - 'built-in' or any other regex. A case insensitive substring of the name of the monitor. See: inlay list-monitors
  -- See: https://nikitabobko.github.io/AeroSpace/guide#assign-workspaces-to-monitors
  -- Fallback value (if you omit the table): no workspace is forced to a monitor
  workspaceToMonitorForceAssignment = {
    ['1'] = 'main',
    ['6'] = { 'secondary', 'main' },
  },
}

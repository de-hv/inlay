-- Reference: https://github.com/i3/i3/blob/next/etc/config

-- A whole config of its own, like i3: not over the built-in config of Inlay
inlay.config({
  builtInConfig = false,

  -- In i3, all workspaces are phantom
  persistentWorkspaces = {},

  -- i3 doesn't have "normalizations" feature that why we disable them here.
  -- But the feature is very helpful.
  -- Normalizations eliminate all sorts of weird tree configurations that don't make sense.
  -- Give normalizations a chance and enable them back.
  enableNormalizationFlattenContainers = false,
  enableNormalizationOppositeOrientationForNestedContainers = false,
})

-- Mouse follows focus when focused monitor changes
inlay.on('monitor_changed', 'move-mouse monitor-lazy-center')

local main = {
  -- A new Terminal window, through AppleScript
  ['alt-enter'] = [[exec-and-forget osascript -e \
    'tell application "Terminal" to tell (do script) to activate' ]],

  -- i3 wraps focus by default
  ['alt-j']         = 'focus --boundaries-action wrap-around-the-workspace left',
  ['alt-k']         = 'focus --boundaries-action wrap-around-the-workspace down',
  ['alt-l']         = 'focus --boundaries-action wrap-around-the-workspace up',
  ['alt-semicolon'] = 'focus --boundaries-action wrap-around-the-workspace right',

  ['alt-shift-j']         = 'move left',
  ['alt-shift-k']         = 'move down',
  ['alt-shift-l']         = 'move up',
  ['alt-shift-semicolon'] = 'move right',

  -- Consider using 'join-with' command as a 'split' replacement if you want to enable
  -- normalizations
  ['alt-h'] = 'split horizontal',
  ['alt-v'] = 'split vertical',

  ['alt-f'] = 'fullscreen',

  -- Not supported: Inlay has no accordion layout ('layout stacking' and 'layout tabbed' in i3)
  -- ['alt-s'] = 'layout v_accordion',
  -- ['alt-w'] = 'layout h_accordion',
  ['alt-e'] = 'layout tiles horizontal vertical', -- 'layout toggle split' in i3

  ['alt-shift-space'] = 'layout floating tiling', -- 'floating toggle' in i3

  -- Not supported: the floating windows of a workspace are focused like the tiling ones
  -- ['alt-space'] = 'focus toggle_tiling_floating',

  -- `focus parent`/`focus child` are not supported
  -- ['alt-a'] = 'focus parent',

  ['alt-shift-c'] = 'reload-config',

  ['alt-r'] = 'mode resize',
}

-- alt-1 … alt-9 and alt-0 go to the workspaces 1 to 10, and alt-shift with them moves the window there
for i = 1, 10 do
  local key = tostring(i % 10)
  main['alt-' .. key]       = 'workspace ' .. i
  main['alt-shift-' .. key] = 'move-node-to-workspace ' .. i
end

for keys, command in pairs(main) do
  inlay.bind(keys, command)
end

local resize = { mode = 'resize' }
inlay.bind('h', 'resize width -50', resize)
inlay.bind('j', 'resize height +50', resize)
inlay.bind('k', 'resize height -50', resize)
inlay.bind('l', 'resize width +50', resize)
inlay.bind('enter', 'mode main', resize)
inlay.bind('esc', 'mode main', resize)

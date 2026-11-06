-- Catppuccin (Mocha)
-- https://catppuccin.com
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    active_color     = '#CBA6F7',
    inactive_color   = '#45475AB3',
    floating_color   = '#89B4FA',
    fullscreen_color = '#FAB387',
    mode_colors = { resize = '#A6E3A1', service = '#F38BA8' },
  },
  menu_bar = {
    colors = { focused = '#CBA6F7', accent = '#F5C2E7' },
  },
}

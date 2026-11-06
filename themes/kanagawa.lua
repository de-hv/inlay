-- Kanagawa
-- https://github.com/rebelot/kanagawa.nvim
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    active_color     = '#E6C384',
    inactive_color   = '#54546DB3',
    floating_color   = '#957FB8',
    fullscreen_color = '#FFA066',
    mode_colors = { resize = '#98BB6C', service = '#C34043' },
  },
  menu_bar = {
    colors = { focused = '#E6C384', accent = '#957FB8' },
  },
}

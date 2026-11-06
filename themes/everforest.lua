-- Everforest
-- https://github.com/sainnhe/everforest
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    active_color     = '#A7C080',
    inactive_color   = '#475258B3',
    floating_color   = '#D699B6',
    fullscreen_color = '#DBBC7F',
    mode_colors = { resize = '#83C092', service = '#E67E80' },
  },
  menu_bar = {
    colors = { focused = '#A7C080', accent = '#D699B6' },
  },
}

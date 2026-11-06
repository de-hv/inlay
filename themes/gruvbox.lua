-- Gruvbox (Material)
-- https://github.com/sainnhe/gruvbox-material
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    active_color     = '#D8A657',
    inactive_color   = '#504945B3',
    floating_color   = '#7DAEA3',
    fullscreen_color = '#E78A4E',
    mode_colors = { resize = '#A9B665', service = '#EA6962' },
  },
  menu_bar = {
    colors = { focused = '#D8A657', accent = '#D3869B' },
  },
}

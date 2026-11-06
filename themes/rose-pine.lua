-- Rosé Pine Dawn (light)
-- https://rosepinetheme.com
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    active_color     = '#286983',
    inactive_color   = '#9893A580',
    floating_color   = '#907AA9',
    fullscreen_color = '#EA9D34',
    mode_colors = { resize = '#56949F', service = '#B4637A' },
  },
  menu_bar = {
    colors = { focused = '#286983', accent = '#907AA9' },
  },
}

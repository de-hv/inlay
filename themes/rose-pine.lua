-- Rosé Pine Dawn (light)
-- https://rosepinetheme.com
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#286983',
    inactiveColor   = '#9893A580',
    floatingColor   = '#907AA9',
    fullscreenColor = '#EA9D34',
    modeColors = { resize = '#56949F', service = '#B4637A' },
  },
  menuBar = {
    colors = { focused = '#286983', accent = '#907AA9' },
  },
}

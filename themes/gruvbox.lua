-- Gruvbox (Material)
-- https://github.com/sainnhe/gruvbox-material
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#D8A657',
    inactiveColor   = '#504945B3',
    floatingColor   = '#7DAEA3',
    fullscreenColor = '#E78A4E',
    modeColors = { resize = '#A9B665', service = '#EA6962' },
  },
  menuBar = {
    colors = { focused = '#D8A657', accent = '#D3869B' },
  },
}

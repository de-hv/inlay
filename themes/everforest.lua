-- Everforest
-- https://github.com/sainnhe/everforest
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#A7C080',
    inactiveColor   = '#475258B3',
    floatingColor   = '#D699B6',
    fullscreenColor = '#DBBC7F',
    modeColors = { resize = '#83C092', service = '#E67E80' },
  },
  menuBar = {
    colors = { focused = '#A7C080', accent = '#D699B6' },
  },
}

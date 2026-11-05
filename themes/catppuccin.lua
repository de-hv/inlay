-- Catppuccin (Mocha)
-- https://catppuccin.com
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#CBA6F7',
    inactiveColor   = '#45475AB3',
    floatingColor   = '#89B4FA',
    fullscreenColor = '#FAB387',
    modeColors = { resize = '#A6E3A1', service = '#F38BA8' },
  },
  menuBar = {
    colors = { focused = '#CBA6F7', accent = '#F5C2E7' },
  },
}

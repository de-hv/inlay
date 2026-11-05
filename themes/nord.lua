-- Nord
-- https://www.nordtheme.com
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#88C0D0',
    inactiveColor   = '#4C566AB3',
    floatingColor   = '#B48EAD',
    fullscreenColor = '#EBCB8B',
    modeColors = { resize = '#A3BE8C', service = '#BF616A' },
  },
  menuBar = {
    colors = { focused = '#88C0D0', accent = '#B48EAD' },
  },
}

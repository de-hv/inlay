-- Tokyo Night
-- https://github.com/folke/tokyonight.nvim
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#7AA2F7',
    inactiveColor   = '#414868B3',
    floatingColor   = '#BB9AF7',
    fullscreenColor = '#FF9E64',
    modeColors = { resize = '#9ECE6A', service = '#F7768E' },
  },
  menuBar = {
    colors = { focused = '#7AA2F7', accent = '#BB9AF7' },
  },
}

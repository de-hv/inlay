-- Kanagawa
-- https://github.com/rebelot/kanagawa.nvim
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    activeColor     = '#E6C384',
    inactiveColor   = '#54546DB3',
    floatingColor   = '#957FB8',
    fullscreenColor = '#FFA066',
    modeColors = { resize = '#98BB6C', service = '#C34043' },
  },
  menuBar = {
    colors = { focused = '#E6C384', accent = '#957FB8' },
  },
}

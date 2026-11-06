-- Nord
-- https://www.nordtheme.com
-- From the palette of the Omarchy theme of the same name (colors.toml)
--
-- A theme only has colors: the borders, and the focused workspace of the menu bar (also in a binding
-- mode). The other colors of the menu bar stay 'auto': they follow the menu bar over any wallpaper
return {
  borders = {
    active_color     = '#88C0D0',
    inactive_color   = '#4C566AB3',
    floating_color   = '#B48EAD',
    fullscreen_color = '#EBCB8B',
    mode_colors = { resize = '#A3BE8C', service = '#BF616A' },
  },
  menu_bar = {
    colors = { focused = '#88C0D0', accent = '#B48EAD' },
  },
}

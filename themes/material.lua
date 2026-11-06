-- Material
-- Material You from #6750A4, dark. The theme of a config without the key 'theme'
--
-- The menu bar item is drawn like the other icons of the menu bar (system_colors): its colors below apply
-- when a config sets system_colors = false
return {
  borders = {
    active_color   = '#B59DF7',
    inactive_color = '#999D9F',
    floating_color = '#EFB8C8',
  },
  menu_bar = {
    system_colors = true,
    colors = { focused = '#B59DF7', occupied = '#CAC4D0', empty = '#938F99', accent = '#EFB8C8' },
  },
}

-- Material
-- Material You from #6750A4, dark. The theme of a config without the key 'theme'
--
-- The menu bar item is drawn like the other icons of the menu bar (systemColors): its colors below apply
-- when a config sets systemColors = false
return {
  borders = {
    activeColor   = '#B59DF7',
    inactiveColor = '#999D9F',
    floatingColor = '#EFB8C8',
  },
  menuBar = {
    systemColors = true,
    colors = { focused = '#B59DF7', occupied = '#CAC4D0', empty = '#938F99', accent = '#EFB8C8' },
  },
}

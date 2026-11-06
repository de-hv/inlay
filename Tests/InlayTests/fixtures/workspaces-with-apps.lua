-- A config of a user over the built-in config: the 7 workspaces, with apps. See: StartupRulesTest
inlay.workspace({ id = '1', name = 'Terminals', key = 'h', apps = { 'com.mitchellh.ghostty' } })
inlay.workspace({ id = '2', name = 'Code',      key = 'j', apps = { 'dev.zed.Zed', 'com.microsoft.VSCode' } })
inlay.workspace({ id = '3', name = 'Browsers',  key = 'k', apps = { 'com.google.Chrome', 'app.zen-browser.zen' } })
inlay.workspace({ id = '4', name = 'Chats',     key = 'l', apps = {
  'com.tinyspeck.slackmacgap', 'com.microsoft.teams2', 'ru.keepcoder.Telegram', 'net.whatsapp.WhatsApp',
} })
inlay.workspace({ id = '5', name = 'AI',        key = 'u', apps = { 'com.anthropic.claudefordesktop' } })
inlay.workspace({ id = '6', name = 'Other',     key = 'i', monitor = { 'secondary', 'main' } })
inlay.workspace({ id = '7', name = 'Free',      key = 'o' })

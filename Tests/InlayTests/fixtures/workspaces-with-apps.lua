-- A config of a user over the built-in config: the 7 workspaces, with apps. See: StartupRulesTest
return {
  workspaces = {
    { id = '1', name = 'Terminals', key = 'h', apps = { 'com.mitchellh.ghostty' } },
    { id = '2', name = 'Code',      key = 'j', apps = { 'dev.zed.Zed', 'com.microsoft.VSCode' } },
    { id = '3', name = 'Browsers',  key = 'k', apps = { 'com.google.Chrome', 'app.zen-browser.zen' } },
    { id = '4', name = 'Chats',     key = 'l', apps = {
      'com.tinyspeck.slackmacgap', 'com.microsoft.teams2', 'ru.keepcoder.Telegram', 'net.whatsapp.WhatsApp',
    } },
    { id = '5', name = 'AI',        key = 'u', apps = { 'com.anthropic.claudefordesktop' } },
    { id = '6', name = 'Other',     key = 'i', monitor = { 'secondary', 'main' } },
    { id = '7', name = 'Free',      key = 'o' },
  },
}

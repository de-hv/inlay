enum KnownBundleId: String, Equatable {

    case _1password = "com.1password.1password"
    case activityMonitor = "com.apple.ActivityMonitor"
    case alacritty = "org.alacritty"
    case braveBrowser = "com.brave.Browser"
    case chrome = "com.google.Chrome"
    case cleanshotx = "pl.maketheweb.cleanshotx"
    case codex = "com.openai.codex"
    case emacs = "org.gnu.Emacs"
    case finder = "com.apple.finder"
    case ghostty = "com.mitchellh.ghostty"
    case gimp = "org.gimp.gimp-2.10"
    case iphonesimulator = "com.apple.iphonesimulator"
    case iterm2 = "com.googlecode.iterm2"
    case kitty = "net.kovidgoyal.kitty"
    case outlook = "com.microsoft.Outlook"
    case photoBooth = "com.apple.PhotoBooth"
    case qutebrowser = "org.qutebrowser.qutebrowser"
    case screenstudio = "com.timpler.screenstudio"
    case slack = "com.tinyspeck.slackmacgap"
    case steam = "com.valvesoftware.steam.helper"
    case wezterm = "com.github.wez.wezterm"
    case wisprFlow = "com.electron.wispr-flow"
    case xcode = "com.apple.dt.Xcode"
    case zenBrowser = "app.zen-browser.zen"
    case zoom = "us.zoom.xos"

    case mozillaFirefox = "org.mozilla.firefox"
    case mozillaFirefoxDeveloperEdition = "org.mozilla.firefoxdeveloperedition"
    case mozillaFirefoxNightly = "org.mozilla.nightly"

    // Browsers on Chromium. Their Picture in Picture window is always on top
    case ardia = "com.ardia.browser"
    case arc = "company.thebrowser.Browser"
    case dia = "company.thebrowser.dia"
    case braveBrowserBeta = "com.brave.Browser.beta"
    case braveBrowserNightly = "com.brave.Browser.nightly"
    case chromeBeta = "com.google.Chrome.beta"
    case chromeDev = "com.google.Chrome.dev"
    case chromeCanary = "com.google.Chrome.canary"
    case chromium = "org.chromium.Chromium"
    case comet = "ai.perplexity.comet"
    case edge = "com.microsoft.edgemac"
    case edgeBeta = "com.microsoft.edgemac.Beta"
    case edgeDev = "com.microsoft.edgemac.Dev"
    case edgeCanary = "com.microsoft.edgemac.Canary"
    case helium = "net.imput.helium"
    case opera = "com.operasoftware.Opera"
    case operaGX = "com.operasoftware.OperaGX"
    case vivaldi = "com.vivaldi.Vivaldi"
    case yandex = "ru.yandex.desktop.yandex-browser"

    // Browsers on Firefox (Gecko)
    case floorp = "one.ablaze.floorp"
    case librewolf = "org.mozilla.librewolf"
    case mullvadBrowser = "net.mullvad.mullvadbrowser"
    case torBrowser = "org.torproject.torbrowser"
    case waterfox = "net.waterfox.waterfox"

    case vscode = "com.microsoft.VSCode"
    case vscodium = "com.vscodium"

    var isFirefox: Bool {
        self == .mozillaFirefox
            || self == .mozillaFirefoxDeveloperEdition
            || self == .mozillaFirefoxNightly
            || self == .zenBrowser
            || self == .floorp
            || self == .librewolf
            || self == .mullvadBrowser
            || self == .torBrowser
            || self == .waterfox
    }

    var isChromium: Bool {
        switch self {
            case .chrome, .chromeBeta, .chromeDev, .chromeCanary, .chromium,
                 .braveBrowser, .braveBrowserBeta, .braveBrowserNightly,
                 .edge, .edgeBeta, .edgeDev, .edgeCanary,
                 .ardia, .arc, .dia, .comet, .helium, .opera, .operaGX, .vivaldi, .yandex:
                true
            default: false
        }
    }

    /// A browser whose Picture in Picture window is always on top: Inlay leaves it alone
    var isBrowser: Bool { isChromium || isFirefox }

    var isVscode: Bool {
        self == .vscode || self == .vscodium
    }
}

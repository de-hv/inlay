import AppKit
import Common
import ServiceManagement

@MainActor
func syncStartAtLogin() {
    let service = SMAppService.mainApp
    switch true {
        case !config.startAtLogin: _ = try? service.unregister()
        case isDebug: print("'start_at_login = true' has no effect in debug builds")
        default: _ = try? service.register()
    }
}

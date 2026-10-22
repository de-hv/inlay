import Foundation

/// The state of the server that isn't a part of the tree or the config
@MainActor
final class ServerState {
    static let shared = ServerState()

    private init() {}

    /// Is "layouting" enabled. See: EnableCommand
    var isEnabled: Bool = true
    var axPermissionStatus: AxPermissionStatus = .waitingWithPrompt {
        didSet { if oldValue != axPermissionStatus { publishUiState() } }
    }
    /// The last attempt to load the config. nil until the first one
    var lastConfigLoad: ConfigLoadStatus? = nil
}

enum AxPermissionStatus: Equatable {
    case granted
    case waiting
    case waitingWithPrompt
}

struct ConfigLoadStatus: Equatable, Sendable {
    var date: Date
    var url: URL
    var errorCount: Int
    var warningCount: Int
    /// false if the errors were too severe to apply the config. The previous config stays in effect then
    var isApplied: Bool
    /// The errors, then the warnings, as the window of the diagnostics shows them
    var problems: [String] = []
}

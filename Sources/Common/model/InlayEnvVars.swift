public let INLAY_WINDOW_ID = "INLAY_WINDOW_ID"
public let INLAY_WORKSPACE = "INLAY_WORKSPACE"
public let INLAY_FOCUSED_WORKSPACE = "INLAY_FOCUSED_WORKSPACE"
public let INLAY_PREV_WORKSPACE = "INLAY_PREV_WORKSPACE"

/// Inlay is a fork of AeroSpace. Processes that Inlay starts (exec-on-workspace-change, exec-and-forget) also get
/// the variables under their AeroSpace names, so that scripts written for AeroSpace keep working after a migration.
/// The 'inlay' CLI itself only reads INLAY_* variables.
public let legacyEnvVarAliases: [String: String] = [
    INLAY_WINDOW_ID: "AEROSPACE_WINDOW_ID",
    INLAY_WORKSPACE: "AEROSPACE_WORKSPACE",
    INLAY_FOCUSED_WORKSPACE: "AEROSPACE_FOCUSED_WORKSPACE",
    INLAY_PREV_WORKSPACE: "AEROSPACE_PREV_WORKSPACE",
]

extension [String: String] {
    /// Adds (or clears) the AEROSPACE_* alias of every INLAY_* variable
    public func withLegacyEnvVarAliases() -> [String: String] {
        var result = self
        for (name, alias) in legacyEnvVarAliases {
            result[alias] = self[name]
        }
        return result
    }
}

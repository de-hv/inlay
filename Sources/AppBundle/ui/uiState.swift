/// The single place where the UI learns that the model has changed.
///
/// It's called on the main thread:
/// - at the end of every refresh session (after the windows are laid out)
/// - when the binding mode, the enabled state, the config or the accessibility permission change outside of a session
///
/// Every consumer derives its own Equatable snapshot from the model and redraws only if the snapshot has changed,
/// so it's cheap to call it more often than needed. Never poll the model, add a consumer here instead
@MainActor
func publishUiState() {
    DebugStats.count("ui.publish")
    MenuBarStore.shared.refresh()
    BordersController.shared.refresh()
    SettingsWindowController.shared.modelDidChange()
}

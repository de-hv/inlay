import AppKit
import Common

// Placement of new tiling windows inspired by the dwindle layout of Hyprland:
// the new window splits the most recent tiling window in two.
//
// Hyprland keeps a binary tree. The tree of Inlay is the tree of AeroSpace: containers may have more than
// two children, and the normalizations don't allow a container to have the same orientation as its parent.
// That's why the split doesn't always create a container: if the container of the split window already has the
// required orientation, the new window becomes its next sibling. The result on the screen is the same.

/// Decides where a new tiling window goes when `new-window-placement = 'dwindle'`, and prepares the tree for it:
/// the caller only has to bind the new window with the returned data.
///
/// 1. Target. The focused window, if it's a tiling window of the workspace.
///    Otherwise, the most recent tiling window of the workspace
/// 2. Axis. Target wider than tall -> horizontal split (side by side). Otherwise, including a square -> vertical split
/// 3. Placement. It depends on the container of the target:
///    a. The same orientation as the axis -> the new window becomes the next sibling of the target.
///       They share the weight of the target. The other siblings keep their sizes
///    b. The target is the only child of the root container -> the root container changes its orientation. Then (a)
///    c. The opposite orientation -> a new container with the orientation of the axis takes the place and
///       the weight of the target. The target and the new window go inside
///
/// The new window is always the right/bottom one. The target keeps `split-ratio` of its space.
///
/// nil if the workspace has no tiling windows. The new window must go to the root container then
///
/// - Parameter focused: The focused window. The caller passes it, because `focus` falls back to an arbitrary window
///   of the workspace while the focused window is unbound, and the new window may be the focused one (floating -> tiling)
@MainActor
func prepareDwindleBindingDataForNewTilingWindow(_ workspace: Workspace, focused: Window?) -> BindingData? {
    // The decision is made on the tree that the user sees. Example: a window is closed and another one is opened in
    // the same refresh session. The container of the closed window isn't flattened yet
    workspace.normalizeContainers()
    // The most recent window isn't necessarily the focused one. Example: flatten-workspace-tree rebinds all the windows
    let focused = focused?.takeIf { $0.parent is TilingContainer && $0.nodeWorkspace == workspace }
    guard let target = focused ?? workspace.rootTilingContainer.mostRecentWindowRecursive,
          let parent = target.parent as? TilingContainer,
          // Also normalizes the weights. From this point, the weights are in screen points
          let targetRect = target.predictLayoutRect() else { return nil }
    let axis: Orientation = targetRect.width > targetRect.height ? .h : .v
    let ratio = config.tiling.splitRatio

    if parent.orientation != axis && parent.isRootContainer && parent.children.count == 1 { // Case b
        parent.changeOrientation(axis)
        target.setWeight(axis, targetRect.getDimension(axis))
    }
    if parent.orientation == axis { // Case a
        let weight = target.getWeight(axis)
        target.setWeight(axis, weight * ratio)
        return BindingData(parent: parent, adaptiveWeight: weight * (1 - ratio), index: target.ownIndex.orDie() + 1)
    } else { // Case c
        let targetBinding = target.unbindFromParent()
        let container = TilingContainer(parent: parent, adaptiveWeight: targetBinding.adaptiveWeight, axis, .tiles, index: targetBinding.index)
        let size = targetRect.getDimension(axis) // The container takes the place of the target
        target.bind(to: container, adaptiveWeight: size * ratio, index: 0)
        return BindingData(parent: container, adaptiveWeight: size * (1 - ratio), index: 1)
    }
}

extension TreeNode {
    /// Call it right before the node leaves the tiling tree: the window is closed, becomes floating, is moved to
    /// a different workspace, is minimized, etc.
    ///
    /// With `new-window-placement = 'dwindle'`, the space of the node goes to its previous sibling (to the next one,
    /// if the node is the first child), as if the split that created the node was undone.
    /// Without it, all the siblings share the space (AeroSpace behavior).
    ///
    /// Nothing to do for a node with a single sibling: the sibling takes all the space, and the container gets flattened
    @MainActor
    func releaseTilingSpaceToNeighbor() {
        guard config.tiling.newWindowPlacement == .dwindle else { return }
        guard let parent = parent as? TilingContainer, parent.children.count >= 3, let ownIndex else { return }
        // Normalizes the weights. From this point, the weights are in screen points
        guard predictLayoutRect() != nil else { return }
        let neighbor = parent.children[ownIndex > 0 ? ownIndex - 1 : 1]
        let orientation = parent.orientation
        neighbor.setWeight(orientation, neighbor.getWeight(orientation) + getWeight(orientation))
    }
}

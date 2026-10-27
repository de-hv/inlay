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
/// 1. Target. With `split-target = 'cursor'`, the tiling window of the workspace under the mouse cursor, if there is one.
///    Otherwise, the focused window, if it's a tiling window of the workspace.
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
    let underCursor = config.tiling.splitTarget == .cursor ? workspace.tilingWindow(at: cursorLocation()) : nil
    guard let target = underCursor ?? focused ?? workspace.rootTilingContainer.mostRecentWindowRecursive,
          target.parent is TilingContainer,
          // Also normalizes the weights. From this point, the weights are in screen points
          let targetRect = target.predictLayoutRect() else { return nil }
    let axis: Orientation = targetRect.width > targetRect.height ? .h : .v
    return target.splitTilingPlace(axis, newShare: 1 - config.tiling.splitRatio, newIsAfter: true, rect: targetRect)
}

extension Workspace {
    /// The tiling window that the layout puts under the point of the screen.
    ///
    /// nil if the point is in a gap, over another monitor, or if nothing of the tree is there to be seen:
    /// the workspace isn't the visible one of its monitor, or a fullscreen window covers the tiling windows.
    /// The floating windows aren't taken into account, not even one that covers the point
    @MainActor
    func tilingWindow(at point: CGPoint) -> Window? {
        guard isVisible, rootTilingContainer.mostRecentWindowRecursive?.isFullscreen != true else { return nil }
        return rootTilingContainer.allLeafWindowsRecursive.first { $0.predictLayoutRect()?.contains(point) == true }
    }
}

extension TreeNode {
    /// Splits the place of the node in the tiling tree in two along `axis`, and tells where to bind the node that
    /// takes the new part. The node keeps the rest. The cases are the ones of
    /// ``prepareDwindleBindingDataForNewTilingWindow(_:focused:)``, plus one for containers:
    ///
    /// a. The container of the node has the orientation of the axis -> the new node becomes a sibling of the node
    /// b. The node is a window, and the only child of the root container -> the root container changes its orientation. Then (a)
    /// c. Otherwise -> a new container with the orientation of the axis takes the place and the weight of the node.
    ///    The node and the new node go inside
    /// d. The node is a container with the orientation of the axis, and its parent has another one ->
    ///    the new node becomes its first or its last child. Wrapping it (c) would nest two containers of the same orientation
    ///
    /// - Parameter newShare: the fraction of the place that the new node takes
    /// - Parameter newIsAfter: the new node goes to the right/bottom of the node. Otherwise, to the left/top
    /// - Parameter rect: `predictLayoutRect()` of the node, which also normalizes the weights that are changed here
    @MainActor
    func splitTilingPlace(_ axis: Orientation, newShare: CGFloat, newIsAfter: Bool, rect: Rect) -> BindingData {
        let size = rect.getDimension(axis)
        if let parent = parent as? TilingContainer {
            if self is Window && parent.orientation != axis && parent.isRootContainer && parent.children.count == 1 { // Case b
                parent.changeOrientation(axis)
                setWeight(axis, size)
            }
            if parent.orientation == axis { // Case a
                let weight = getWeight(axis)
                setWeight(axis, weight * (1 - newShare))
                return BindingData(parent: parent, adaptiveWeight: weight * newShare, index: ownIndex.orDie() + (newIsAfter ? 1 : 0))
            }
        }
        if let container = self as? TilingContainer, container.orientation == axis { // Case d
            _ = children.first?.predictLayoutRect() // Normalizes the weights of the children
            for child in children {
                child.setWeight(axis, child.getWeight(axis) * (1 - newShare))
            }
            return BindingData(parent: container, adaptiveWeight: size * newShare, index: newIsAfter ? INDEX_BIND_LAST : 0)
        }
        // Case c
        let binding = unbindFromParent()
        let container = TilingContainer(parent: binding.parent, adaptiveWeight: binding.adaptiveWeight, axis, .tiles, index: binding.index)
        bind(to: container, adaptiveWeight: size * (1 - newShare), index: 0)
        return BindingData(parent: container, adaptiveWeight: size * newShare, index: newIsAfter ? 1 : 0)
    }

    /// The sibling that gets the space of the node when the node leaves the tiling tree:
    /// the previous one, or the next one if the node is the first child. nil for an only child
    var siblingThatTakesTheSpace: TreeNode? {
        guard let parent = parent as? TilingContainer, parent.children.count >= 2, let ownIndex else { return nil }
        return parent.children[ownIndex > 0 ? ownIndex - 1 : 1]
    }

    /// Call it right before the node leaves the tiling tree: the window is closed, becomes floating, is moved to
    /// a different workspace, is minimized, etc.
    ///
    /// With `new-window-placement = 'dwindle'`, the space of the node goes to its previous sibling (to the next one,
    /// if the node is the first child), as if the split that created the node was undone.
    /// Without it, all the siblings share the space (AeroSpace behavior).
    ///
    /// Nothing to do for a node with a single sibling: the sibling takes all the space, and the container gets flattened.
    /// An only child takes its container with it (an empty container is removed), so it's the container that releases its space
    ///
    /// - Parameter temporarily: the node comes back to its place later (minimized, macOS native fullscreen, hidden app).
    ///   Otherwise, two windows left alone in the workspace are put side by side again. See: Workspace.orientTwoWindowsLikeDwindle
    @MainActor
    func releaseTilingSpaceToNeighbor(temporarily: Bool = false) {
        guard config.tiling.newWindowPlacement == .dwindle else { return }
        guard let parent = parent as? TilingContainer else { return }
        if !temporarily { nodeWorkspace?.lostTilingNode = true }
        if parent.children.count == 1 && !parent.isRootContainer { return parent.releaseTilingSpaceToNeighbor(temporarily: temporarily) }
        guard parent.children.count >= 3, let neighbor = siblingThatTakesTheSpace else { return }
        // Normalizes the weights. From this point, the weights are in screen points
        guard predictLayoutRect() != nil else { return }
        let orientation = parent.orientation
        neighbor.setWeight(orientation, neighbor.getWeight(orientation) + getWeight(orientation))
    }
}

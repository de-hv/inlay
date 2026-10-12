import AppKit
import Common

/// The place of a window in the tiling tree, remembered when macOS takes the window out of it: the window is
/// minimized, goes to the macOS native fullscreen, or its app is hidden. When the window comes back, it gets
/// the place back, as long as the place still makes sense. See: normalizeLayoutReason
final class TilingSlot {
    /// The workspace of the tree
    private let workspaceName: String
    /// The container of the node. It's gone if the node had a single sibling: the container was flattened
    private weak var parent: TilingContainer?
    private let index: Int
    /// The orientation of `parent`
    private let orientation: Orientation
    /// The weight of the node, in screen points
    private let weight: CGFloat
    /// The sibling that took the space of the node. See: TreeNode.siblingThatTakesTheSpace
    private weak var neighbor: TreeNode?
    private let isBeforeNeighbor: Bool
    /// The fraction of the space of the node and its neighbor together that the node had
    private let share: CGFloat
    private weak var nextSibling: TreeNode?
    /// The place of `parent`, if the node was its only child: the container goes away with the node, and
    /// its place is all that is left of the place of the node. Example: both windows of a container leave at once
    private let outer: TilingSlot?

    /// nil if the node isn't a part of the tiling tree of a workspace
    @MainActor
    init?(of node: TreeNode) {
        guard let parent = node.parent as? TilingContainer, let workspace = node.nodeWorkspace, let index = node.ownIndex,
              // Normalizes the weights. From this point, the weights are in screen points
              node.predictLayoutRect() != nil else { return nil }
        let orientation = parent.orientation
        let weight = node.getWeight(orientation)
        let neighbor = node.siblingThatTakesTheSpace
        workspaceName = workspace.name
        self.parent = parent
        self.index = index
        self.orientation = orientation
        self.weight = weight
        self.neighbor = neighbor
        isBeforeNeighbor = index == 0
        share = neighbor.map { weight / (weight + $0.getWeight(orientation)) } ?? 1
        nextSibling = parent.children.getOrNil(atIndex: index + 1)
        outer = parent.children.count == 1 && !parent.isRootContainer ? TilingSlot(of: parent) : nil
    }

    /// Makes room for the window where it was, and tells where to bind it.
    ///
    /// - The container is still there: the window goes back to its index, next to the neighbor that took its space,
    ///   and takes the space back
    /// - The container is gone, but the neighbor is still in the tree: the place of the neighbor is split again,
    ///   the way it was split before
    /// - The window was alone in its container: the same, with the place that the container had
    /// - Otherwise, or if the workspace is another one: nil. The window must be placed like a new window
    ///
    /// The window must be unbound, and it must be bound with the returned data right away
    @MainActor
    func bindingData(in workspace: Workspace) -> BindingData? {
        guard workspace.name == workspaceName else { return nil }
        // The container of a window with a single sibling is still there until the tree is normalized
        workspace.normalizeContainers()
        let root = workspace.rootTilingContainer
        func isInTree(_ node: TreeNode) -> Bool { node.parentsWithSelf.contains(root) }
        if let parent, isInTree(parent) {
            return bindingData(in: parent)
        }
        if let neighbor, isInTree(neighbor), let rect = neighbor.predictLayoutRect() {
            return neighbor.splitTilingPlace(orientation, newShare: share, newIsAfter: !isBeforeNeighbor, rect: rect)
        }
        return outer?.bindingData(in: workspace)
    }

    @MainActor
    private func bindingData(in parent: TilingContainer) -> BindingData {
        let axis = parent.orientation
        _ = parent.children.first?.predictLayoutRect() // Normalizes the weights of the children
        guard let neighbor, neighbor.parent === parent, let neighborIndex = neighbor.ownIndex else {
            // The neighbor is gone. The sibling on the other side still tells where the node was
            let index = nextSibling?.takeIf { $0.parent === parent }?.ownIndex ?? min(index, parent.children.count)
            return BindingData(parent: parent, adaptiveWeight: weightTakenFromAllSiblings(of: parent), index: index)
        }
        let index = neighborIndex + (isBeforeNeighbor ? 0 : 1)
        // after-focused: all the siblings shared the space of the node. They give it back
        guard config.tiling.newWindowPlacement == .dwindle else {
            return BindingData(parent: parent, adaptiveWeight: weightTakenFromAllSiblings(of: parent), index: index)
        }
        // dwindle: the neighbor took the space. If it is still big enough (and the container wasn't turned around),
        // it gives back the very same points. Otherwise, the same fraction
        let neighborWeight = neighbor.getWeight(axis)
        let taken = axis == orientation && weight < neighborWeight ? weight : neighborWeight * share
        neighbor.setWeight(axis, neighborWeight - taken)
        return BindingData(parent: parent, adaptiveWeight: taken, index: index)
    }

    /// The layout takes the excess of weight from all the children of a container in equal parts. This is the weight
    /// that leaves the node with the weight it had after that
    @MainActor
    private func weightTakenFromAllSiblings(of parent: TilingContainer) -> CGFloat {
        let siblings = CGFloat(parent.children.count)
        return siblings > 0 && parent.orientation == orientation ? weight * (siblings + 1) / siblings : WEIGHT_AUTO
    }
}

extension Window {
    /// Call it right before the window leaves its place because macOS made it fullscreen or minimized it, or
    /// because its app was hidden. It remembers the workspace of the window and, for a tiling window, its place in the tree
    @MainActor
    func rememberPlace() {
        switch parent?.kind {
            case .tilingContainer:
                tilingSlot = TilingSlot(of: self)
                workspaceBeforeMinimize = nodeWorkspace?.name
            case .floatingWindowsContainer:
                tilingSlot = nil
                workspaceBeforeMinimize = nodeWorkspace?.name
            case .macosFullscreenWindowsContainer, .macosMinimizedWindowsContainer, .macosHiddenAppsWindowsContainer:
                // macos-native-fullscreen and macos-native-minimize have moved the window already, and remembered its place
                break
            case .macosPopupWindowsContainer, .workspace, nil:
                tilingSlot = nil
                workspaceBeforeMinimize = nil
        }
    }

    /// The remembered place, which is forgotten: it's only good for one comeback
    func takeTilingSlot() -> TilingSlot? {
        defer { tilingSlot = nil }
        return tilingSlot
    }

    /// The workspace to go back to after the window was minimized, which is forgotten like the place.
    /// nil if it isn't known, or if the workspace doesn't exist anymore: it had no other window, and it isn't a persistent one
    @MainActor
    func takeWorkspaceBeforeMinimize() -> Workspace? {
        defer { workspaceBeforeMinimize = nil }
        return Workspace.all.first { $0.name == workspaceBeforeMinimize }
    }
}

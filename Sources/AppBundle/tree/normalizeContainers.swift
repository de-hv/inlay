import Common

extension Workspace {
    @MainActor func normalizeContainers() {
        rootTilingContainer.unbindEmptyAndAutoFlatten() // Beware! rootTilingContainer may change after this line of code
        if config.enableNormalizationOppositeOrientationForNestedContainers {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainers()
        }
        orientTwoWindowsLikeDwindle()
    }

    /// With dwindle, a window that leaves takes its split with it, but not the splits it made. Example: A | (B / C).
    /// A goes away, and B / C becomes the root container: two windows one above the other on a wide screen.
    /// Two windows left alone in the workspace get the axis that dwindle gives to a second window: side by side on
    /// a wide screen. Each one keeps its share. The tree of three or more windows is left alone, and so are two
    /// windows that no window left (`layout v_tiles`, `join-with`...)
    @MainActor private func orientTwoWindowsLikeDwindle() {
        // The node is unbound right after it releases its space, before any normalization
        guard lostTilingNode else { return }
        lostTilingNode = false
        let root = rootTilingContainer
        guard root.children.count == 2, root.children.allSatisfy({ $0 is Window }) else { return }
        let area = tilingArea
        let axis: Orientation = area.width > area.height ? .h : .v
        guard root.orientation != axis else { return }
        _ = root.children.first?.predictLayoutRect() // Normalizes the weights of the children
        let weights = root.children.map { $0.getWeight(root.orientation) }
        let total = weights.reduce(0, +)
        root.changeOrientation(axis)
        // The layout spreads the difference with the new size in equal parts. The shares are kept with points of the new axis
        for (child, weight) in zip(root.children, weights) {
            child.setWeight(axis, total > 0 ? weight / total * area.getDimension(axis) : 1)
        }
    }
}

extension TilingContainer {
    @MainActor fileprivate func unbindEmptyAndAutoFlatten() {
        if let child = children.singleOrNil(), config.enableNormalizationFlattenContainers && (child is TilingContainer || !isRootContainer) {
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent()
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else {
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndAutoFlatten()
            }
            if children.isEmpty && !isRootContainer {
                unbindFromParent()
            }
        }
    }
}

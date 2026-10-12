import AppKit
import Common

// 'tiling.min-window-size' config option. It limits how far the resize command and the mouse shrink a tiling window.
// It isn't a promise of the layout: when the windows of a workspace don't fit with that size (many windows, a small
// monitor, a window that was split again and again), they get less, down to the floor of the layout. See: normalizedWeights

/// Takes `amount` from the weights in equal parts, without leaving any of them under its minimum: a weight that
/// can't give its part gives what it has over its minimum, and the rest of the weights share what is left to take.
/// A weight that already is at its minimum or under it is left alone.
///
/// Returns the new weights. Their sum goes down by `amount`, or by less if there wasn't that much to take
func shrinkWeights(_ weights: [CGFloat], by amount: CGFloat, minimums: [CGFloat]) -> [CGFloat] {
    var result = weights
    var left = amount
    var free = weights.indices.filter { weights[$0] > minimums[$0] }
    while left > 0 && !free.isEmpty {
        let part = left / CGFloat(free.count)
        let exhausted = free.filter { result[$0] - minimums[$0] <= part }
        if exhausted.isEmpty {
            for index in free { result[index] -= part }
            break
        }
        for index in exhausted {
            left -= result[index] - minimums[index]
            result[index] = minimums[index]
        }
        free.removeAll(where: exhausted.contains)
    }
    return result
}

extension TreeNode {
    /// The smallest weight that resizing leaves to the node, along the orientation of its container:
    /// 'tiling.min-window-size', plus the part of the inner gap that the layout takes from the weight of the node.
    /// 0 for a node that isn't a child of a tiling container.
    ///
    /// It only makes sense for weights in screen points. They are after a layout pass, and after `predictLayoutRect()`
    @MainActor
    var minimumResizeWeight: CGFloat {
        guard let parent = parent as? TilingContainer, let ownIndex else { return 0 }
        let orientation = parent.orientation
        let rawGap = nodeWorkspace.map { ResolvedGaps(gaps: config.gaps, monitor: $0.workspaceMonitor).inner.get(orientation) } ?? 0
        let gap = CGFloat(max(rawGap, 0))
        // The same gaps as in tileChildren
        let isFirst = ownIndex == 0
        let isLast = ownIndex == parent.children.count - 1
        return config.tiling.minWindowSize + gap - (isFirst ? gap / 2 : 0) - (isLast ? gap / 2 : 0)
    }
}

import AppKit
import Common

// 'focus left|down|up|right' goes to the window that is next to the focused one on the screen.
//
// AeroSpace goes up the tree instead, to the closest container with a node in that direction, and then down that node
// to its most recent window. With nested splits that window may be nowhere near the focused one. Example (dwindle):
//
//     horizontal
//         vertical
//             A
//             horizontal [C, D]
//         vertical
//             B <-- focused
//             horizontal [E, F]
//
// 'focus left' from B went to D if D was the last one focused of the left column, although A is the one next to B

extension Window {
    /// The tiling window next to this one in `direction`, as the tiles are on the screen: of the windows on that side
    /// whose span across the direction overlaps the one of this window, the closest. When several of them touch this
    /// window (the two halves of a split below it), the most recent one, so that going back and forth returns to the
    /// same window.
    ///
    /// nil if this window is at the edge of the workspace in `direction`, or isn't a tiling window
    @MainActor
    func tilingNeighbor(in direction: CardinalDirection) -> Window? {
        guard let workspace = nodeWorkspace, parent is TilingContainer else { return nil }
        let tiles = workspace.rootTilingContainer.mruTiles(in: workspace.tilingArea)
        guard let own = tiles.first(where: { $0.window == self })?.rect else { return nil }
        let epsilon: CGFloat = 0.01
        var best: (window: Window, distance: CGFloat)? = nil
        for (window, rect) in tiles where window != self {
            let distance = rect.distance(from: own, in: direction)
            guard distance > -epsilon, rect.overlap(with: own, across: direction) > epsilon else { continue }
            // The tiles are in MRU order: a tie keeps the most recent window
            if best.map({ distance < $0.distance - epsilon }) ?? true { best = (window, distance) }
        }
        return best?.window
    }
}

extension TilingContainer {
    /// The windows of the container with the rects that the layout gives them inside `rect`, without the gaps, most
    /// recent first (the most recent child of every container goes first). Unlike the layout pass, the weights are
    /// left as they are: the floating windows that 'focus' binds for a moment have a weight of 1, and normalizing it
    /// would shrink their neighbors
    @MainActor
    fileprivate func mruTiles(in rect: Rect) -> [(window: Window, rect: Rect)] {
        let weights = children.map { max($0.getWeight(orientation), 0) }
        let total = weights.reduce(0, +)
        let size = rect.getDimension(orientation)
        var offset: CGFloat = 0
        var childRects: [ObjectIdentifier: Rect] = [:]
        for (child, weight) in zip(children, weights) {
            let share = total > 0 ? size * weight / total : size / CGFloat(children.count)
            childRects[ObjectIdentifier(child)] = orientation == .h
                ? Rect(topLeftX: rect.minX + offset, topLeftY: rect.minY, width: share, height: rect.height)
                : Rect(topLeftX: rect.minX, topLeftY: rect.minY + offset, width: rect.width, height: share)
            offset += share
        }
        let mru = Array(mruChildren)
        let ordered = mru + children.filter { child in !mru.contains(child) }
        return ordered.flatMap { (child: TreeNode) -> [(window: Window, rect: Rect)] in
            guard let childRect = childRects[ObjectIdentifier(child)] else { return [] }
            return switch child.nodeCases {
                case .window(let window): [(window, childRect)]
                case .tilingContainer(let container): container.mruTiles(in: childRect)
                default: []
            }
        }
    }
}

extension Rect {
    /// How far this rect is from `other` in `direction`: 0 if it touches it on that side, negative if it isn't
    /// on that side
    fileprivate func distance(from other: Rect, in direction: CardinalDirection) -> CGFloat {
        switch direction {
            case .left: other.minX - maxX
            case .right: minX - other.maxX
            case .up: other.minY - maxY
            case .down: minY - other.maxY
        }
    }

    /// The length of the overlap of the two rects across `direction`: vertical for left and right, horizontal for
    /// up and down. 0 or less if they don't face each other
    fileprivate func overlap(with other: Rect, across direction: CardinalDirection) -> CGFloat {
        direction.orientation == .h
            ? min(maxY, other.maxY) - max(minY, other.minY)
            : min(maxX, other.maxX) - max(minX, other.minX)
    }
}

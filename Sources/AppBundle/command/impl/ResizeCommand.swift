import AppKit
import Common

struct ResizeCommand: Command {
    let args: ResizeCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }

        let candidates = target.windowOrNil?.parentsWithSelf
            .filter { ($0.parent as? TilingContainer)?.layout == .tiles }
            ?? []

        let orientation: Orientation?
        let parent: TilingContainer?
        let node: TreeNode?
        switch args.dimension.val {
            case .width:
                orientation = .h
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .height:
                orientation = .v
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
            case .smart:
                node = candidates.first
                parent = node?.parent as? TilingContainer
                orientation = parent?.orientation
            case .smartOpposite:
                orientation = (candidates.first?.parent as? TilingContainer)?.orientation.opposite
                node = candidates.first(where: { ($0.parent as? TilingContainer)?.orientation == orientation })
                parent = node?.parent as? TilingContainer
        }
        guard let parent else {
            return .fail(io.err("resize command doesn't support floating windows yet https://github.com/nikitabobko/AeroSpace/issues/9"))
        }
        guard let orientation else { return .fail }
        guard let node else { return .fail }
        // The weights become screen points. Before the first layout pass they may be anything: 1, 1, 1...
        guard node.predictLayoutRect() != nil, let index = node.ownIndex else { return .fail }
        let diff: CGFloat = switch args.units.val {
            case .set(let unit): CGFloat(unit) - node.getWeight(orientation)
            case .add(let unit): CGFloat(unit)
            case .subtract(let unit): -CGFloat(unit)
        }
        let siblingIndexes = parent.children.indices.filter { $0 != index }
        if siblingIndexes.isEmpty { return .fail }

        // Nobody is shrunk under 'tiling.min-window-size': the resize stops there. It isn't an error, and the command
        // doesn't tell about it: a key that is held down in a resize mode reaches the limit all the time
        var weights = parent.children.map { $0.getWeight(orientation) }
        let minimums = parent.children.map(\.minimumResizeWeight)
        if diff > 0 {
            let shrunk = shrinkWeights(siblingIndexes.map { weights[$0] }, by: diff, minimums: siblingIndexes.map { minimums[$0] })
            for (siblingIndex, weight) in zip(siblingIndexes, shrunk) {
                weights[index] += weights[siblingIndex] - weight
                weights[siblingIndex] = weight
            }
        } else {
            let given = weights[index] - shrinkWeights([weights[index]], by: -diff, minimums: [minimums[index]])[0]
            weights[index] -= given
            for siblingIndex in siblingIndexes {
                weights[siblingIndex] += given / CGFloat(siblingIndexes.count)
            }
        }
        for (child, weight) in zip(parent.children, weights) {
            child.setWeight(orientation, weight)
        }
        return .succ
    }
}

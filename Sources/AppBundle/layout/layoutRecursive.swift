import AppKit

extension Workspace {
    @MainActor
    func layoutWorkspace() async throws {
        if isEffectivelyEmpty { return }
        let frame = layoutFrame
        try await layoutRecursive(frame.point, width: frame.width, height: frame.height, virtual: frame.virtual, LayoutContext(self))
    }

    /// The frame of the workspace, and of its root tiling container
    @MainActor
    fileprivate var layoutFrame: LayoutFrame {
        let rect = workspaceMonitor.visibleRectPaddedByOuterGaps
        // If monitors are aligned vertically and the monitor below has smaller width, then macOS may not allow the
        // window on the upper monitor to take full width. rect.height - 1 resolves this problem
        // But I also faced this problem in monitors horizontal configuration. ¯\_(ツ)_/¯
        return LayoutFrame(point: rect.topLeftCorner, width: rect.width, height: rect.height - 1, virtual: rect)
    }
}

/// The place of a node on the screen. Physical frame (with real inner gaps): point, width, height
private struct LayoutFrame {
    let point: CGPoint
    let width: CGFloat
    let height: CGFloat
    let virtual: Rect // as if inner gaps were always zero

    var physicalRect: Rect { Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height) }
}

extension TreeNode {
    /// The physical rect (with real inner gaps) that the next layout pass gives to the node, as long as the tree doesn't change.
    /// Unlike ``lastAppliedLayoutPhysicalRect``, it's available before the node is laid out for the first time,
    /// and it's never outdated.
    ///
    /// Side effect: just like the layout pass, it normalizes the weights of the nodes on the way from the root
    /// container to the node, and the weights of their siblings. After the call, the weights are in screen points.
    ///
    /// nil if the node isn't a part of the tiling tree of a workspace
    @MainActor
    func predictLayoutRect() -> Rect? {
        let path: [TreeNode] = parentsWithSelf.reversed() // workspace, root container, ..., self
        guard let workspace = path.first as? Workspace, path.count >= 2 else { return nil }
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
        var frame = workspace.layoutFrame
        for (parent, child) in zip(path.dropFirst(), path.dropFirst(2)) {
            guard let parent = parent as? TilingContainer else { return nil }
            guard let childFrame = parent.tileChildren(frame, gaps).first(where: { $0.child === child })?.frame else { return nil }
            frame = childFrame
        }
        return path[1] is TilingContainer ? frame.physicalRect : nil
    }
}

extension TreeNode {
    @MainActor
    fileprivate func layoutRecursive(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let physicalRect = Rect(topLeftX: point.x, topLeftY: point.y, width: width, height: height)
        switch nodeCases {
            case .workspace(let workspace):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                try await workspace.rootTilingContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
                try await workspace.floatingWindowsContainer.layoutRecursive(point, width: width, height: height, virtual: virtual, context)
            case .floatingWindowsContainer(let container):
                for window in container.children.filterIsInstance(of: Window.self) {
                    window.lastAppliedLayoutPhysicalRect = nil
                    window.lastAppliedLayoutVirtualRect = nil
                    try await window.layoutFloatingWindow(context)
                }
            case .window(let window):
                if window.windowId != currentlyManipulatedWithMouseWindowId {
                    lastAppliedLayoutVirtualRect = virtual
                    if window.isFullscreen && window == context.workspace.rootTilingContainer.mostRecentWindowRecursive {
                        lastAppliedLayoutPhysicalRect = nil
                        window.layoutFullscreen(context)
                    } else {
                        lastAppliedLayoutPhysicalRect = physicalRect
                        window.isFullscreen = false
                        DebugStats.count("layout.tiling-window-frame")
                        window.setAxFrame(point, CGSize(width: width, height: height))
                    }
                }
            case .tilingContainer(let container):
                lastAppliedLayoutPhysicalRect = physicalRect
                lastAppliedLayoutVirtualRect = virtual
                switch container.layout {
                    case .tiles:
                        try await container.layoutTiles(point, width: width, height: height, virtual: virtual, context)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer:
                return // Nothing to do for weirdos
        }
    }
}

private struct LayoutContext {
    let workspace: Workspace
    let resolvedGaps: ResolvedGaps

    @MainActor
    init(_ workspace: Workspace) {
        self.workspace = workspace
        self.resolvedGaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor)
    }
}

extension Window {
    @MainActor
    fileprivate func layoutFloatingWindow(_ context: LayoutContext) async throws {
        let workspace = context.workspace
        let windowRect = try await getAxRect(.cancellable) // Probably not idempotent
        lastKnownFloatingRect = windowRect
        let currentMonitor = windowRect?.center.monitorApproximation
        if let currentMonitor, let windowRect, workspace != currentMonitor.activeWorkspace {
            let windowTopLeftCorner = windowRect.topLeftCorner
            let xProportion = (windowTopLeftCorner.x - currentMonitor.visibleRect.topLeftX) / currentMonitor.visibleRect.width
            let yProportion = (windowTopLeftCorner.y - currentMonitor.visibleRect.topLeftY) / currentMonitor.visibleRect.height

            let workspaceRect = workspace.workspaceMonitor.visibleRect
            var newX = workspaceRect.topLeftX + xProportion * workspaceRect.width
            var newY = workspaceRect.topLeftY + yProportion * workspaceRect.height

            let windowWidth = windowRect.width
            let windowHeight = windowRect.height
            newX = newX.coerce(in: workspaceRect.minX ... max(workspaceRect.minX, workspaceRect.maxX - windowWidth))
            newY = newY.coerce(in: workspaceRect.minY ... max(workspaceRect.minY, workspaceRect.maxY - windowHeight))

            setAxFrame(CGPoint(x: newX, y: newY), nil)
            lastKnownFloatingRect = Rect(topLeftX: newX, topLeftY: newY, width: windowWidth, height: windowHeight)
        }
        if isFullscreen {
            lastKnownFloatingRect = nil
            layoutFullscreen(context)
            isFullscreen = false
        }
    }

    @MainActor
    fileprivate func layoutFullscreen(_ context: LayoutContext) {
        let monitorRect = noOuterGapsInFullscreen
            ? context.workspace.workspaceMonitor.visibleRect
            : context.workspace.workspaceMonitor.visibleRectPaddedByOuterGaps
        setAxFrame(monitorRect.topLeftCorner, CGSize(width: monitorRect.width, height: monitorRect.height))
    }
}

extension TilingContainer {
    @MainActor
    fileprivate func layoutTiles(_ point: CGPoint, width: CGFloat, height: CGFloat, virtual: Rect, _ context: LayoutContext) async throws {
        let frame = LayoutFrame(point: point, width: width, height: height, virtual: virtual)
        for (child, frame) in tileChildren(frame, context.resolvedGaps) {
            try await child.layoutRecursive(frame.point, width: frame.width, height: frame.height, virtual: frame.virtual, context)
        }
    }

    /// Normalizes the weights of the children (their sum becomes the size of the container), and
    /// returns the frames of the children
    @MainActor
    fileprivate func tileChildren(_ frame: LayoutFrame, _ gaps: ResolvedGaps) -> [(child: TreeNode, frame: LayoutFrame)] {
        let width = frame.width
        let height = frame.height
        var point = frame.point
        var virtualPoint = frame.virtual.topLeftCorner

        if children.isEmpty { return [] }
        let rawGap = gaps.inner.get(orientation).toDouble()
        let weights = normalizedWeights(
            children.map { $0.getWeight(orientation) },
            toFill: orientation == .h ? width : height,
            minimum: max(rawGap, 0) + 1,
        )

        var result: [(child: TreeNode, frame: LayoutFrame)] = []
        let lastIndex = children.indices.last
        for (i, child) in children.enumerated() {
            child.setWeight(orientation, weights[i])
            // Gaps. Consider 4 cases:
            // 1. Multiple children. Layout first child
            // 2. Multiple children. Layout last child
            // 3. Multiple children. Layout child in the middle
            // 4. Single child   let rawGap = gaps.inner.get(orientation).toDouble()
            let gap = rawGap - (i == 0 ? rawGap / 2 : 0) - (i == lastIndex ? rawGap / 2 : 0)
            let childFrame = LayoutFrame(
                point: i == 0 ? point : point.addingOffset(orientation, rawGap / 2),
                width: orientation == .h ? child.hWeight - gap : width,
                height: orientation == .v ? child.vWeight - gap : height,
                virtual: Rect(
                    topLeftX: virtualPoint.x,
                    topLeftY: virtualPoint.y,
                    width: orientation == .h ? child.hWeight : width,
                    height: orientation == .v ? child.vWeight : height,
                ),
            )
            result.append((child, childFrame))
            virtualPoint = orientation == .h ? virtualPoint.addingXOffset(child.hWeight) : virtualPoint.addingYOffset(child.vWeight)
            point = orientation == .h ? point.addingXOffset(child.hWeight) : point.addingYOffset(child.vWeight)
        }
        return result
    }
}

/// The weights of the children of a container, changed so that their sum is the size of the container.
///
/// Like in AeroSpace, every child takes the same share of the difference. That alone can leave a small child with
/// a negative weight, and its window with a negative size that overlaps the neighbors: a window is added with an
/// average weight next to a small one, or a small window is shrunk with the resize command. So the children that
/// would end up under `minimum` (the inner gap plus one point: the smallest weight that leaves room for a window)
/// get `minimum`, and the rest of the children share the difference that is left.
/// If there is no room for `minimum` for everybody, all the children get the same weight
func normalizedWeights(_ weights: [CGFloat], toFill size: CGFloat, minimum: CGFloat) -> [CGFloat] {
    if weights.isEmpty { return [] }
    let count = CGFloat(weights.count)
    let delta = (size - weights.reduce(0, +)) / count
    var result = weights.map { $0 + delta }
    if result.allSatisfy({ $0 >= minimum }) { return result } // Always the case, but for the corner cases above
    let equal = Array(repeating: size / count, count: weights.count)
    if !(size >= minimum * count) { return equal }
    var pinned: Set<Int> = []
    while true {
        let tooSmall = result.indices.filter { !pinned.contains($0) && !(result[$0] >= minimum) }
        if tooSmall.isEmpty { return result }
        pinned.formUnion(tooSmall)
        let free = weights.indices.filter { !pinned.contains($0) }
        if free.isEmpty { return equal }
        let delta = (size - minimum * CGFloat(pinned.count) - free.reduce(0) { $0 + weights[$1] }) / CGFloat(free.count)
        for index in pinned { result[index] = minimum }
        for index in free { result[index] = weights[index] + delta }
    }
}

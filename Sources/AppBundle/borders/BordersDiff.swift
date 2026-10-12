import CoreGraphics

/// The smallest change that turns the borders on the screen into the wanted ones
enum BorderOp: Equatable, Sendable {
    /// A window got a border
    case add(BorderItem)
    /// The frame of the window, the width, the corner radius or the glow changed: the panel is moved and its shape is rebuilt
    case reshape(BorderItem)
    /// Only the color changed: the cheapest change, and the most frequent one (every focus change)
    case recolor(windowId: UInt32, Rgba)
    /// The window lost its border
    case remove(windowId: UInt32)
}

enum BordersDiff {
    /// Pure. Removals first, then the changes in the order of `new`. Nothing for the borders that stay the same
    static func ops(from old: [BorderItem], to new: [BorderItem]) -> [BorderOp] {
        var oldById: [UInt32: BorderItem] = [:]
        for item in old { oldById[item.windowId] = item }
        let newIds = Set(new.map(\.windowId))
        var result: [BorderOp] = old.filter { !newIds.contains($0.windowId) }.map { .remove(windowId: $0.windowId) }
        for item in new {
            guard let before = oldById[item.windowId] else {
                result.append(.add(item))
                continue
            }
            if before.frame != item.frame || before.width != item.width || before.cornerRadius != item.cornerRadius ||
                before.glowRadius != item.glowRadius
            {
                result.append(.reshape(item))
            }
            if before.color != item.color {
                result.append(.recolor(windowId: item.windowId, item.color))
            }
        }
        return result
    }
}

/// Keeps every border glued, in the Z order, to its window
enum BorderStacking {
    struct Panel: Equatable, Sendable {
        var windowId: UInt32
        /// The window number of the panel of the border
        var panelNumber: Int
        var isVisible: Bool
    }

    enum Op: Equatable, Sendable {
        /// Put the panel right above its window, showing it if needed
        case orderAbove(windowId: UInt32)
        /// The window isn't on the screen (another Space, minimized, gone): its border must not be either
        case hide(windowId: UInt32)
    }

    /// Pure.
    /// - Parameter order: the numbers of the windows of all the apps that are on the screen, front to back
    static func plan(order: [Int], panels: [Panel]) -> [Op] {
        var index: [Int: Int] = [:]
        for (i, number) in order.enumerated() where index[number] == nil { index[number] = i }
        var result: [Op] = []
        for panel in panels {
            guard let target = index[Int(panel.windowId)] else {
                if panel.isVisible { result.append(.hide(windowId: panel.windowId)) }
                continue
            }
            if !panel.isVisible || index[panel.panelNumber] != target - 1 {
                result.append(.orderAbove(windowId: panel.windowId))
            }
        }
        return result
    }
}

/// The layout asks a window for a frame, but the window has the last word (minimum sizes, fixed sizes, slow apps).
/// The border must go around the window, not around the frame that was asked for
enum BorderCorrection {
    /// Pure.
    /// - Parameter actual: the frames of the windows on the screen, as the window server reports them
    /// - Returns: the items, with the frame replaced by the real one where they differ by more than the tolerance
    static func corrected(_ items: [BorderItem], actual: [UInt32: CGRect], tolerance: CGFloat = 1) -> [BorderItem] {
        items.map { item in
            guard let real = actual[item.windowId], real.width >= 1, real.height >= 1 else { return item }
            let differs = abs(real.minX - item.frame.minX) > tolerance || abs(real.minY - item.frame.minY) > tolerance ||
                abs(real.maxX - item.frame.maxX) > tolerance || abs(real.maxY - item.frame.maxY) > tolerance
            var item = item
            if differs { item.frame = real }
            return item
        }
    }
}

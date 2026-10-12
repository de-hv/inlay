@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// See: normalizedWeights. The layout must never give a window a negative size
    @Suite @MainActor struct NormalizedWeightsTest {
        let workspace: Workspace

        init() {
            setUpWorkspacesForTests()
            workspace = focus.workspace
        }

        @Test func testEveryChildTakesTheSameShareOfTheDifference() {
            // The behavior of AeroSpace, untouched as long as nobody ends up too small
            assertEquals(normalizedWeights([1, 1, 1], toFill: 1920, minimum: 1), [640, 640, 640])
            assertEquals(normalizedWeights([1000, 500], toFill: 1920, minimum: 1), [1210, 710])
            assertEquals(normalizedWeights([1400, 700, 720], toFill: 1920, minimum: 1), [1100, 400, 420] as [CGFloat])
            assertEquals(normalizedWeights([5], toFill: 1920, minimum: 1), [1920])
            assertEquals(normalizedWeights([], toFill: 1920, minimum: 1), [])
        }

        @Test func testNobodyEndsUpUnderTheMinimum() {
            // AeroSpace gives [1490, -210, 640] here
            assertEquals(normalizedWeights([1810, 110, 960], toFill: 1920, minimum: 1), [1384.5, 1, 534.5])
            // A weight left negative by the resize command
            assertEquals(normalizedWeights([-65, 1985], toFill: 1920, minimum: 15), [15, 1905])
            // Pinning one child pushes another one under the minimum
            assertEquals(normalizedWeights([10, 30, 3000], toFill: 1000, minimum: 20), [20, 20, 960])
            // No room for the minimum, or nothing to tell the children apart: equal shares
            assertEquals(normalizedWeights([10, 500, 30], toFill: 30, minimum: 20), [10, 10, 10])
            assertEquals(normalizedWeights([.nan, 5], toFill: 100, minimum: 1), [50, 50])
            assertEquals(normalizedWeights([.infinity, 5], toFill: 100, minimum: 1), [50, 50])
            for weights in [[1810, 110, 960], [-65, 1985], [10, 30, 3000], [0, 0, 0, 0], [-5, -5]] as [[CGFloat]] {
                let result = normalizedWeights(weights, toFill: 1920, minimum: 15)
                assertEquals(abs(result.reduce(0, +) - 1920) < 0.001, true, additionalMsg: "\(weights)")
                assertEquals(result.allSatisfy { $0 >= 15 }, true, additionalMsg: "\(weights)")
            }
        }

        /// Regression: shrinking a small window used to give it a negative width. Now the resize command stops
        /// at 'tiling.min-window-size', long before the floor of the layout
        @Test func testResizeBelowZero_theWindowKeepsAPositiveSize() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1800)
                assertEquals(TestWindow.new(id: 2, parent: $0, adaptiveWeight: 120).focusWindow(), true)
            }
            try await workspace.layoutWorkspace()
            _ = await parseCommand("resize smart -200").cmdOrDie.run(.defaultEnv, .emptyStdin)
            try await workspace.layoutWorkspace()
            let rects = workspace.rootTilingContainer.allLeafWindowsRecursive.compactMap { ($0 as? TestWindow)?.rect }
            assertEquals(rects.map(\.width), [1820, 100])
            assertEquals(rects.map(\.topLeftX), [0, 1820])
        }

        /// The floor of the layout is still there for the weights that the resize command doesn't decide
        @Test func testWeightBelowZero_theWindowKeepsAPositiveSize() async throws {
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 2000)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: -80)
            }
            try await workspace.layoutWorkspace()
            let rects = workspace.rootTilingContainer.allLeafWindowsRecursive.compactMap { ($0 as? TestWindow)?.rect }
            assertEquals(rects.map(\.width), [1919, 1])
            assertEquals(rects.map(\.topLeftX), [0, 1919])
        }

        /// The gap is a part of the weight: a window needs more than the gap to have a positive size
        @Test func testMinimumLeavesRoomForTheInnerGap() async throws {
            config.gaps = Gaps(inner: .init(vertical: 0, horizontal: 20), outer: .zero)
            workspace.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0, adaptiveWeight: 1915)
                TestWindow.new(id: 2, parent: $0, adaptiveWeight: 5)
            }
            try await workspace.layoutWorkspace()
            let rects = workspace.rootTilingContainer.allLeafWindowsRecursive.compactMap { ($0 as? TestWindow)?.rect }
            assertEquals(rects.allSatisfy { $0.width > 0 && $0.height > 0 }, true, additionalMsg: "\(rects)")
        }
    }
}

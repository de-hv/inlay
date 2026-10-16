@testable import AppBundle
import AppKit
import Common
import Testing

extension InlayTests {
    /// The tiling windows slide to their frames when a window opens or closes, or is moved with swap or move
    @Suite @MainActor struct WindowAnimatorTest {
        private let animator = WindowAnimator.shared

        init() {
            setUpWorkspacesForTests()
            ServerState.shared.axPermissionStatus = .granted
            ServerState.shared.isEnabled = true
            currentlyManipulatedWithMouseWindowId = nil
            // Turned off again by setUpWorkspacesForTests, for the next test
            animator.isEnabledInTests = true
        }

        private func frame(_ window: TestWindow) -> CGRect? { window.rect.map(CGRect.init) }

        /// Equal but for the rounding of the frames to whole points
        private func isClose(_ a: CGRect?, _ b: CGRect?) -> Bool {
            guard let a, let b else { return false }
            return [a.minX - b.minX, a.minY - b.minY, a.width - b.width, a.height - b.height].allSatisfy { abs($0) <= 1 }
        }

        // MARK: - The curve

        @Test func testFrameAnimation() {
            let start = ContinuousClock.now
            let from = CGRect(x: 0, y: 0, width: 100, height: 200)
            let to = CGRect(x: 100, y: 50, width: 300, height: 200)
            let animation = FrameAnimation(from: from, to: to, start: start, duration: .milliseconds(200))
            assertEquals(animation.frame(at: start), from)
            assertEquals(animation.frame(at: start + .milliseconds(200)), to)
            assertEquals(animation.frame(at: start + .seconds(5)), to)
            assertEquals(animation.isFinished(at: start + .milliseconds(199)), false)
            assertEquals(animation.isFinished(at: start + .milliseconds(200)), true)
            // Ease out: more than half of the way at half of the time, and never back
            let half = animation.frame(at: start + .milliseconds(100))
            assertTrue(half.minX > 50 && half.minX < 100)
            var last = -1.0
            for step in 0 ... 20 {
                let value = FrameAnimation.ease(Double(step) / 20)
                assertTrue(value >= last)
                last = value
            }
            assertEquals(FrameAnimation.ease(0), 0)
            assertEquals(FrameAnimation.ease(1), 1)
            // No duration: already there
            assertEquals(FrameAnimation(from: from, to: to, start: start, duration: .zero).frame(at: start), to)
        }

        // MARK: - The layout

        @Test func testANewWindowGrowsFromTheCenterOfItsTile() async throws {
            let workspace = focus.workspace
            let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            assertEquals(window1.focusWindow(), true)
            // Not asked for: right away
            try await workspace.layoutWorkspace()
            assertEquals(animator.isAnimating, false)
            let alone = try #require(window1.lastAppliedLayoutPhysicalRect.map(CGRect.init))

            let window2 = TestWindow.newTiling(id: 2, workspace: workspace)
            window2.isEntering = true
            animator.requestAnimatedLayout()
            let started = DebugStats.counters["animation.started"] ?? 0
            try await workspace.layoutWorkspace()
            assertEquals(animator.isAnimating, true)
            assertEquals(DebugStats.counters["animation.started"], started + 2)
            // The first frame: the window that is split where it was, and the new one in the center of its tile, smaller
            animator.tick(now: .now - .seconds(10))
            let tile2 = try #require(window2.lastAppliedLayoutPhysicalRect.map(CGRect.init))
            assertEquals(isClose(frame(window1), alone), true, additionalMsg: "\(String(describing: frame(window1))) \(alone)")
            assertEquals(isClose(frame(window2), WindowAnimator.entryFrame(tile2)), true, additionalMsg: "\(String(describing: frame(window2))) \(tile2)")
            assertEquals(frame(window2).map { abs($0.midX - tile2.midX) <= 1 && abs($0.width - tile2.width * 0.8) <= 1 }, true)
            assertEquals(window2.isEntering, false)
            assertEquals(animator.currentFrame(1) != nil, true)

            // The same layout again (the complete session after the light one): the animations go on
            try await workspace.layoutWorkspace()
            assertEquals(DebugStats.counters["animation.started"], started + 2)

            // Half way, on the way
            animator.tick(now: .now + .milliseconds(90))
            let target1 = try #require(window1.lastAppliedLayoutPhysicalRect.map(CGRect.init))
            let middle = try #require(frame(window1))
            assertEquals(middle.width < alone.width && middle.width > target1.width, true, additionalMsg: "\(alone) \(middle) \(target1)")
            // Over: exactly the frames of the layout
            animator.tick(now: .now + .seconds(1))
            assertEquals(animator.isAnimating, false)
            assertEquals(frame(window1), target1)
            assertEquals(frame(window2), window2.lastAppliedLayoutPhysicalRect.map(CGRect.init))
            assertEquals(animator.currentFrame(1), nil)
        }

        @Test func testALayoutThatIsNotAnimatedStopsTheAnimations() async throws {
            let workspace = focus.workspace
            let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
            assertEquals(window1.focusWindow(), true)
            try await workspace.layoutWorkspace()
            TestWindow.newTiling(id: 2, workspace: workspace)
            animator.requestAnimatedLayout()
            try await workspace.layoutWorkspace()
            assertEquals(animator.isAnimating, true)

            // Resizing, switching workspaces...: the windows jump to their frames, as before
            animator.layoutDidFinish()
            Window.get(byId: 2)?.unbindFromParent()
            try await workspace.layoutWorkspace()
            assertEquals(animator.isAnimating, false)
            assertEquals(frame(window1), window1.lastAppliedLayoutPhysicalRect.map(CGRect.init))
        }

        @Test func testAnimationsCanBeTurnedOff() async throws {
            config.animations.duration = 0
            let workspace = focus.workspace
            assertEquals(TestWindow.new(id: 1, parent: workspace.rootTilingContainer).focusWindow(), true)
            try await workspace.layoutWorkspace()
            TestWindow.newTiling(id: 2, workspace: workspace)
            animator.requestAnimatedLayout()
            try await workspace.layoutWorkspace()
            assertEquals(animator.isAnimating, false)
        }

        // MARK: - What asks for an animated layout

        @Test func testSwapAndMoveAskForAnAnimatedLayout() async throws {
            let workspace = focus.workspace
            workspace.rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 1, parent: $0)
                    TestWindow.new(id: 2, parent: $0)
                }
                assertEquals(TestWindow.new(id: 3, parent: $0).focusWindow(), true)
            }
            assertEquals(animator.isAnimatedLayoutRequested, false)
            await parseCommand("swap left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(animator.isAnimatedLayoutRequested, true)
            animator.layoutDidFinish()
            await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(animator.isAnimatedLayoutRequested, true)
            animator.layoutDidFinish()
            // Resizing is not animated
            await parseCommand("balance-sizes").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(animator.isAnimatedLayoutRequested, false)
        }

        /// The layout of the screenshot: A and B in a left column, C on the right
        @Test func testSwapKeepsTheShapeOfTheLayout() async throws {
            let workspace = focus.workspace
            var a: TestWindow!, b: TestWindow!, c: TestWindow!
            let root = workspace.rootTilingContainer.apply {
                TilingContainer.newVTiles(parent: $0, adaptiveWeight: 2).apply {
                    a = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 3)
                    b = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
                }
                c = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 1)
            }
            try await workspace.layoutWorkspace()
            let slots = [a, b, c].map { $0!.lastAppliedLayoutPhysicalRect.map(CGRect.init) }

            // B to the right: B takes the place of C, and C the one of B. The slots stay the same
            assertEquals(b.focusWindow(), true)
            await parseCommand("swap right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(root.layoutDescription, .h_tiles([.v_tiles([.window(1), .window(3)]), .window(2)]))
            try await workspace.layoutWorkspace()
            assertEquals([a, c, b].map { $0!.lastAppliedLayoutPhysicalRect.map(CGRect.init) }, slots)
            assertEquals(focus.windowOrNil?.windowId, 2)

            // B, now on the right, to the left: toward A and C, it swaps with the one focused more recently
            assertEquals(a.focusWindow(), true)
            assertEquals(b.focusWindow(), true)
            await parseCommand("swap left").cmdOrDie.run(.defaultEnv, .emptyStdin)
            assertEquals(root.layoutDescription, .h_tiles([.v_tiles([.window(2), .window(3)]), .window(1)]))
        }
    }
}

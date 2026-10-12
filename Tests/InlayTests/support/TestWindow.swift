@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    var isMacosFullscreenForTest = false
    var isMacosMinimizedForTest = false
    /// nil: the description of the window
    var titleForTest: String? = nil
    /// Asking for the title waits for it, like the real request to the app waits for the app to answer
    var titleGateForTest: AwaitableOneTimeBroadcastLatch? = nil

    @MainActor
    private init(_ id: UInt32, _ app: any AbstractApp, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?, index: Int) {
        _rect = rect
        super.init(id: id, app, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: index)
    }

    /// Binds the window to the given place of the tree
    @discardableResult
    @MainActor
    static func new(
        id: UInt32,
        parent: NonLeafTreeNodeObject,
        adaptiveWeight: CGFloat = 1,
        rect: Rect? = nil,
        index: Int = INDEX_BIND_LAST,
        app: any AbstractApp = TestApp.shared,
    ) -> TestWindow {
        let wi = TestWindow(id, app, parent, adaptiveWeight, rect, index: index)
        TestApp.shared._windows.append(wi)
        return wi
    }

    /// Places the window the same way as a new tiling window detected by the real app (MacWindow.getOrRegister).
    /// See: 'tiling.new-window-placement' config option
    @discardableResult
    @MainActor
    static func newTiling(id: UInt32, workspace: Workspace, app: any AbstractApp = TestApp.shared) -> TestWindow {
        let data = getBindingDataForNewTilingWindow(workspace, focused: focus.windowOrNil)
        return new(id: id, parent: data.parent, adaptiveWeight: data.adaptiveWeight, index: data.index, app: app)
    }

    /// The frame set by the last layout pass. See: Workspace.layoutWorkspace
    var rect: Rect? { _rect }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    @MainActor
    override func nativeFocus() {
        appForTests = TestApp.shared
        TestApp.shared.focusedWindow = self
    }

    override func closeAxWindow() {
        releaseTilingSpaceToNeighbor() // The same as MacWindow.garbageCollect
        unbindFromParent()
    }

    override func setAxFrame(_ topLeft: CGPoint?, _ size: CGSize?) {
        let prev = _rect ?? Rect(topLeftX: 0, topLeftY: 0, width: 0, height: 0)
        _rect = Rect(
            topLeftX: topLeft?.x ?? prev.topLeftX,
            topLeftY: topLeft?.y ?? prev.topLeftY,
            width: size?.width ?? prev.width,
            height: size?.height ?? prev.height,
        )
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String {
        try await titleGateForTest?.await()
        return titleForTest ?? description
    }

    @MainActor override func getAxRect(_ cm: CancellationMode) async throws -> Rect? { // todo change to not Optional
        _rect
    }

    @MainActor override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        _rect.map { CGSize(width: $0.width, height: $0.height) }
    }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { isMacosFullscreenForTest }
    override func isMacosMinimized(_ cm: CancellationMode) async throws -> Bool { isMacosMinimizedForTest }
}

import Testing

/// The root of all the suites.
///
/// The tests share the global model (config, workspaces, focus, TestApp), so they can't run in parallel.
/// Swift Testing only serializes the tests of one suite tree, that's why every suite must be nested here:
///
///     extension InlayTests {
///         @Suite @MainActor struct FooTest {
///             init() { setUpWorkspacesForTests() }
///             @Test func testFoo() { ... }
///         }
///     }
@Suite(.serialized) struct InlayTests {}

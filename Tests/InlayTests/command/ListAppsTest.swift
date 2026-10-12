@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    @Suite @MainActor struct ListAppsTest {
        @Test func testParse() {
            assertNotNil(parseCommand("list-apps --macos-native-hidden").cmdOrDie)
            assertNotNil(parseCommand("list-apps --macos-native-hidden no").cmdOrDie)
            assertNotNil(parseCommand("list-apps --format %{app-bundle-id}").cmdOrDie)
            assertNotNil(parseCommand("list-apps --count").cmdOrDie)
            assertEquals(parseCommand("list-apps --format %{app-bundle-id} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        }
    }
}

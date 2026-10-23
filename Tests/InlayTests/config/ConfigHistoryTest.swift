@testable import AppBundle
import Common
import Foundation
import Testing

extension InlayTests {
    /// Settings › Changes: the reloads that changed the config, and who changed it
    @Suite @MainActor struct ConfigHistoryTest {
        @Test func testRecordsTheKeysThatChanged() {
            let history = ConfigHistory()
            history.record(from: "[borders]\nwidth = 4\n", to: "[borders]\nwidth = 2\nglow = true\n")
            assertEquals(history.entries.count, 1)
            assertEquals(history.entries[0].source, .file)
            assertEquals(history.entries[0].changes, [
                ConfigChange(key: "borders.glow", old: nil, new: "true"),
                ConfigChange(key: "borders.width", old: "4", new: "2"),
            ])
        }

        /// The first load, a text that didn't change, and comments or formatting alone aren't changes
        @Test func testNothingToRecord() {
            let history = ConfigHistory()
            history.record(from: nil, to: "[borders]\nwidth = 4\n")
            history.record(from: "[borders]\nwidth = 4\n", to: "[borders]\nwidth = 4\n")
            history.record(from: "[borders]\nwidth = 4\n", to: "# Thin\n[borders]\n    width = 4 # points\n")
            history.record(from: "[borders]\nwidth = 4\n", to: nil)
            assertEquals(history.entries, [])
        }

        /// The text that the settings window wrote is its change, whoever reloads it first
        @Test func testTheChangesOfTheSettingsWindow() {
            let history = ConfigHistory()
            history.lastTextWrittenBySettings = "[borders]\nwidth = 6\n"
            history.record(from: "[borders]\nwidth = 4\n", to: "[borders]\nwidth = 6\n")
            history.record(from: "[borders]\nwidth = 6\n", to: "[borders]\nwidth = 8\n")
            assertEquals(history.entries.map(\.source), [.settings, .file])
            assertEquals(Set(history.entries.map(\.id)).count, 2)
        }

        @Test func testKeepsTheLastOnes() {
            let history = ConfigHistory()
            for width in 0 ... ConfigHistory.maxEntries + 4 {
                history.record(from: "[borders]\nwidth = \(width)\n", to: "[borders]\nwidth = \(width + 1)\n")
            }
            assertEquals(history.entries.count, ConfigHistory.maxEntries)
            assertEquals(history.entries.last?.changes.first?.new, "\(ConfigHistory.maxEntries + 5)")
        }
    }
}

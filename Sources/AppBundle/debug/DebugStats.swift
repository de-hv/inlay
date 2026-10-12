import Common

/// Counts what Inlay does, to find out what keeps it busy. See: 'debug-stats' command
///
/// The counters only live in memory and counting is one dictionary update: they are always on.
/// Never log or write a file from a place that counts
@MainActor
enum DebugStats {
    private(set) static var counters: [String: Int] = [:]
    private static let startedAt: ContinuousClock.Instant = .now
    /// The counters as the last report showed them
    private static var lastReport: (at: ContinuousClock.Instant, counters: [String: Int])? = nil

    static func count(_ name: String, _ amount: Int = 1) {
        counters[name, default: 0] += amount
    }

    /// The totals, and what has been counted since the previous report
    static func report() -> String {
        let now: ContinuousClock.Instant = .now
        let report = DebugStatsReport(
            version: "\(inlayAppVersion) \(gitHash)",
            uptime: (now - startedAt).seconds,
            interval: lastReport.map { (now - $0.at).seconds },
            gauges: [
                ("windows", MacWindow.allWindowsMap.count),
                ("apps", MacApp.allAppsMap.count),
                ("workspaces", Workspace.all.count),
                ("monitors", monitorInfos.count),
                ("border-panels", BordersController.shared.panelCount),
            ],
            counters: counters,
            previous: lastReport?.counters ?? [:],
        )
        lastReport = (now, counters)
        return report.text
    }
}

extension Duration {
    fileprivate var seconds: Double { self / .seconds(1) }
}

/// What 'debug-stats' prints. Pure
struct DebugStatsReport {
    var version: String
    /// Seconds since Inlay started
    var uptime: Double
    /// Seconds since the previous report. nil: this is the first one
    var interval: Double?
    /// What there is right now
    var gauges: [(name: String, value: Int)]
    var counters: [String: Int]
    /// The counters of the previous report
    var previous: [String: Int]

    var text: String {
        let period = interval ?? uptime
        let since = interval == nil ? "since Inlay started" : "since the previous debug-stats"
        var lines = [
            "Inlay \(version), running for \(Self.format(uptime)) s",
            gauges.map { "\($0.name): \($0.value)" }.joined(separator: "   "),
            "",
            "new and per-sec: the last \(Self.format(period)) s (\(since)). Counters that are still 0 aren't listed",
            "",
        ]
        var rows = [["counter", "total", "new", "per-sec"]]
        for (name, total) in counters.sorted(by: { $0.key < $1.key }) {
            let new = total - previous[name, default: 0]
            rows.append([name, String(total), String(new), Self.format(period > 0 ? Double(new) / period : 0)])
        }
        let widths = rows[0].indices.map { column in rows.map { $0[column].count }.max() ?? 0 }
        for row in rows {
            let name = row[0] + String(repeating: " ", count: widths[0] - row[0].count)
            let numbers = row.indices.dropFirst().map { String(repeating: " ", count: widths[$0] - row[$0].count) + row[$0] }
            lines.append(([name] + numbers).joined(separator: "   "))
        }
        return lines.joined(separator: "\n")
    }

    /// One decimal, whatever the locale
    private static func format(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10).\(abs(tenths % 10))"
    }
}

extension RefreshSessionEvent {
    /// What started the session, as the name of a counter
    var statName: String {
        switch self {
            case .ax(let notification): "ax.\(notification)"
            case .configAutoReload: "config-auto-reload"
            case .globalObserver(let notification): "workspace.\(notification)"
            case .globalObserverLeftMouseUp: "mouse-up"
            case .hotkeyBinding: "hotkey"
            case .menuBarButton: "menu-or-settings"
            case .resetManipulatedWithMouse: "end-of-mouse-manipulation"
            case .socketServer(let args): "cli.\(type(of: args).info.kind.rawValue)"
            case .startup: "startup"
            case .focusFollowsMouse: "focus-follows-mouse"
        }
    }
}

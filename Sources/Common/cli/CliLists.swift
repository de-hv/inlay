import Foundation

/// The tables of the list-* commands for a terminal. The server answers them with --json: these turn its objects into
/// CliTable. Piped, the commands print what they always did
public enum CliLists {
    public typealias Object = [String: Any]

    /// The objects of a JSON answer of the server
    public static func objects(_ json: String) -> [Object] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [Object] ?? []
    }

    static func string(_ object: Object, _ key: String) -> String {
        switch object[key] {
            case let string as String: string
            case let number as NSNumber: number.stringValue
            default: ""
        }
    }

    static func bool(_ object: Object, _ key: String) -> Bool { (object[key] as? Bool) ?? ((object[key] as? NSNumber)?.boolValue ?? false) }

    /// 'Zed · Code', 'Slack · Telegram · +2'
    public static func appNames(_ names: [String]) -> String {
        var unique: [String] = []
        for name in names where !unique.contains(name) { unique.append(name) }
        if unique.isEmpty { return "–" }
        return unique.count <= 3 ? unique.joined(separator: " · ") : unique.prefix(2).joined(separator: " · ") + " · +\(unique.count - 2)"
    }

    /// The fields that list-workspaces asks the server for
    public static let workspaceFormat = "%{workspace} %{workspace-is-focused} %{monitor-name}"
    /// The fields of the windows, for the count and the apps of each workspace, and for list-windows
    public static let windowFormat = "%{window-id} %{app-name} %{window-title} %{window-layout} %{workspace}"
    public static let monitorFormat = "%{monitor-id} %{monitor-name} %{monitor-is-main}"
    public static let appFormat = "%{app-pid} %{app-name} %{app-bundle-id}"

    /// - Parameter names: the names of the workspaces of the config: id → name
    public static func workspaces(_ workspaces: [Object], windows: [Object], names: [String: String]) -> CliTable {
        let byWorkspace = Dictionary(grouping: windows) { string($0, "workspace") }
        // With one monitor, the column says the same on every row
        let showsMonitor = Set(workspaces.map { string($0, "monitor-name") }).count > 1
        var columns = [CliTable.Column("WS"), CliTable.Column("NAME", priority: 4, truncation: .tail, minWidth: 6)]
        if showsMonitor { columns.append(CliTable.Column("MONITOR", priority: 2, truncation: .tail, minWidth: 6)) }
        columns += [CliTable.Column("WINDOWS"), CliTable.Column("APPS", priority: 1, truncation: .tail, minWidth: 8)]
        let rows = workspaces.map { workspace -> CliTable.Row in
            let id = string(workspace, "workspace")
            let own = byWorkspace[id] ?? []
            var cells = [id, names[id] ?? ""]
            if showsMonitor { cells.append(monitorRole(string(workspace, "monitor-name"))) }
            cells += [own.isEmpty ? "–" : String(own.count), appNames(own.map { string($0, "app-name") })]
            return CliTable.Row(cells, isCurrent: bool(workspace, "workspace-is-focused"))
        }
        return CliTable(columns: columns, rows: rows)
    }

    /// The built-in display is 'main' for most people: its long name says little in a table
    static func monitorRole(_ name: String) -> String {
        name.replacingOccurrences(of: "Built-in Retina Display", with: "Built-in")
    }

    public static func windows(_ windows: [Object], focusedId: String?) -> CliTable {
        let workspaces = Set(windows.map { string($0, "workspace") })
        var columns = [
            CliTable.Column("ID"),
            CliTable.Column("APP", truncation: .tail, minWidth: 6),
            CliTable.Column("TITLE", truncation: .middle, minWidth: 10),
        ]
        if workspaces.count > 1 { columns.append(CliTable.Column("WS", priority: 2)) }
        columns.append(CliTable.Column("LAYOUT", priority: 1))
        let rows = windows.map { window -> CliTable.Row in
            let layout = layoutName(string(window, "window-layout"))
            var cells = [string(window, "window-id"), string(window, "app-name"), string(window, "window-title")]
            if workspaces.count > 1 { cells.append(string(window, "workspace")) }
            cells.append(layout)
            return CliTable.Row(cells, isCurrent: string(window, "window-id") == focusedId, tones: layout == "floating" ? [cells.count - 1: .warning] : [:])
        }
        return CliTable(columns: columns, rows: rows)
    }

    /// 'h_tiles' and 'v_tiles' are 'tiling' for people
    static func layoutName(_ layout: String) -> String {
        layout.hasSuffix("tiles") ? "tiling" : layout
    }

    /// - Parameter workspaces: the visible workspace of each monitor: monitor id → workspace
    public static func monitors(_ monitors: [Object], workspaces: [String: String], focusedId: String?) -> CliTable {
        let columns = [
            CliTable.Column("#"),
            CliTable.Column("NAME", truncation: .middle, minWidth: 10),
            CliTable.Column("WORKSPACE"),
            CliTable.Column("ROLE", priority: 1),
        ]
        let rows = monitors.map { monitor -> CliTable.Row in
            let id = string(monitor, "monitor-id")
            return CliTable.Row(
                [id, string(monitor, "monitor-name"), workspaces[id] ?? "–", bool(monitor, "monitor-is-main") ? "main" : "secondary"],
                isCurrent: id == focusedId,
            )
        }
        return CliTable(columns: columns, rows: rows)
    }

    public static func apps(_ apps: [Object], focusedPid: String?) -> CliTable {
        let columns = [
            CliTable.Column("PID"),
            CliTable.Column("NAME", truncation: .tail, minWidth: 8),
            CliTable.Column("BUNDLE ID", priority: 1, truncation: .middle, minWidth: 12),
        ]
        let rows = apps.map { app -> CliTable.Row in
            CliTable.Row([string(app, "app-pid"), string(app, "app-name"), string(app, "app-bundle-id")], isCurrent: string(app, "app-pid") == focusedPid)
        }
        return CliTable(columns: columns, rows: rows)
    }
}

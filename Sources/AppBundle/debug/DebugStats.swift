/// Counts what Inlay does, to find out what keeps it busy. See: 'debug-stats' command
///
/// The counters only live in memory and counting is one dictionary update: they are always on.
/// Never log or write a file from a place that counts
@MainActor
enum DebugStats {
    private(set) static var counters: [String: Int] = [:]

    static func count(_ name: String, _ amount: Int = 1) {
        counters[name, default: 0] += amount
    }
}

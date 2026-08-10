import Foundation
import Combine

/// Persistent cumulative traffic accounting (spec §5.1 extension): per-day,
/// per-month, and all-time byte totals for both directions. Stored in the
/// app-group container so the numbers survive relaunches and start/stop.
///
/// The proxy feeds deltas via `add(inBytes:outBytes:)` (once per sampling
/// tick); the store keeps a bounded per-day ledger and derives month/total
/// from it plus an all-time accumulator.
final class UsageStore: ObservableObject {
    struct DayUsage: Identifiable {
        let day: String        // "yyyy-MM-dd"
        let bytesIn: Int
        let bytesOut: Int
        var id: String { day }
        var total: Int { bytesIn + bytesOut }
    }

    // Published snapshot the UI observes.
    @Published private(set) var todayIn = 0
    @Published private(set) var todayOut = 0
    @Published private(set) var monthIn = 0
    @Published private(set) var monthOut = 0
    @Published private(set) var totalIn = 0
    @Published private(set) var totalOut = 0
    @Published private(set) var recentDays: [DayUsage] = []

    private let defaults: UserDefaults
    private let daysKey = "usage.days"       // [String: [Int]] -> [in, out]
    private let totalInKey = "usage.totalIn"
    private let totalOutKey = "usage.totalOut"
    private let retentionDays = 90           // prune ledger beyond this

    private var days: [String: [Int]] = [:]  // dayKey -> [in, out]
    private var allTimeIn = 0
    private var allTimeOut = 0
    private var dirty = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(defaults: UserDefaults = SharedState.defaults) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutation

    /// Adds traffic to today's ledger and the all-time totals. Cheap; call
    /// once per sampling tick. Persistence is deferred to `flush()`.
    func add(inBytes: Int, outBytes: Int) {
        guard inBytes != 0 || outBytes != 0 else { return }
        let key = Self.dayFormatter.string(from: Date())
        var entry = days[key] ?? [0, 0]
        entry[0] += max(0, inBytes)
        entry[1] += max(0, outBytes)
        days[key] = entry
        allTimeIn += max(0, inBytes)
        allTimeOut += max(0, outBytes)
        dirty = true
        recompute()
    }

    /// Writes the ledger to disk (if changed) after pruning old entries.
    func flush() {
        guard dirty else { return }
        prune()
        defaults.set(days, forKey: daysKey)
        defaults.set(allTimeIn, forKey: totalInKey)
        defaults.set(allTimeOut, forKey: totalOutKey)
        dirty = false
    }

    // MARK: - Derivation

    private func load() {
        days = (defaults.dictionary(forKey: daysKey) as? [String: [Int]]) ?? [:]
        allTimeIn = defaults.integer(forKey: totalInKey)
        allTimeOut = defaults.integer(forKey: totalOutKey)
        recompute()
    }

    private func recompute() {
        let todayKey = Self.dayFormatter.string(from: Date())
        let monthKey = String(todayKey.prefix(7))  // "yyyy-MM"

        let today = days[todayKey] ?? [0, 0]
        todayIn = today[0]
        todayOut = today[1]

        var mIn = 0, mOut = 0
        for (key, v) in days where key.hasPrefix(monthKey) {
            mIn += v[0]; mOut += v[1]
        }
        monthIn = mIn
        monthOut = mOut

        totalIn = allTimeIn
        totalOut = allTimeOut

        recentDays = days.keys.sorted(by: >).prefix(7).map { key in
            let v = days[key] ?? [0, 0]
            return DayUsage(day: key, bytesIn: v[0], bytesOut: v[1])
        }
    }

    private func prune() {
        guard days.count > retentionDays else { return }
        let keep = Set(days.keys.sorted(by: >).prefix(retentionDays))
        days = days.filter { keep.contains($0.key) }
    }
}

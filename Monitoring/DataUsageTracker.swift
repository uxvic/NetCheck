import Foundation
import Observation

/// Accurate cumulative data-usage accounting, bucketed by local day. It sums the EXACT per-tick
/// byte deltas from `ThroughputSampler` (wrap-safe), so totals are byte-accurate while the app runs.
///
/// Scope/limits (by design): counts traffic on the active network interface (internet + local LAN),
/// and only while NetCheck is running. True internet-only/per-app accounting would need a system
/// network extension. Day buckets persist across launches; rollups use the user's calendar.
@MainActor
@Observable
final class DataUsageTracker {
    struct Usage: Codable, Equatable {
        var down: UInt64 = 0
        var up: UInt64 = 0
        var total: UInt64 { down &+ up }
    }

    private(set) var today = Usage()
    private(set) var week = Usage()
    private(set) var month = Usage()
    private(set) var year = Usage()

    private var days: [String: Usage] = [:]          // "yyyy-MM-dd" (local) → usage
    private let store = UserDefaults.standard
    private let key = "dataUsageDays_v1"
    private let cal = Calendar.current
    private let fmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    private var addsSincePersist = 0

    init() {
        load()
        recompute(now: Date())
    }

    /// Call every tick. Adds the exact byte delta to today's bucket and refreshes the rollups
    /// (also handles midnight rollover even when there's no traffic).
    func record(downBytes: UInt64, upBytes: UInt64, now: Date = Date()) {
        if downBytes > 0 || upBytes > 0 {
            let k = fmt.string(from: now)
            var u = days[k] ?? Usage()
            u.down &+= downBytes
            u.up &+= upBytes
            days[k] = u
            addsSincePersist += 1
            if addsSincePersist >= 10 { persist() }   // light throttle; ~once per 10s of traffic
        }
        recompute(now: now)
    }

    func reset() {
        days = [:]
        persist()
        recompute(now: Date())
    }

    // MARK: - Rollups

    private func recompute(now: Date) {
        today = days[fmt.string(from: now)] ?? Usage()
        var w = Usage(), m = Usage(), y = Usage()
        let wInt = cal.dateInterval(of: .weekOfYear, for: now)
        let mInt = cal.dateInterval(of: .month, for: now)
        let yInt = cal.dateInterval(of: .year, for: now)
        for (k, u) in days {
            guard let d = fmt.date(from: k) else { continue }
            let noon = cal.startOfDay(for: d).addingTimeInterval(12 * 3600)   // avoid midnight/DST edges
            if let wInt, wInt.contains(noon) { w.down &+= u.down; w.up &+= u.up }
            if let mInt, mInt.contains(noon) { m.down &+= u.down; m.up &+= u.up }
            if let yInt, yInt.contains(noon) { y.down &+= u.down; y.up &+= u.up }
        }
        week = w; month = m; year = y
    }

    // MARK: - Persistence

    private func load() {
        guard let data = store.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Usage].self, from: data) else { return }
        days = decoded
        prune()
    }

    private func persist() {
        prune()
        addsSincePersist = 0
        if let data = try? JSONEncoder().encode(days) { store.set(data, forKey: key) }
    }

    /// Keep ~2 years of daily buckets. `yyyy-MM-dd` sorts lexically, so a string compare is enough.
    private func prune() {
        guard let cutoff = cal.date(byAdding: .day, value: -740, to: Date()) else { return }
        let cutoffKey = fmt.string(from: cutoff)
        days = days.filter { $0.key >= cutoffKey }
    }
}

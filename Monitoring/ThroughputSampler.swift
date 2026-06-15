import Foundation

/// Samples per-interface byte counters via `getifaddrs` and returns the instantaneous
/// download/upload rate (bytes/sec) since the previous call.
///
/// Two subtleties handled here:
///  1. **VPN double-counting:** we read ONE interface (the active default-route interface that
///     `NWPath` reports), never the sum of all interfaces. Summing physical + utun double-counts.
///  2. **32-bit wraparound:** `if_data.ifi_ibytes/ifi_obytes` are `UInt32` and wrap at 4 GB. We use
///     Swift's overflow-subtraction operator (`&-`) so a single wrap between samples still yields a
///     correct positive delta.
actor ThroughputSampler {
    private var lastDown: UInt32 = 0
    private var lastUp: UInt32 = 0
    private var lastTime: TimeInterval = 0
    private var primed = false

    /// Discard the baseline — call on interface change and on wake (a long-sleep delta is meaningless).
    func reset() {
        primed = false
        lastTime = 0
        lastDown = 0
        lastUp = 0
    }

    /// Returns the instantaneous rate AND the exact byte delta since the previous sample. The raw
    /// `downBytes`/`upBytes` are what the data-usage tracker accumulates (exact, wrap-safe), rather
    /// than `rate × time` which would drift.
    func tick(interfaceName: String?) -> (down: Double, up: Double, downBytes: UInt64, upBytes: UInt64) {
        guard let interfaceName else {
            reset()
            return (0, 0, 0, 0)
        }
        let counters = Self.readCounters(for: interfaceName)
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            lastDown = counters.down
            lastUp = counters.up
            lastTime = now
            primed = true
        }
        guard primed, lastTime > 0 else { return (0, 0, 0, 0) }
        let elapsed = now - lastTime
        guard elapsed > 0.05 else { return (0, 0, 0, 0) }
        let downDelta = counters.down &- lastDown   // wrap-safe modular subtraction
        let upDelta = counters.up &- lastUp
        return (Double(downDelta) / elapsed, Double(upDelta) / elapsed, UInt64(downDelta), UInt64(upDelta))
    }

    /// Reads cumulative in/out bytes for a specific interface name (e.g. "en0", "utun3").
    private static func readCounters(for name: String) -> (down: UInt32, up: UInt32) {
        var down: UInt32 = 0
        var up: UInt32 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifap) }

        var ptr = ifap
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            guard let addr = cur.pointee.ifa_addr,
                  Int32(addr.pointee.sa_family) == AF_LINK,
                  let namePtr = cur.pointee.ifa_name,
                  String(cString: namePtr) == name,
                  let dataPtr = cur.pointee.ifa_data else { continue }
            let data = dataPtr.assumingMemoryBound(to: if_data.self)
            down = data.pointee.ifi_ibytes
            up = data.pointee.ifi_obytes
        }
        return (down, up)
    }
}

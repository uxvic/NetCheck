import Foundation

/// The connectivity states surfaced to the user. The whole reason the app exists is
/// `.vpnNoInternet` — interface is "connected" but real traffic doesn't reach the internet.
enum ConnectivityState: String, Equatable, Sendable {
    case checking
    case online
    case offline
    case vpnNoInternet
    case captivePortal

    var title: String {
        switch self {
        case .checking: return "Checking…"
        case .online: return "Online"
        case .offline: return "Offline"
        case .vpnNoInternet: return "VPN — No Internet"
        case .captivePortal: return "Sign-in Required"
        }
    }

    /// SF Symbol name for the static icon (detail panel, and the menu bar when the spinning globe
    /// is off). The menu bar's live indicator is a `globe` — the app is about *internet
    /// reachability*, not the Wi-Fi radio, so it must not wear the system Wi-Fi glyph.
    var symbolName: String {
        switch self {
        case .checking: return "globe"
        case .online: return "globe"
        case .offline: return "globe"
        case .vpnNoInternet: return "exclamationmark.shield.fill"
        case .captivePortal: return "person.crop.circle.badge.exclamationmark"
        }
    }

    var isHealthy: Bool { self == .online }
    var isProblem: Bool { self == .offline || self == .vpnNoInternet || self == .captivePortal }

    /// Speed tier from live download throughput, plus the non-rate states. Drives the globe's
    /// colour + spin and the detail-panel legend.
    func rateTier(downBytesPerSec: Double) -> RateTier {
        switch self {
        case .offline, .vpnNoInternet: return .offline
        case .captivePortal: return .signIn
        case .checking: return .checking
        case .online:
            let mbps = downBytesPerSec * 8 / 1_000_000
            if mbps < RateTier.idleFloorMbps { return .idle }
            if mbps < RateTier.slowCeilingMbps { return .slow }
            if mbps < RateTier.fastFloorMbps { return .normal }
            return .fast
        }
    }
}

/// Coarse colour bucket for the globe — AppKit maps it to an `NSColor`.
enum StatusTier { case good, neutral, warn, bad }

/// The speed tier the globe communicates. Thresholds are in Mbps (the unit ISPs use).
enum RateTier {
    case checking, idle, slow, normal, fast, signIn, offline

    static let fastFloorMbps = 200.0     // ≥ this → Fast (green, fast spin)
    static let slowCeilingMbps = 50.0    // < this, but transferring → Slow (amber)
    static let idleFloorMbps = 0.5       // online but under this → Idle (calm), not Slow

    var label: String {
        switch self {
        case .checking: return "Checking"
        case .idle: return "Idle"
        case .slow: return "Slow"
        case .normal: return "Normal"
        case .fast: return "Fast"
        case .signIn: return "Sign-in"
        case .offline: return "Offline"
        }
    }

    var colorTier: StatusTier {
        switch self {
        case .fast: return .good
        case .checking, .idle, .normal: return .neutral
        case .slow, .signIn: return .warn
        case .offline: return .bad
        }
    }

    /// Problems (offline / sign-in) hold the globe still; everything else spins.
    var spins: Bool {
        switch self {
        case .offline, .signIn: return false
        default: return true
        }
    }

    /// A real connectivity problem (worth colouring even in "only on problems" mode), as opposed
    /// to a merely slow/idle speed tier.
    var isProblem: Bool { self == .offline || self == .signIn }
}

/// The kind of interface currently carrying traffic.
enum ActiveInterface: String, Sendable, Equatable {
    case wifi, ethernet, cellular, vpn, other, none

    var label: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .cellular: return "Cellular"
        case .vpn: return "VPN"
        case .other: return "Other"
        case .none: return "—"
        }
    }
}

/// Immutable snapshot of everything the UI renders. Held by `NetworkMonitor` (the single source of truth).
struct NetworkSnapshot: Equatable {
    var state: ConnectivityState = .checking
    var downBytesPerSec: Double = 0
    var upBytesPerSec: Double = 0
    var latencyMs: Double? = nil
    var interface: ActiveInterface = .none
    var interfaceName: String? = nil
    var isVPNActive: Bool = false
    var isExpensive: Bool = false
    var publicIP: String? = nil
}

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

    /// SF Symbol name for the menu-bar icon.
    var symbolName: String {
        switch self {
        case .checking: return "wifi"
        case .online: return "wifi"
        case .offline: return "wifi.slash"
        case .vpnNoInternet: return "exclamationmark.shield.fill"
        case .captivePortal: return "person.crop.circle.badge.exclamationmark"
        }
    }

    var isHealthy: Bool { self == .online }
    var isProblem: Bool { self == .offline || self == .vpnNoInternet || self == .captivePortal }
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

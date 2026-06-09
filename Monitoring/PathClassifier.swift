import Foundation
import Network

/// Thin wrapper over `NWPathMonitor` that classifies the current path into an interface type,
/// detects VPN/utun presence, and reports it through a callback (on a background queue).
final class PathClassifier: @unchecked Sendable {
    struct PathInfo: Sendable, Equatable {
        var satisfied: Bool
        var interface: ActiveInterface
        var interfaceName: String?
        var isVPN: Bool
        var isExpensive: Bool
        var isConstrained: Bool

        static let unknown = PathInfo(
            satisfied: false, interface: .none, interfaceName: nil,
            isVPN: false, isExpensive: false, isConstrained: false
        )
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.victoradedini.NetCheck.path")
    private let onUpdate: @Sendable (PathInfo) -> Void

    init(onUpdate: @escaping @Sendable (PathInfo) -> Void) {
        self.onUpdate = onUpdate
    }

    func start() {
        monitor.pathUpdateHandler = { [onUpdate] path in
            onUpdate(PathClassifier.classify(path))
        }
        monitor.start(queue: queue)
    }

    func cancel() { monitor.cancel() }

    static func classify(_ path: NWPath) -> PathInfo {
        let vpnPrefixes = ["utun", "ipsec", "ppp", "tap", "tun"]
        let vpnInterface = path.availableInterfaces.first { iface in
            let n = iface.name.lowercased()
            return vpnPrefixes.contains { n.hasPrefix($0) }
        }
        // `.other` is how NWPath surfaces VPN tunnels; corroborate with interface-name prefixes.
        let isVPN = path.usesInterfaceType(.other) || vpnInterface != nil

        let interface: ActiveInterface
        if isVPN {
            interface = .vpn
        } else if path.usesInterfaceType(.wifi) {
            interface = .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = .ethernet
        } else if path.usesInterfaceType(.cellular) {
            interface = .cellular
        } else if !path.availableInterfaces.isEmpty {
            interface = .other
        } else {
            interface = .none
        }

        // For throughput, prefer the tunnel interface when a VPN is active (that's where the
        // user-visible bytes flow); otherwise the primary available interface.
        let name = isVPN
            ? (vpnInterface?.name ?? path.availableInterfaces.first?.name)
            : path.availableInterfaces.first?.name

        return PathInfo(
            satisfied: path.status == .satisfied,
            interface: interface,
            interfaceName: name,
            isVPN: isVPN,
            isExpensive: path.isExpensive,
            isConstrained: path.isConstrained
        )
    }
}

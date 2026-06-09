import Foundation
import Observation

enum ProbeEndpointChoice: String, CaseIterable, Identifiable, Sendable {
    case apple, cloudflare, google
    var id: String { rawValue }
    var label: String {
        switch self {
        case .apple: return "Apple (captive.apple.com)"
        case .cloudflare: return "Cloudflare"
        case .google: return "Google (gstatic)"
        }
    }
}

/// User settings, `@Observable` and backed by `UserDefaults`. SwiftUI binds to it via `@Bindable`.
@MainActor
@Observable
final class Preferences {
    var showSpeedInBar: Bool { didSet { d.set(showSpeedInBar, forKey: Keys.showSpeedInBar) } }
    var iconOnly: Bool { didSet { d.set(iconOnly, forKey: Keys.iconOnly) } }
    var colorIconByState: Bool { didSet { d.set(colorIconByState, forKey: Keys.colorIconByState) } }
    var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: Keys.notificationsEnabled) } }
    var activeProbingEnabled: Bool { didSet { d.set(activeProbingEnabled, forKey: Keys.activeProbingEnabled) } }
    var probeIntervalSeconds: Int { didSet { d.set(probeIntervalSeconds, forKey: Keys.probeIntervalSeconds) } }
    var probeEndpoint: ProbeEndpointChoice { didSet { d.set(probeEndpoint.rawValue, forKey: Keys.probeEndpoint) } }

    private let d = UserDefaults.standard

    private enum Keys {
        static let showSpeedInBar = "showSpeedInBar"
        static let iconOnly = "iconOnly"
        static let colorIconByState = "colorIconByState"
        static let notificationsEnabled = "notificationsEnabled"
        static let activeProbingEnabled = "activeProbingEnabled"
        static let probeIntervalSeconds = "probeIntervalSeconds"
        static let probeEndpoint = "probeEndpoint"
    }

    init() {
        let store = UserDefaults.standard
        showSpeedInBar = (store.object(forKey: Keys.showSpeedInBar) as? Bool) ?? true
        iconOnly = (store.object(forKey: Keys.iconOnly) as? Bool) ?? false
        colorIconByState = (store.object(forKey: Keys.colorIconByState) as? Bool) ?? true
        notificationsEnabled = (store.object(forKey: Keys.notificationsEnabled) as? Bool) ?? true
        activeProbingEnabled = (store.object(forKey: Keys.activeProbingEnabled) as? Bool) ?? true
        probeIntervalSeconds = (store.object(forKey: Keys.probeIntervalSeconds) as? Int) ?? 10
        probeEndpoint = ProbeEndpointChoice(rawValue: store.string(forKey: Keys.probeEndpoint) ?? "") ?? .apple
    }

    /// Two endpoints (rotated) for redundancy — one host's hiccup shouldn't read as "offline".
    func selectedEndpoints() -> [ReachabilityProbe.Endpoint] {
        let apple = ReachabilityProbe.Endpoint(
            url: URL(string: "http://captive.apple.com/hotspot-detect.html")!, kind: .appleCaptive)
        let gstatic = ReachabilityProbe.Endpoint(
            url: URL(string: "https://www.gstatic.com/generate_204")!, kind: .status204)
        let cloudflare = ReachabilityProbe.Endpoint(
            url: URL(string: "https://www.cloudflare.com/cdn-cgi/trace")!, kind: .generic)

        switch probeEndpoint {
        case .apple: return [apple, gstatic]
        case .cloudflare: return [cloudflare, gstatic]
        case .google: return [gstatic, apple]
        }
    }
}

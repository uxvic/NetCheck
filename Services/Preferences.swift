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

/// How much the menu-bar globe is coloured. Lets users who find the speed-tier colours (e.g. amber
/// when slow) distracting calm it down while keeping the offline alert.
enum GlobeColorMode: String, CaseIterable, Identifiable, Sendable {
    case full       // green fast / amber slow / red offline … (full speed tiers)
    case problems   // monochrome normally; colour only for offline / sign-in
    case off        // always monochrome

    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: return "By speed (full colour)"
        case .problems: return "Only when there's a problem"
        case .off: return "Off (monochrome)"
        }
    }
}

/// User settings, `@Observable` and backed by `UserDefaults`. SwiftUI binds to it via `@Bindable`.
@MainActor
@Observable
final class Preferences {
    var showSpeedInBar: Bool { didSet { d.set(showSpeedInBar, forKey: Keys.showSpeedInBar) } }
    var iconOnly: Bool { didSet { d.set(iconOnly, forKey: Keys.iconOnly) } }
    var globeColorMode: GlobeColorMode { didSet { d.set(globeColorMode.rawValue, forKey: Keys.globeColorMode) } }
    var spinningGlobeEnabled: Bool { didSet { d.set(spinningGlobeEnabled, forKey: Keys.spinningGlobeEnabled) } }
    var soundOnChangeEnabled: Bool { didSet { d.set(soundOnChangeEnabled, forKey: Keys.soundOnChangeEnabled) } }
    var notificationsEnabled: Bool { didSet { d.set(notificationsEnabled, forKey: Keys.notificationsEnabled) } }
    var activeProbingEnabled: Bool { didSet { d.set(activeProbingEnabled, forKey: Keys.activeProbingEnabled) } }
    var probeIntervalSeconds: Int { didSet { d.set(probeIntervalSeconds, forKey: Keys.probeIntervalSeconds) } }
    var probeEndpoint: ProbeEndpointChoice { didSet { d.set(probeEndpoint.rawValue, forKey: Keys.probeEndpoint) } }

    private let d = UserDefaults.standard

    private enum Keys {
        static let showSpeedInBar = "showSpeedInBar"
        static let iconOnly = "iconOnly"
        static let colorIconByState = "colorIconByState"   // legacy (migrated to globeColorMode)
        static let globeColorMode = "globeColorMode"
        static let spinningGlobeEnabled = "spinningGlobeEnabled"
        static let soundOnChangeEnabled = "soundOnChangeEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let activeProbingEnabled = "activeProbingEnabled"
        static let probeIntervalSeconds = "probeIntervalSeconds"
        static let probeEndpoint = "probeEndpoint"
    }

    init() {
        let store = UserDefaults.standard
        // Default to glance-only: the spinning globe shows status; the number lives one click away.
        showSpeedInBar = (store.object(forKey: Keys.showSpeedInBar) as? Bool) ?? false
        iconOnly = (store.object(forKey: Keys.iconOnly) as? Bool) ?? false
        if let raw = store.string(forKey: Keys.globeColorMode), let mode = GlobeColorMode(rawValue: raw) {
            globeColorMode = mode
        } else {
            // Migrate the old on/off boolean: off → .off, otherwise full colour.
            let legacyOn = (store.object(forKey: Keys.colorIconByState) as? Bool) ?? true
            globeColorMode = legacyOn ? .full : .off
        }
        spinningGlobeEnabled = (store.object(forKey: Keys.spinningGlobeEnabled) as? Bool) ?? true
        soundOnChangeEnabled = (store.object(forKey: Keys.soundOnChangeEnabled) as? Bool) ?? true
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

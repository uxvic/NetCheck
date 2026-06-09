import Foundation
import Observation

/// The single source of truth. `@MainActor @Observable` so SwiftUI views and the status item bind
/// to it directly. It orchestrates the three background workers (sampler, probe, path classifier),
/// applies the 2-strike rule + state machine, and fires notifications on transitions.
@MainActor
@Observable
final class NetworkMonitor {
    private(set) var snapshot = NetworkSnapshot()
    private(set) var history: [RateSample] = []

    struct RateSample: Identifiable, Equatable {
        let id: Int
        let down: Double
        let up: Double
    }

    private let maxHistory = 60
    private var sampleCounter = 0

    private let sampler = ThroughputSampler()
    private let probe = ReachabilityProbe()
    private let ipResolver = PublicIPResolver()
    private var classifier: PathClassifier?

    private let prefs: Preferences
    private let notifier: Notifier

    private var tickTask: Task<Void, Never>?
    private var probeTask: Task<Void, Never>?

    private var pathInfo = PathClassifier.PathInfo.unknown
    private var consecutiveFailures = 0
    private var lastInterfaceName: String?
    private var running = false

    init(prefs: Preferences, notifier: Notifier) {
        self.prefs = prefs
        self.notifier = notifier
    }

    func start() {
        guard !running else { return }
        running = true
        let classifier = PathClassifier { [weak self] info in
            Task { @MainActor in self?.handlePathUpdate(info) }
        }
        self.classifier = classifier
        classifier.start()
        startTickLoop()
        startProbeLoop()
    }

    /// Suspend on display sleep.
    func pause() {
        tickTask?.cancel(); tickTask = nil
        probeTask?.cancel(); probeTask = nil
    }

    /// Resume on wake — discard the stale byte-counter baseline and probe immediately.
    func resume() {
        Task { await sampler.reset() }
        lastInterfaceName = nil
        startTickLoop()
        startProbeLoop()
    }

    // MARK: - Throughput (1 Hz, local, cheap)

    private func startTickLoop() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tick() async {
        let name = pathInfo.satisfied ? pathInfo.interfaceName : nil
        if name != lastInterfaceName {
            await sampler.reset()
            lastInterfaceName = name
        }
        let rate = await sampler.tick(interfaceName: name)
        let a = 0.4   // EMA smoothing so the bar text doesn't jitter
        let down = a * rate.down + (1 - a) * snapshot.downBytesPerSec
        let up = a * rate.up + (1 - a) * snapshot.upBytesPerSec
        snapshot.downBytesPerSec = down < 1 ? 0 : down
        snapshot.upBytesPerSec = up < 1 ? 0 : up

        sampleCounter += 1
        history.append(RateSample(id: sampleCounter, down: snapshot.downBytesPerSec, up: snapshot.upBytesPerSec))
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
    }

    // MARK: - Reachability probe (slower cadence + on path change)

    private func startProbeLoop() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.runProbe()
                let interval = self?.currentInterval() ?? 10
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func currentInterval() -> Double {
        let base = Double(max(5, prefs.probeIntervalSeconds))
        return PowerSource.isOnBattery() ? max(base, 25) : base
    }

    /// Force an immediate probe (on path change, or from the UI).
    func probeNow() {
        Task { await runProbe() }
    }

    private func runProbe() async {
        guard prefs.activeProbingEnabled else {
            setState(pathInfo.satisfied ? .online : .offline, latency: nil)
            return
        }
        guard pathInfo.satisfied else {
            consecutiveFailures = 0
            setState(.offline, latency: nil)
            return
        }

        var reachable = false
        var captive = false
        var latency: Double?
        for endpoint in prefs.selectedEndpoints() {
            let result = await probe.probe(endpoint)
            if result.captivePortal { captive = true }
            if result.reachable {
                reachable = true
                latency = result.latencyMs
                break
            }
        }

        if reachable {
            consecutiveFailures = 0
            setState(.online, latency: latency)
        } else if captive {
            consecutiveFailures = 0
            setState(.captivePortal, latency: nil)
        } else {
            // 2-strike rule: require two consecutive failures before declaring down (kills false alarms).
            consecutiveFailures += 1
            if consecutiveFailures >= 2 {
                setState(pathInfo.isVPN ? .vpnNoInternet : .offline, latency: nil)
            }
        }
    }

    // MARK: - Path updates

    private func handlePathUpdate(_ info: PathClassifier.PathInfo) {
        pathInfo = info
        snapshot.interface = info.interface
        snapshot.interfaceName = info.interfaceName
        snapshot.isVPNActive = info.isVPN
        snapshot.isExpensive = info.isExpensive
        if !info.satisfied {
            consecutiveFailures = 0
            setState(.offline, latency: nil)
        }
        probeNow()   // instant re-check whenever the path changes (VPN connect/drop, Wi-Fi switch)
    }

    // MARK: - State machine + notifications

    private func setState(_ newState: ConnectivityState, latency: Double?) {
        snapshot.interface = pathInfo.interface
        snapshot.interfaceName = pathInfo.interfaceName
        snapshot.isVPNActive = pathInfo.isVPN
        snapshot.isExpensive = pathInfo.isExpensive
        snapshot.latencyMs = latency

        guard newState != snapshot.state else { return }
        let old = snapshot.state
        snapshot.state = newState
        notifyTransition(from: old, to: newState)
    }

    private func notifyTransition(from old: ConnectivityState, to new: ConnectivityState) {
        guard prefs.notificationsEnabled, old != .checking else { return }
        switch new {
        case .offline:
            notifier.notify(title: "Internet disconnected", body: "No connection could be reached.")
        case .vpnNoInternet:
            notifier.notify(title: "VPN up, but no internet",
                            body: "Your VPN is connected but traffic isn’t reaching the internet.")
        case .captivePortal:
            notifier.notify(title: "Sign-in required",
                            body: "This network needs you to sign in (captive portal).")
        case .online:
            if old.isProblem {
                notifier.notify(title: "Back online", body: "Your internet connection is working again.")
            }
        case .checking:
            break
        }
    }

    // MARK: - Public IP (on demand)

    func refreshPublicIP() {
        Task { [weak self] in
            let ip = await self?.ipResolver.fetch()
            self?.snapshot.publicIP = ip
        }
    }
}

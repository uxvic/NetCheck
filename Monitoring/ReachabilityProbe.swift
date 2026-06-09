import Foundation

/// Actively verifies that the internet is *actually* reachable (not just that an interface is up).
/// This is what catches "VPN connected but internet dead" and captive portals.
///
/// Uses an **ephemeral** session with `waitsForConnectivity = false` and caching disabled, so a dead
/// link fails fast instead of being masked by URLSession waiting or returning a cached response.
actor ReachabilityProbe {
    enum Kind: Sendable {
        case appleCaptive   // captive.apple.com — 200 + body "Success", else captive portal
        case status204      // generate_204-style — any 2xx means reachable
        case generic        // any 2xx/3xx means reachable
    }

    struct Endpoint: Sendable, Equatable {
        let url: URL
        let kind: Kind
    }

    struct Result: Sendable {
        let reachable: Bool
        let captivePortal: Bool
        let latencyMs: Double?
    }

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false                              // must fail fast — do NOT wait
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.urlCache = nil
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 5
        session = URLSession(configuration: cfg)
    }

    func probe(_ endpoint: Endpoint) async -> Result {
        var req = URLRequest(url: endpoint.url)
        req.httpMethod = (endpoint.kind == .appleCaptive) ? "GET" : "HEAD"
        req.setValue("NetCheck/1.0", forHTTPHeaderField: "User-Agent")

        let startNs = DispatchTime.now().uptimeNanoseconds
        do {
            let (data, response) = try await session.data(for: req)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - startNs) / 1_000_000.0
            guard let http = response as? HTTPURLResponse else {
                return Result(reachable: false, captivePortal: false, latencyMs: nil)
            }
            switch endpoint.kind {
            case .appleCaptive:
                if http.statusCode == 200 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    if body.localizedCaseInsensitiveContains("success") {
                        return Result(reachable: true, captivePortal: false, latencyMs: ms)
                    }
                    return Result(reachable: false, captivePortal: true, latencyMs: ms)
                }
                return Result(reachable: false, captivePortal: false, latencyMs: ms)
            case .status204:
                return Result(reachable: (200...299).contains(http.statusCode), captivePortal: false, latencyMs: ms)
            case .generic:
                return Result(reachable: (200...399).contains(http.statusCode), captivePortal: false, latencyMs: ms)
            }
        } catch {
            return Result(reachable: false, captivePortal: false, latencyMs: nil)
        }
    }
}

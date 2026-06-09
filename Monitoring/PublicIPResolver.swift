import Foundation

/// Fetches the public IP address. Called **on demand only** (never on a loop) — repeatedly
/// resolving the public IP is a privacy/tracking concern and wasteful.
actor PublicIPResolver {
    func fetch() async -> String? {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.waitsForConnectivity = false
        cfg.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: cfg)

        guard let url = URL(string: "https://api.ipify.org") else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let ip = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !ip.isEmpty else { return nil }
            return ip
        } catch {
            return nil
        }
    }
}

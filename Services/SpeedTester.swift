import Foundation

/// Measures real download bandwidth with a short fetch from Cloudflare's public speed endpoint
/// (`speed.cloudflare.com/__down`), which streams a requested number of zero bytes. Used to answer
/// "what speed tier am I on?" when nothing is actively downloading.
actor SpeedTester {
    enum TestError: Error { case badResponse }

    /// Returns measured download speed in Mbps (megabits/sec). Throws on failure.
    func measure(bytes: Int = 25_000_000) async throws -> Double {
        let url = URL(string: "https://speed.cloudflare.com/__down?bytes=\(bytes)")!
        var req = URLRequest(url: url)
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.timeoutInterval = 30

        let start = Date()
        let (data, response) = try await URLSession.shared.data(for: req)
        let elapsed = Date().timeIntervalSince(start)

        guard (response as? HTTPURLResponse)?.statusCode == 200, elapsed > 0.01, !data.isEmpty else {
            throw TestError.badResponse
        }
        return Double(data.count) * 8 / elapsed / 1_000_000
    }
}

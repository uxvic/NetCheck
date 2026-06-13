import AppKit

/// Formats throughput for display.
enum BarRenderer {
    /// Compact form for the menu bar (no "/s" — the arrows imply rate; saves precious bar width).
    static func format(_ bytesPerSec: Double) -> String {
        let b = max(0, bytesPerSec)
        if b < 1000 { return String(format: "%.0fB", b) }
        let kb = b / 1024
        if kb < 1000 { return String(format: "%.0fK", kb) }
        let mb = kb / 1024
        if mb < 10 { return String(format: "%.1fM", mb) }
        return String(format: "%.0fM", mb)
    }

    static func attributedSpeed(down: Double, up: Double) -> NSAttributedString {
        // Fully monospaced (not just digits) so unit letters and the decimal point are fixed
        // width too — combined with the padding below, the bar width never changes.
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let text = "↓\(pad(format(down))) ↑\(pad(format(up)))"
        return NSAttributedString(string: text, attributes: [.font: font])
    }

    /// Right-justify into a fixed 4-char field so the menu bar title is always the same length
    /// (units stay put; digits grow leftward into reserved space — an "odometer" feel).
    private static func pad(_ s: String) -> String {
        s.count >= 4 ? s : String(repeating: " ", count: 4 - s.count) + s
    }

    /// Live download/upload as megabits per second (the unit ISPs and the user think in).
    static func mbps(_ bytesPerSec: Double) -> Double { max(0, bytesPerSec) * 8 / 1_000_000 }

    /// Mbps formatted for the panel headline: one decimal under 10, whole numbers above.
    static func formatMbps(_ bytesPerSec: Double) -> String {
        let m = mbps(bytesPerSec)
        return m < 10 ? String(format: "%.1f", m) : String(format: "%.0f", m)
    }

    /// Verbose form for the detail panel, e.g. "2.41 MB/s".
    static func formatVerbose(_ bytesPerSec: Double) -> String {
        let b = max(0, bytesPerSec)
        if b < 1024 { return String(format: "%.0f B/s", b) }
        let kb = b / 1024
        if kb < 1024 { return String(format: "%.1f KB/s", kb) }
        let mb = kb / 1024
        return String(format: "%.2f MB/s", mb)
    }
}

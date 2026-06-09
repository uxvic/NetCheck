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
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let text = "↓\(format(down)) ↑\(format(up))"
        return NSAttributedString(string: text, attributes: [.font: font])
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

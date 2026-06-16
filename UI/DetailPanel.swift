import SwiftUI

/// The click-through popover. A dark gradient (black at top, easing down to the card) holds the
/// legend + details in light text — the Siri-summary look from the reference — and a status-coloured
/// gradient card anchors the bottom. The card names your speed tier (Fast / Normal / Slow); the
/// "Test speed" button measures real bandwidth so the tier is meaningful even when idle.
struct DetailPanel: View {
    let monitor: NetworkMonitor
    let prefs: Preferences
    let actions: PanelActions
    @State private var dataPeriod: DataPeriod = .today

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 12) {
            legend(current: displayedTier(snap))
            Divider()
            details(snap)
            SparklineView(samples: monitor.history).frame(height: 40)
            footer
            hero(snap)   // gradient card anchors the bottom
        }
        .padding(14)
        .frame(width: 320)
        .background(
            // Black at the top, easing down to where the card begins — the reference's dark sheet.
            LinearGradient(stops: [
                .init(color: Color.black.opacity(0.96), location: 0.0),
                .init(color: Color.black.opacity(0.82), location: 0.55),
                .init(color: Color.black.opacity(0.55), location: 1.0)
            ], startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Speed tier helpers

    /// The Mbps figure the card headlines: a recent speed-test result if we have one, else the live rate.
    private func shownMbps(_ snap: NetworkSnapshot) -> Double {
        if let m = monitor.lastTestMbps, let at = monitor.lastTestAt, Date().timeIntervalSince(at) < 300 {
            return m
        }
        return BarRenderer.mbps(snap.downBytesPerSec)
    }

    private func isShowingTested() -> Bool {
        guard monitor.snapshot.state == .online, let at = monitor.lastTestAt else { return false }
        return Date().timeIntervalSince(at) < 300
    }

    /// The single tier the whole UI shows — globe colour AND card — computed in one place on the
    /// monitor so the menu-bar globe and the panel can never disagree.
    private func displayedTier(_ snap: NetworkSnapshot) -> RateTier {
        monitor.displayedRateTier()
    }

    // MARK: - Hero (the gradient card, bottom-anchored)

    @ViewBuilder private func hero(_ snap: NetworkSnapshot) -> some View {
        let dt = displayedTier(snap)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(heroTitle(snap), systemImage: "globe")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                testButton
            }

            if monitor.isSpeedTesting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(.white)
                    Text("Measuring your speed…").font(.system(size: 17, weight: .medium))
                }
                .frame(height: 40, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(fmt(shownMbps(snap)))
                        .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("Mbps").font(.system(size: 15)).opacity(0.92)
                    Spacer()
                    // Status word (Idle / Fast / …) — a plain text label, not a pill,
                    // so it doesn't read as a tappable button next to the real one.
                    Text(dt.label)
                        .font(.system(size: 15, weight: .semibold))
                        .opacity(0.95)
                }
            }

            HStack {
                Label("\(fmt(BarRenderer.mbps(snap.upBytesPerSec))) Mbps up", systemImage: "arrow.up")
                    .font(.system(size: 12)).opacity(0.92)
                Spacer()
                Text(noteLine(snap)).font(.system(size: 12)).opacity(0.85).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(
            LinearGradient(colors: heroColors(dt), startPoint: .bottom, endPoint: .top),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }

    private var testButton: some View {
        Button { monitor.runSpeedTest() } label: {
            HStack(spacing: 4) {
                Image(systemName: monitor.isSpeedTesting ? "hourglass" : "gauge.high")
                Text(monitor.isSpeedTesting ? "Testing…" : "Test speed")
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(.white.opacity(0.24), in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(monitor.isSpeedTesting)
    }

    private func noteLine(_ snap: NetworkSnapshot) -> String {
        var parts: [String] = []
        if isShowingTested(), let at = monitor.lastTestAt { parts.append("tested \(ago(at))") }
        else { parts.append("live now") }
        if let ms = snap.latencyMs { parts.append("\(Int(ms)) ms") }
        return parts.joined(separator: " · ")
    }

    private func fmt(_ m: Double) -> String { m < 10 ? String(format: "%.1f", m) : String(format: "%.0f", m) }

    private func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        return s < 60 ? "\(max(1, s))s ago" : "\(s / 60)m ago"
    }

    private func heroTitle(_ snap: NetworkSnapshot) -> String {
        let iface = snap.interface == .none ? "" : "\(snap.interface.label) · "
        return iface + snap.state.title
    }

    /// Card gradient by **speed tier**: fast/normal/idle → green, slow/sign-in → amber, offline → red,
    /// checking → slate. `[bottom, top]`; both shades are dark enough for white text to clear WCAG AA
    /// (white-on-each measures ≥ ~5:1).
    private func heroColors(_ tier: RateTier) -> [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b) }
        switch tier {
        case .fast, .normal, .idle:  return [c(0.078, 0.478, 0.271), c(0.043, 0.322, 0.188)] // deep emerald
        case .slow, .signIn:         return [c(0.706, 0.325, 0.035), c(0.541, 0.239, 0.024)] // deep amber
        case .checking:              return [c(0.337, 0.384, 0.439), c(0.227, 0.263, 0.310)] // slate
        case .offline:               return [c(0.776, 0.180, 0.180), c(0.561, 0.114, 0.114)] // deep red
        }
    }

    // MARK: - Legend (how the globe is judged)

    @ViewBuilder private func legend(current: RateTier) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How the globe is judged · spin = live data, colour = tier")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            legendRow(.fast,    "≥ 200 Mbps",    current: current)
            legendRow(.normal,  "50 – 200 Mbps", current: current)
            legendRow(.slow,    "< 50 Mbps",     current: current)
            legendRow(.offline, "no connection", current: current)
        }
    }

    private func legendRow(_ tier: RateTier, _ threshold: String, current: RateTier) -> some View {
        HStack(spacing: 8) {
            Circle().fill(legendColor(tier)).frame(width: 9, height: 9)
            Text(tier.label).font(.system(size: 13))
            Spacer()
            Text(threshold).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background {
            if current == tier {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
            }
        }
    }

    private func legendColor(_ tier: RateTier) -> Color {
        switch tier {
        case .fast: return .green
        case .slow: return .orange
        case .offline: return .red
        default: return .gray
        }
    }

    // MARK: - Details + footer

    @ViewBuilder private func details(_ snap: NetworkSnapshot) -> some View {
        VStack(spacing: 6) {
            detailRow("Interface", snap.interface.label + (snap.interfaceName.map { " (\($0))" } ?? ""))
            HStack {
                Text("Public IP").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(snap.publicIP ?? "—").font(.caption).monospacedDigit()
                Button { actions.refreshPublicIP() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
            dataUsedRow()
            if snap.isExpensive {
                detailRow("Network", "Metered / Expensive")
            }
        }
    }

    private func detailRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption)
        }
    }

    // MARK: - Data used (one row + period switch)

    private enum DataPeriod: String, CaseIterable, Identifiable {
        case today, week, month, year
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .week:  return "This week"
            case .month: return "This month"
            case .year:  return "This year"
            }
        }
    }

    private func usageFor(_ p: DataPeriod) -> DataUsageTracker.Usage {
        switch p {
        case .today: return monitor.usage.today
        case .week:  return monitor.usage.week
        case .month: return monitor.usage.month
        case .year:  return monitor.usage.year
        }
    }

    /// A single line, like Interface / Public IP — with a compact menu to switch the period.
    private func dataUsedRow() -> some View {
        HStack(spacing: 6) {
            Text("Data used").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $dataPeriod) {
                ForEach(DataPeriod.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize().controlSize(.small)
            Spacer()
            Text(fmtBytes(usageFor(dataPeriod).total)).font(.caption).monospacedDigit()
        }
        .help("Traffic through the active interface (internet + local network) measured while NetCheck is running; resets when this Mac restarts. macOS doesn’t expose a true internet-only or per-app total.")
    }

    private func fmtBytes(_ b: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(b); var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(b) B" }
        return v < 10 ? String(format: "%.1f %@", v, units[i]) : String(format: "%.0f %@", v, units[i])
    }

    @ViewBuilder private var footer: some View {
        HStack {
            Button("Settings…") { actions.openSettings() }.panelButtonStyle()
            Button("Updates") { actions.checkForUpdates() }.panelButtonStyle()
            Spacer()
            Button("Quit") { actions.quit() }.panelButtonStyle()
        }
        .font(.caption)
    }
}

private extension View {
    /// Liquid Glass buttons on macOS 26+, a graceful bordered fallback below.
    @ViewBuilder func panelButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

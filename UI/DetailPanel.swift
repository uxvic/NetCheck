import SwiftUI

/// The click-through popover. A dark gradient (black at top, easing down to the card) holds the
/// legend + details in light text — the Siri-summary look from the reference — and a status-coloured
/// gradient card anchors the bottom. The card names your speed tier (Fast / Normal / Slow); the
/// "Test speed" button measures real bandwidth so the tier is meaningful even when idle.
struct DetailPanel: View {
    let monitor: NetworkMonitor
    let prefs: Preferences
    let actions: PanelActions

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 12) {
            legend(current: highlightTier(snap))
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
        guard let at = monitor.lastTestAt else { return false }
        return Date().timeIntervalSince(at) < 300
    }

    /// Tier from a raw Mbps figure (no idle band — used for tested results).
    private func tier(forMbps m: Double) -> RateTier {
        if m >= RateTier.fastFloorMbps { return .fast }
        if m >= RateTier.slowCeilingMbps { return .normal }
        if m >= RateTier.idleFloorMbps { return .slow }
        return .idle
    }

    /// Which legend row to highlight: the tested tier if recent, else the live rate tier.
    private func highlightTier(_ snap: NetworkSnapshot) -> RateTier {
        isShowingTested() ? tier(forMbps: monitor.lastTestMbps ?? 0)
                          : snap.state.rateTier(downBytesPerSec: snap.downBytesPerSec)
    }

    /// The category label shown on the card: state problems win, else the (tested or live) tier.
    private func categoryLabel(_ snap: NetworkSnapshot) -> String {
        switch snap.state {
        case .offline, .vpnNoInternet: return "Offline"
        case .captivePortal: return "Sign-in"
        default:
            return isShowingTested() ? tier(forMbps: monitor.lastTestMbps ?? 0).label
                                     : snap.state.rateTier(downBytesPerSec: snap.downBytesPerSec).label
        }
    }

    // MARK: - Hero (the gradient card, bottom-anchored)

    @ViewBuilder private func hero(_ snap: NetworkSnapshot) -> some View {
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
                    Text(categoryLabel(snap))
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 4)
                        .background(.white.opacity(0.24), in: Capsule())
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
            LinearGradient(colors: heroColors(snap.state), startPoint: .bottom, endPoint: .top),
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

    /// `[bottom, top]` — both shades dark enough for white text to clear AA contrast.
    private func heroColors(_ state: ConnectivityState) -> [Color] {
        func c(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(.sRGB, red: r, green: g, blue: b) }
        switch state {
        case .online:                   return [c(0.078, 0.478, 0.271), c(0.043, 0.322, 0.188)] // deep emerald
        case .checking:                 return [c(0.337, 0.384, 0.439), c(0.227, 0.263, 0.310)] // slate
        case .captivePortal:            return [c(0.706, 0.325, 0.035), c(0.541, 0.239, 0.024)] // deep amber
        case .offline, .vpnNoInternet:  return [c(0.776, 0.180, 0.180), c(0.561, 0.114, 0.114)] // deep red
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

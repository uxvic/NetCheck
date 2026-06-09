import SwiftUI

/// The click-through popover: current state, live rates, sparkline, and connection details.
struct DetailPanel: View {
    let monitor: NetworkMonitor
    let prefs: Preferences
    let actions: PanelActions

    var body: some View {
        let snap = monitor.snapshot
        VStack(alignment: .leading, spacing: 12) {
            header(snap)
            Divider()
            rates(snap)
            SparklineView(samples: monitor.history).frame(height: 44)
            Divider()
            details(snap)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    @ViewBuilder private func header(_ snap: NetworkSnapshot) -> some View {
        HStack(spacing: 8) {
            Image(systemName: snap.state.symbolName)
                .foregroundStyle(statusColor(snap.state))
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(snap.state.title).font(.headline)
                Text(subtitle(snap)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func subtitle(_ snap: NetworkSnapshot) -> String {
        switch snap.state {
        case .vpnNoInternet: return "VPN is up but the internet is unreachable"
        case .captivePortal: return "Sign in to this network to continue"
        case .offline: return "No route to the internet"
        case .checking: return "Verifying connection…"
        case .online: return snap.isVPNActive ? "Connected over VPN" : "Connected"
        }
    }

    @ViewBuilder private func rates(_ snap: NetworkSnapshot) -> some View {
        HStack {
            rateBox("arrow.down", "Download", BarRenderer.formatVerbose(snap.downBytesPerSec))
            Divider().frame(height: 30)
            rateBox("arrow.up", "Upload", BarRenderer.formatVerbose(snap.upBytesPerSec))
        }
    }

    private func rateBox(_ symbol: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.system(.body, design: .rounded)).monospacedDigit()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func details(_ snap: NetworkSnapshot) -> some View {
        VStack(spacing: 6) {
            detailRow("Interface", snap.interface.label + (snap.interfaceName.map { " (\($0))" } ?? ""))
            detailRow("Latency", snap.latencyMs.map { "\(Int($0)) ms" } ?? "—")
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
        VStack(spacing: 6) {
            HStack {
                Button("Settings…") { actions.openSettings() }
                Spacer()
                Button("Check for Updates") { actions.checkForUpdates() }
            }
            HStack {
                Spacer()
                Button("Quit NetCheck") { actions.quit() }.foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func statusColor(_ s: ConnectivityState) -> Color {
        switch s {
        case .online: return .green
        case .checking: return .gray
        case .captivePortal: return .orange
        case .offline, .vpnNoInternet: return .red
        }
    }
}

import SwiftUI

/// Settings window — display customization, monitoring, alerts/startup, updates.
struct SettingsView: View {
    @Bindable var prefs: Preferences
    let updater: UpdaterController

    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show speed in the menu bar", isOn: $prefs.showSpeedInBar)
                Toggle("Icon only (hide speed text)", isOn: $prefs.iconOnly)
                Toggle("Color the icon by status", isOn: $prefs.colorIconByState)
            }

            Section("Monitoring") {
                Toggle("Actively verify internet (recommended)", isOn: $prefs.activeProbingEnabled)
                Picker("Probe endpoint", selection: $prefs.probeEndpoint) {
                    ForEach(ProbeEndpointChoice.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Check every \(prefs.probeIntervalSeconds)s",
                        value: $prefs.probeIntervalSeconds, in: 5...120, step: 5)
                Text("Active verification catches the VPN-connected-but-no-internet case. Turn off to rely on interface state only (more private, less accurate).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Alerts & Startup") {
                Toggle("Notify on disconnect / reconnect", isOn: $prefs.notificationsEnabled)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        LoginItem.setEnabled(newValue)
                        launchAtLogin = LoginItem.isEnabled
                    }
            }

            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }))
                Button("Check Now") { updater.checkForUpdates() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 520)
    }
}

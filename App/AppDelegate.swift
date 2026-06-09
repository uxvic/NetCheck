import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var prefs: Preferences!
    private var notifier: Notifier!
    private var monitor: NetworkMonitor!
    private var updater: UpdaterController!
    private var statusController: StatusItemController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        prefs = Preferences()
        notifier = Notifier()
        notifier.requestAuthorization()
        updater = UpdaterController()
        monitor = NetworkMonitor(prefs: prefs, notifier: notifier)

        let actions = PanelActions(
            openSettings: { [weak self] in self?.openSettings() },
            checkForUpdates: { [weak self] in self?.updater.checkForUpdates() },
            refreshPublicIP: { [weak self] in self?.monitor.refreshPublicIP() },
            quit: { NSApp.terminate(nil) }
        )

        statusController = StatusItemController(
            monitor: monitor, prefs: prefs, updater: updater, actions: actions)
        monitor.start()
        monitor.refreshPublicIP()
        registerSleepWake()
    }

    private func openSettings() {
        if settingsWindow == nil {
            let hosting = NSHostingController(rootView: SettingsView(prefs: prefs, updater: updater))
            let window = NSWindow(contentViewController: hosting)
            window.title = "NetCheck Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func registerSleepWake() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.monitor.pause() }
        }
        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.monitor.resume() }
        }
    }
}

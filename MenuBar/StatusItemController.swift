import AppKit
import Observation

/// Owns the `NSStatusItem`. Left-click → detail popover; right-click (or ⌃-click) → menu.
/// Re-renders the bar whenever observed state changes via Observation tracking.
@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let monitor: NetworkMonitor
    private let prefs: Preferences
    private let actions: PanelActions
    private let panel: PanelHostController
    private var menu: NSMenu!

    init(monitor: NetworkMonitor, prefs: Preferences, updater: UpdaterController, actions: PanelActions) {
        self.monitor = monitor
        self.prefs = prefs
        self.actions = actions
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = PanelHostController(monitor: monitor, prefs: prefs, actions: actions)

        configureButton()
        buildMenu()
        startObserving()
        render()
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageLeading
    }

    @objc private func handleClick() {
        let event = NSApp.currentEvent
        let isRight = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if isRight {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil   // detach so the next left-click hits our action again
        } else if let button = statusItem.button {
            panel.toggle(relativeTo: button)
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Show Details", action: #selector(showDetails), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NetCheck", action: #selector(quit), keyEquivalent: "q").target = self
        self.menu = menu
    }

    @objc private func showDetails() { if let b = statusItem.button { panel.show(relativeTo: b) } }
    @objc private func checkUpdates() { actions.checkForUpdates() }
    @objc private func openSettings() { actions.openSettings() }
    @objc private func quit() { actions.quit() }

    /// Manual `@Observable` tracking: re-register after each fire to keep observing.
    private func startObserving() {
        func track() {
            withObservationTracking {
                _ = monitor.snapshot
                _ = prefs.showSpeedInBar
                _ = prefs.iconOnly
                _ = prefs.colorIconByState
            } onChange: { [weak self] in
                Task { @MainActor in
                    self?.render()
                    track()
                }
            }
        }
        track()
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let snap = monitor.snapshot

        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        let image = NSImage(systemSymbolName: snap.state.symbolName, accessibilityDescription: snap.state.title)?
            .withSymbolConfiguration(config)
        if prefs.colorIconByState {
            image?.isTemplate = false
            button.contentTintColor = color(for: snap.state)
        } else {
            image?.isTemplate = true
            button.contentTintColor = nil
        }
        button.image = image

        if prefs.iconOnly || !prefs.showSpeedInBar {
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        } else {
            button.imagePosition = .imageLeading
            button.attributedTitle = BarRenderer.attributedSpeed(down: snap.downBytesPerSec, up: snap.upBytesPerSec)
        }
        button.toolTip = tooltip(for: snap)
    }

    private func color(for state: ConnectivityState) -> NSColor {
        switch state {
        case .online: return .systemGreen
        case .checking: return .secondaryLabelColor
        case .captivePortal: return .systemOrange
        case .offline, .vpnNoInternet: return .systemRed
        }
    }

    private func tooltip(for snap: NetworkSnapshot) -> String {
        var parts = [snap.state.title]
        if snap.interface != .none { parts.append(snap.interface.label) }
        if let ms = snap.latencyMs { parts.append("\(Int(ms)) ms") }
        return parts.joined(separator: " · ")
    }
}

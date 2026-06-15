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

    /// The live animated globe shown in the default (glance) mode.
    private let globe = SpinningGlobe()
    /// Fixed width for globe-only mode so tier/glyph changes can't nudge neighbours.
    private let globeLength: CGFloat = 28

    /// Fixed bar width so neither the item nor its neighbours ever move. Measured from the widest
    /// realistic title plus a generous icon allowance (surplus shows as constant right-side
    /// padding, which never shifts; erring generous avoids clipping fast/gigabit values).
    private lazy var fixedBarLength: CGFloat = {
        let widest = BarRenderer.attributedSpeed(down: 999 * 1024 * 1024, up: 999 * 1024 * 1024)
        let iconAllowance: CGFloat = 24   // SF Symbol footprint at pointSize 13
        let spacing: CGFloat = 8          // image–title gap + edge padding, generous
        return ceil(widest.size().width) + iconAllowance + spacing
    }()

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
        button.imagePosition = .imageOnly
        statusItem.length = globeLength   // give the button a real width before the globe attaches
        globe.attach(to: button)
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
                _ = prefs.globeColorMode
                _ = prefs.spinningGlobeEnabled
                _ = monitor.lastTestMbps
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
        let rt = monitor.displayedRateTier()   // tested-if-recent, else live — matches the panel card
        let displayTier = colorTier(for: rt)
        let colorize = prefs.globeColorMode != .off
        let showText = prefs.showSpeedInBar && !prefs.iconOnly

        if showText {
            // Opt-in: static globe + fixed-width number (the constant-width path keeps it jitter-free).
            globe.setHidden(true)
            statusItem.length = fixedBarLength
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            let image = NSImage(systemSymbolName: "globe", accessibilityDescription: snap.state.title)?
                .withSymbolConfiguration(config)
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = colorize ? nsColor(for: displayTier) : nil
            button.imagePosition = .imageLeading
            button.attributedTitle = BarRenderer.attributedSpeed(down: snap.downBytesPerSec, up: snap.upBytesPerSec)
        } else {
            // Default: the live spinning globe carries everything; the number lives one click away.
            button.image = nil
            button.contentTintColor = nil
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            statusItem.length = globeLength
            globe.relayout()
            globe.setHidden(false)
            let spin = prefs.spinningGlobeEnabled && rt.spins
            globe.update(tier: displayTier, colorize: colorize,
                         spin: spin, bytesPerSec: snap.downBytesPerSec)
        }
        button.toolTip = tooltip(for: snap)
    }

    /// Resolve the colour tier under the user's colour-mode preference: full tiers, problems-only
    /// (slow/fast stay neutral, offline/sign-in keep their colour), or off (always neutral).
    private func colorTier(for rt: RateTier) -> StatusTier {
        switch prefs.globeColorMode {
        case .off: return .neutral
        case .problems: return rt.isProblem ? rt.colorTier : .neutral
        case .full: return rt.colorTier
        }
    }

    private func nsColor(for tier: StatusTier) -> NSColor {
        switch tier {
        case .good: return .systemGreen
        case .neutral: return .labelColor
        case .warn: return .systemOrange
        case .bad: return .systemRed
        }
    }

    private func tooltip(for snap: NetworkSnapshot) -> String {
        var parts = [snap.state.title]
        if snap.interface != .none { parts.append(snap.interface.label) }
        if let ms = snap.latencyMs { parts.append("\(Int(ms)) ms") }
        return parts.joined(separator: " · ")
    }
}

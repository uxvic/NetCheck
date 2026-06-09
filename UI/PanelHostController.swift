import AppKit
import SwiftUI

/// Hosts the SwiftUI `DetailPanel` in a transient `NSPopover` anchored to the status item.
@MainActor
final class PanelHostController {
    private let popover = NSPopover()

    init(monitor: NetworkMonitor, prefs: Preferences, actions: PanelActions) {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 380)
        popover.contentViewController = NSHostingController(
            rootView: DetailPanel(monitor: monitor, prefs: prefs, actions: actions))
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show(relativeTo: button)
        }
    }

    func show(relativeTo button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
}

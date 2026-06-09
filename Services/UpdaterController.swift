import Foundation

// Guarded so the project still compiles if the Sparkle package isn't resolved.
#if canImport(Sparkle)
import Sparkle

/// Wraps Sparkle's standard updater. The feed URL + public EdDSA key live in Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`). Auto-update works WITHOUT an Apple Developer account —
/// Sparkle verifies via its own signature and strips quarantine on install.
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
}

#else
import AppKit

/// Fallback when Sparkle isn't available (e.g. dependency removed).
@MainActor
final class UpdaterController {
    init() {}
    func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Updates unavailable"
        alert.informativeText = "This build was compiled without the Sparkle update framework."
        alert.runModal()
    }
    var automaticallyChecksForUpdates: Bool = false
    var canCheckForUpdates: Bool { false }
}
#endif

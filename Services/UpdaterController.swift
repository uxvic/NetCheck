import Foundation

// Guarded so the project still compiles if the Sparkle package isn't resolved.
#if canImport(Sparkle)
import Sparkle
import AppKit

/// Wraps Sparkle's standard updater. The feed URL + public EdDSA key live in Info.plist
/// (`SUFeedURL`, `SUPublicEDKey`). Auto-update works WITHOUT an Apple Developer account —
/// Sparkle verifies via its own signature and strips quarantine on install.
///
/// The updater only *starts* once a real `SUPublicEDKey` is set, so the app runs cleanly during
/// development (before you've generated Sparkle keys in M4).
@MainActor
final class UpdaterController {
    private let controller: SPUStandardUpdaterController
    private let started: Bool

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        if Self.hasValidFeedKey {
            controller.startUpdater()
            started = true
        } else {
            started = false
            NSLog("NetCheck: Sparkle not started — set SUPublicEDKey + SUFeedURL in Info.plist (README §Releasing).")
        }
    }

    func checkForUpdates() {
        guard started else {
            let alert = NSAlert()
            alert.messageText = "Updates aren’t configured yet"
            alert.informativeText = "Generate Sparkle keys, set SUPublicEDKey in Info.plist, and ship a release. See the README."
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { started && controller.updater.automaticallyChecksForUpdates }
        set { if started { controller.updater.automaticallyChecksForUpdates = newValue } }
    }

    var canCheckForUpdates: Bool { started && controller.updater.canCheckForUpdates }

    private static var hasValidFeedKey: Bool {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        return !key.isEmpty && !key.hasPrefix("REPLACE_")
    }
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

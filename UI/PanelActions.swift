import Foundation

/// Closures the SwiftUI panels invoke; wired up by `AppDelegate`.
struct PanelActions {
    var openSettings: () -> Void
    var checkForUpdates: () -> Void
    var refreshPublicIP: () -> Void
    var quit: () -> Void
}

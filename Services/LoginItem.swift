import Foundation
import ServiceManagement

/// Launch-at-login via `SMAppService` (macOS 13+). The user may need to approve in
/// System Settings → General → Login Items the first time.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("NetCheck LoginItem error: \(error.localizedDescription)")
            return false
        }
    }
}

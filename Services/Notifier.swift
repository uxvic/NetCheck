import Foundation
import UserNotifications

/// Thin wrapper over `UNUserNotificationCenter` for the disconnect / back-online alerts.
@MainActor
final class Notifier {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("NetCheck notification auth error: \(error.localizedDescription)") }
        }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error { NSLog("NetCheck notify error: \(error.localizedDescription)") }
        }
    }
}

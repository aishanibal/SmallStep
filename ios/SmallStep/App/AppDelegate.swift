import UIKit
import UserNotifications

/// Receives reminder taps, including when the app was not running. Snooze is handled without opening the app;
/// Done, Skip and a tap on the reminder itself open Home, which shows the logging screen.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        MainActor.assumeIsolated { NotificationScheduler.shared.registerCategories() }
        return true
    }

    /// Show reminders even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let raw = info["windowId"] as? String, let windowId = UUID(uuidString: raw),
           let start = info["start"] as? Double, let minutes = info["minutes"] as? Int {
            Task { @MainActor in
                if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                    NotificationScheduler.shared.logWindow(windowId, "opened")
                    ReminderRouter.shared.windowTap = WindowTap(windowId: windowId, start: Date(timeIntervalSince1970: start), minutes: minutes)
                }
                completionHandler()
            }
            return
        }
        guard let raw = info["outcomeId"] as? String,
              let outcomeId = UUID(uuidString: raw) else { completionHandler(); return }
        let action = response.actionIdentifier
        Task { @MainActor in
            let scheduler = NotificationScheduler.shared
            switch action {
            case NotificationScheduler.ActionID.snooze:
                await scheduler.snooze(outcomeId)
            case NotificationScheduler.ActionID.done:
                scheduler.log(outcomeId, "done")
                ReminderRouter.shared.tap = ReminderTap(outcomeId: outcomeId, action: .done)
            case NotificationScheduler.ActionID.skip:
                scheduler.log(outcomeId, "skip")
                ReminderRouter.shared.tap = ReminderTap(outcomeId: outcomeId, action: .skip)
            case UNNotificationDefaultActionIdentifier:
                scheduler.log(outcomeId, "opened")
                ReminderRouter.shared.tap = ReminderTap(outcomeId: outcomeId, action: .open)
            default:
                break
            }
            completionHandler()
        }
    }
}

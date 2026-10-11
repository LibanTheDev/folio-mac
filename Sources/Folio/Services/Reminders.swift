import Foundation
import UserNotifications

/// Daily reading reminders via local notifications.
enum Reminders {
    static let identifierPrefix = "folio.reminder."

    /// Calendar triggers for the chosen weekdays (1 = Sunday … 7 = Saturday) at the given time.
    static func triggers(hour: Int, minute: Int, weekdays: Set<Int>) -> [(String, UNCalendarNotificationTrigger)] {
        weekdays.sorted().map { day in
            var c = DateComponents()
            c.weekday = day
            c.hour = hour
            c.minute = minute
            return ("\(identifierPrefix)\(day)", UNCalendarNotificationTrigger(dateMatching: c, repeats: true))
        }
    }

    static func message(currentlyReading: [String], streak: Int) -> (title: String, body: String) {
        let title = streak > 0 ? "Keep your \(streak)-day streak going" : "Time to read"
        let body: String
        switch currentlyReading.count {
        case 0:
            body = "A little reading every day adds up."
        case 1:
            body = "Pick up \(currentlyReading[0]) for a few pages."
        case 2:
            body = "Pick up \(currentlyReading[0]) or \(currentlyReading[1]) for a few pages."
        default:
            body = "Pick up \(currentlyReading[0]) or one of your \(currentlyReading.count - 1) other books."
        }
        return (title, body)
    }

    /// Replaces any scheduled reminders. Asks for permission the first time.
    static func schedule(enabled: Bool, hour: Int, minute: Int, weekdays: Set<Int>,
                         currentlyReading: [String], streak: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: existing)
        guard enabled, !weekdays.isEmpty else { return true }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        let m = message(currentlyReading: currentlyReading, streak: streak)
        for (id, trigger) in triggers(hour: hour, minute: minute, weekdays: weekdays) {
            let content = UNMutableNotificationContent()
            content.title = m.title
            content.body = m.body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        return true
    }
}

import Foundation
import UserNotifications

enum Reminders {
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func post(title: String, body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }

    /// Plans a reminder 2 days before each expected subscription charge.
    @MainActor
    static func scheduleSubscriptionReminders(_ store: FinanceStore) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("abo-") })
        guard UserDefaults.standard.object(forKey: "aboReminders") as? Bool ?? true else { return }
        let cal = Calendar.current
        for r in store.recurring {
            guard let day = cal.date(byAdding: .day, value: -2, to: r.nextDate),
                  let at = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day), at > Date() else { continue }
            let c = UNMutableNotificationContent()
            c.title = "Abo bald fällig: \(r.name)"
            c.body = "Voraussichtlich am \(r.nextDate.formatted(date: .abbreviated, time: .omitted)): \(Money.chf(r.lastAmount)). Noch nötig?"
            c.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            try? await center.add(UNNotificationRequest(identifier: "abo-\(r.key)", content: c,
                                                        trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

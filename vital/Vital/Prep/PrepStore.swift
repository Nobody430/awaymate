import Foundation
import Observation
import UserNotifications

enum PrepMode: String, Codable, CaseIterable, Identifiable {
    case daily, onDemand
    var id: String { rawValue }
    var label: String { self == .daily ? "Täglich" : "Bei Bedarf (2-1-1)" }
}

struct Dose: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var pills: Int = 1
}

@MainActor
@Observable
final class PrepStore {
    static let shared = PrepStore()

    private struct Snapshot: Codable {
        var doses: [Dose]
        var mode: PrepMode
        var reminderHour: Int
        var reminderMinute: Int
        var stock: Int
        var nextTest: Date?
        var discreet: Bool
    }

    private(set) var doses: [Dose] = []
    var mode: PrepMode = .daily { didSet { persist() } }
    var reminderHour = 9 { didSet { persist() } }
    var reminderMinute = 0 { didSet { persist() } }
    var stock = 30 { didSet { save() } }
    var nextTest: Date? { didSet { persist() } }
    var discreet = true { didSet { persist() } }

    private let file = "prep.json"
    private var loading = true

    init() {
        if let s = Disk.load(Snapshot.self, file) {
            doses = s.doses.sorted { $0.date > $1.date }
            mode = s.mode
            reminderHour = s.reminderHour
            reminderMinute = s.reminderMinute
            stock = s.stock
            nextTest = s.nextTest
            discreet = s.discreet
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        Disk.save(Snapshot(doses: doses, mode: mode, reminderHour: reminderHour, reminderMinute: reminderMinute,
                           stock: stock, nextTest: nextTest, discreet: discreet), file)
    }

    private func persist() {
        guard !loading else { return }
        save()
        rescheduleReminders()
    }

    // MARK: Doses

    var takenToday: Bool { doses.contains { Calendar.current.isDateInToday($0.date) } }

    func logDose(pills: Int = 1, at date: Date = Date()) {
        doses.insert(Dose(date: date, pills: pills), at: 0)
        doses.sort { $0.date > $1.date }
        stock = max(0, stock - pills)
        save()
        rescheduleReminders()
    }

    /// Adds a historical dose without touching the pill stock.
    func importDose(at date: Date) {
        doses.append(Dose(date: date))
        doses.sort { $0.date > $1.date }
        save()
    }

    func delete(_ ids: [UUID]) {
        for d in doses where ids.contains(d.id) { stock += d.pills }
        doses.removeAll { ids.contains($0.id) }
        save()
        rescheduleReminders()
    }

    /// 2-1-1: two pills now, one after 24h, one after 48h.
    func startOnDemand() {
        logDose(pills: 2)
        let now = Date()
        schedule(id: "ondemand-24", at: now.addingTimeInterval(24 * 3600), body: discreet ? "Zeit für deine Erinnerung." : "PrEP: 2. Dosis (1 Tablette)")
        schedule(id: "ondemand-48", at: now.addingTimeInterval(48 * 3600), body: discreet ? "Zeit für deine Erinnerung." : "PrEP: 3. Dosis (1 Tablette)")
    }

    func taken(on day: Date) -> Bool {
        doses.contains { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var streak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if !taken(on: day) { day = cal.date(byAdding: .day, value: -1, to: day) ?? day }
        var count = 0
        while taken(on: day) {
            count += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return count
    }

    /// Share of the last 30 days with a dose (daily mode)
    var adherence30: Double {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let firstDose = doses.last.map { cal.startOfDay(for: $0.date) } ?? today
        let days = (0..<30).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }.filter { $0 >= firstDose }
        guard !days.isEmpty else { return 0 }
        return Double(days.filter(taken(on:)).count) / Double(days.count)
    }

    var daysOfStockLeft: Int { mode == .daily ? stock : stock / 4 }

    // MARK: Reminders

    private func schedule(id: String, at date: Date, body: String, category: Bool = true) {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = discreet ? "Erinnerung" : "PrEP"
        content.body = body
        content.sound = .default
        if category { content.categoryIdentifier = NotificationHandler.doseCategory }
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }

    /// Plans the next 14 daily reminders, skipping today if already taken.
    func rescheduleReminders() {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<14).map { "daily-\($0)" } + ["stock", "test"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        let cal = Calendar.current

        if mode == .daily {
            for offset in 0..<14 {
                guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: Date())),
                      let at = cal.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: day) else { continue }
                if offset == 0 && takenToday { continue }
                schedule(id: "daily-\(offset)", at: at, body: discreet ? "Zeit für deine tägliche Erinnerung." : "Zeit für deine PrEP-Tablette 💊")
            }
        }

        if stock <= 7, let at = cal.date(byAdding: .hour, value: 2, to: Date()) {
            schedule(id: "stock", at: at, body: discreet ? "Vorrat bald leer – rechtzeitig nachbestellen." : "Nur noch \(stock) PrEP-Tabletten – Rezept/Nachschub organisieren.", category: false)
        }

        if let test = nextTest,
           let dayBefore = cal.date(byAdding: .day, value: -1, to: test),
           let at = cal.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore) {
            schedule(id: "test", at: at, body: discreet ? "Morgen hast du einen Termin." : "Morgen: Kontrolltermin (HIV/STI-Test).", category: false)
        }
    }
}

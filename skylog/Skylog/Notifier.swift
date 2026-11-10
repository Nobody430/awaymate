import Foundation
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()
    static let newFlightCategory = "NEWFLIGHT"
    static let addAction = "ADD_FLIGHT"
    static let ignoreAction = "IGNORE_FLIGHT"

    static func registerCategories() {
        let add = UNNotificationAction(identifier: addAction, title: String(localized: "Hinzufügen"), options: [])
        let ignore = UNNotificationAction(identifier: ignoreAction, title: String(localized: "Ignorieren"), options: [.destructive])
        let category = UNNotificationCategory(identifier: newFlightCategory, actions: [add, ignore], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        guard let pendingID = (info["pendingID"] as? String).flatMap(UUID.init(uuidString:)) else {
            completionHandler()
            return
        }
        let action = response.actionIdentifier
        DispatchQueue.main.async {
            if action == Self.addAction {
                FlightStore.shared.acceptPending(pendingID)
            } else if action == Self.ignoreAction {
                FlightStore.shared.ignorePending(pendingID)
            }
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

enum Notifier {
    struct Change { let title: String; let body: String }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func post(id: String, title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: Change detection

    static func changes(old: Flight, new: Flight) -> [Change] {
        var result: [Change] = []
        let n = new.number

        let oldStatus = old.normalizedStatus, newStatus = new.normalizedStatus
        // No "ist gelandet" an hour later when the app is opened again
        func recent(_ d: Date?) -> Bool { d.map { Date().timeIntervalSince($0) < 45 * 60 } ?? true }
        let stale = (newStatus == .arrived && !recent(new.arrival.runway ?? new.arrival.best))
            || (newStatus.isAirborne && !recent(new.departure.runway ?? new.departure.best))
        if oldStatus != newStatus && !stale {
            switch newStatus {
            case .boarding:
                result.append(Change(title: String(localized: "\(n): Boarding"), body: String(localized: "Boarding hat begonnen") + (new.departure.gate.map { String(localized: " an Gate \($0)") } ?? "") + "."))
            case .departed, .enRoute:
                if !oldStatus.isAirborne {
                    result.append(Change(title: String(localized: "\(n) ist gestartet"), body: String(localized: "Ankunft in \(new.arrival.displayCity) um \(Fmt.time(new.arrival.best, new.arrival.tz)).")))
                }
            case .arrived:
                result.append(Change(title: String(localized: "\(n) ist gelandet"), body: String(localized: "Willkommen in \(new.arrival.displayCity)!") + (new.arrival.baggageBelt.map { String(localized: " Gepäckband \($0).") } ?? "")))
                let comp = Compensation.check(new)
                if comp.status == .eligible {
                    result.append(Change(title: String(localized: "\(n): \(comp.amountEUR) € Entschädigung möglich"), body: String(localized: "Ankunft über 3 Stunden zu spät – in Skylog den Antrag erstellen.")))
                }
            case .canceled:
                result.append(Change(title: String(localized: "\(n) annulliert"), body: String(localized: "Dein Flug nach \(new.arrival.displayCity) wurde annulliert.")))
            case .diverted:
                result.append(Change(title: String(localized: "\(n) umgeleitet"), body: String(localized: "Der Flug wurde umgeleitet.")))
            default:
                break
            }
        }

        if let g = new.departure.gate, g != old.departure.gate {
            let title = old.departure.gate == nil ? String(localized: "\(n): Gate \(g)") : String(localized: "\(n): Gate-Wechsel")
            let body = old.departure.gate.map { String(localized: "Neues Gate \(g) (vorher \($0)).") } ?? String(localized: "Abflug von Gate \(g).")
            result.append(Change(title: title, body: body + (new.departure.terminal.map { String(localized: " Terminal \($0).") } ?? "")))
        } else if let t = new.departure.terminal, t != old.departure.terminal, old.departure.terminal != nil {
            result.append(Change(title: String(localized: "\(n): Terminal-Wechsel"), body: String(localized: "Abflug jetzt von Terminal \(t).")))
        }

        if !newStatus.isAirborne && !newStatus.isFinal,
           let oldTime = old.lastNotifiedDeparture ?? old.departure.best, let newTime = new.departure.best,
           abs(newTime.timeIntervalSince(oldTime)) >= 5 * 60 {
            let delay = Fmt.delay(new.departure.delayMinutes).map { " (\($0))" } ?? ""
            result.append(Change(title: String(localized: "\(n): Neue Abflugzeit"), body: String(localized: "Abflug jetzt \(Fmt.time(newTime, new.departure.tz))\(delay).")))
        }

        if newStatus.isAirborne, let oldTime = old.arrival.best, let newTime = new.arrival.best,
           abs(newTime.timeIntervalSince(oldTime)) >= 10 * 60 {
            result.append(Change(title: String(localized: "\(n): Neue Ankunftszeit"), body: String(localized: "Ankunft jetzt \(Fmt.time(newTime, new.arrival.tz)).")))
        }

        // Baggage belt only makes sense shortly before / after landing (airlines publish early guesses)
        let nearArrival = new.arrival.best.map { $0.timeIntervalSinceNow < 45 * 60 } ?? false
        let beltRelevant = (newStatus.isAirborne && nearArrival) || (newStatus == .arrived && oldStatus == .arrived)
        if let b = new.arrival.baggageBelt, b != old.arrival.baggageBelt, beltRelevant {
            result.append(Change(title: String(localized: "\(n): Gepäckband \(b)"), body: String(localized: "Dein Gepäck kommt auf Band \(b).")))
        }
        return result
    }

    // MARK: Reminders

    private static func reminderIDs(_ f: Flight) -> [String] {
        ["\(f.id)-checkin", "\(f.id)-boarding", "\(f.id)-landing"]
    }

    static func cancelReminders(for f: Flight) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: reminderIDs(f))
    }

    static func scheduleReminders(for f: Flight) {
        cancelReminders(for: f)
        guard Settings.reminders, !f.isPast, !f.normalizedStatus.isFinal else { return }
        let ids = reminderIDs(f)

        if let dep = f.departure.best {
            schedule(id: ids[0], at: dep.addingTimeInterval(-3 * 3600),
                     title: String(localized: "\(f.number) nach \(f.arrival.displayCity)"),
                     body: String(localized: "Abflug in 3 Stunden um \(Fmt.time(dep, f.departure.tz))") + (f.departure.terminal.map { String(localized: ", Terminal \($0)") } ?? "") + ".")
            schedule(id: ids[1], at: dep.addingTimeInterval(-45 * 60),
                     title: String(localized: "\(f.number): Boarding bald"),
                     body: (f.departure.gate.map { String(localized: "Gate \($0) · ") } ?? "") + String(localized: "Abflug \(Fmt.time(dep, f.departure.tz))."))
        }
        if let arr = f.arrival.best {
            schedule(id: ids[2], at: arr.addingTimeInterval(-20 * 60),
                     title: String(localized: "\(f.number): Landung in ca. 20 Min."),
                     body: String(localized: "Ankunft \(Fmt.time(arr, f.arrival.tz)) in \(f.arrival.displayCity)") + (f.arrival.baggageBelt.map { String(localized: ", Gepäckband \($0)") } ?? "") + ".")
        }
    }

    private static func schedule(id: String, at date: Date, title: String, body: String) {
        let interval = date.timeIntervalSinceNow
        guard interval > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

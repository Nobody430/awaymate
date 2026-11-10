import Foundation
import EventKit

/// Writes upcoming flights (and hotel stays) into the iPhone calendar and keeps them up to date.
@MainActor
enum CalendarSync {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "calendarSync") }
    private static let store = EKEventStore()

    private static var map: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "calendarEvents") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "calendarEvents") }
    }

    /// Asks for calendar access; returns false if the user declined.
    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    static func sync(_ flights: [Flight], bookings: [TravelBooking]) async {
        guard enabled, EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.defaultCalendarForNewEvents else { return }
        var ids = map
        var alive: Set<String> = []

        for f in flights where !f.isPast && f.normalizedStatus != .canceled {
            guard let dep = f.departure.best, let arr = f.arrival.best, arr > dep else { continue }
            let key = f.id.uuidString
            alive.insert(key)
            let event = ids[key].flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
            let title = "✈️ \(f.number) \(f.departure.code) → \(f.arrival.code)"
            var notes = ["Abflug \(Fmt.time(dep, f.departure.tz)) (\(f.departure.displayCity)), Ankunft \(Fmt.time(arr, f.arrival.tz)) (\(f.arrival.displayCity)) – Ortszeiten"]
            if let t = f.departure.terminal { notes.append("Terminal \(t)") }
            if let g = f.departure.gate { notes.append("Gate \(g)") }
            if !f.seat.isEmpty { notes.append("Sitz \(f.seat)") }
            if !f.notes.isEmpty { notes.append(f.notes) }
            let text = notes.joined(separator: "\n")
            if event.title == title, event.startDate == dep, event.endDate == arr, event.notes == text { continue }
            event.calendar = event.calendar ?? calendar
            event.title = title
            event.startDate = dep
            event.endDate = arr
            event.timeZone = f.departure.tz
            event.location = f.departure.name ?? f.departure.code
            event.notes = text
            if (try? store.save(event, span: .thisEvent)) != nil { ids[key] = event.eventIdentifier }
        }

        for b in bookings where b.kind == .hotel && !b.cancelled && b.end > Date() {
            let key = "booking-" + b.id.uuidString
            alive.insert(key)
            let event = ids[key].flatMap { store.event(withIdentifier: $0) } ?? EKEvent(eventStore: store)
            let title = "🏨 \(b.name)"
            if event.title == title, event.startDate == b.start, event.isAllDay { continue }
            event.calendar = event.calendar ?? calendar
            event.title = title
            event.isAllDay = true
            event.startDate = b.start
            event.endDate = b.end
            event.location = b.address.isEmpty ? b.city : b.address
            event.notes = b.bookingReference.isEmpty ? nil : "Buchung \(b.bookingReference)"
            if (try? store.save(event, span: .thisEvent)) != nil { ids[key] = event.eventIdentifier }
        }

        // deleted or cancelled flights disappear from the calendar again
        for (key, id) in ids where !alive.contains(key) {
            if let e = store.event(withIdentifier: id), e.endDate > Date() { try? store.remove(e, span: .thisEvent) }
            ids[key] = nil
        }
        map = ids
    }

    /// Removes everything Skylog put into the calendar (when the option is switched off).
    static func removeAll() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        for id in map.values { if let e = store.event(withIdentifier: id) { try? store.remove(e, span: .thisEvent) } }
        map = [:]
    }
}

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
            var notes = [String(localized: "Abflug \(Fmt.time(dep, f.departure.tz)) (\(f.departure.displayCity)), Ankunft \(Fmt.time(arr, f.arrival.tz)) (\(f.arrival.displayCity)) – Ortszeiten")]
            if let t = f.departure.terminal { notes.append(String(localized: "Terminal \(t)")) }
            if let g = f.departure.gate { notes.append(String(localized: "Gate \(g)")) }
            if !f.seat.isEmpty { notes.append(String(localized: "Sitz \(f.seat)")) }
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
            event.notes = b.bookingReference.isEmpty ? nil : String(localized: "Buchung \(b.bookingReference)")
            if (try? store.save(event, span: .thisEvent)) != nil { ids[key] = event.eventIdentifier }
        }

        // deleted or cancelled flights disappear from the calendar again
        for (key, id) in ids where !alive.contains(key) {
            if let e = store.event(withIdentifier: id), e.endDate > Date() { try? store.remove(e, span: .thisEvent) }
            ids[key] = nil
        }
        map = ids
    }

    /// Removes everything Awaymate put into the calendar (when the option is switched off).
    static func removeAll() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        for id in map.values { if let e = store.event(withIdentifier: id) { try? store.remove(e, span: .thisEvent) } }
        map = [:]
    }
}

/// Finds flights in the iPhone calendar (entries made by airlines, travel agencies or by hand).
@MainActor
enum CalendarImport {
    /// Calendar events from two years back to one year ahead that look like flights.
    static func scan() async throws -> [FlightCandidate] {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else {
            throw AIClient.Failure(message: String(localized: "Kein Zugriff auf den Kalender. Erlaube ihn in den iPhone-Einstellungen → Awaymate → Kalender (Vollzugriff)."))
        }
        let now = Date()
        let ownEvents = Set((UserDefaults.standard.dictionary(forKey: "calendarEvents") as? [String: String] ?? [:]).values)
        let numberRegex = try NSRegularExpression(pattern: MailAI.flightNumberPattern)
        let codeRegex = try NSRegularExpression(pattern: "\\b[A-Z]{3}\\b")
        var found: [String: FlightCandidate] = [:]

        // EventKit only searches up to four years per query – go year by year
        for offset in [-2, -1, 0] {
            guard let from = Calendar.current.date(byAdding: .year, value: offset, to: now),
                  let to = Calendar.current.date(byAdding: .year, value: 1, to: from) else { continue }
            let predicate = store.predicateForEvents(withStart: from, end: to, calendars: nil)
            for event in store.events(matching: predicate) {
                // skip all-day entries and the ones Awaymate wrote itself
                guard !event.isAllDay, let id = event.eventIdentifier, !ownEvents.contains(id),
                      let title = event.title, let start = event.startDate else { continue }
                let text = [title, event.location ?? "", event.notes ?? ""].joined(separator: "\n")
                let range = NSRange(text.startIndex..., in: text)
                guard let m = numberRegex.firstMatch(in: text, range: NSRange(title.startIndex..., in: title)) ?? numberRegex.firstMatch(in: text, range: range),
                      let r = Range(m.range, in: text) else { continue }
                let number = FlightStore.normalizedNumber(String(text[r]))
                guard FlightTextParser.airlines.contains(String(number.prefix(2))) else { continue }

                // airports: three-letter codes that really exist, in the order they appear
                var airports: [String] = []
                for c in codeRegex.matches(in: text, range: range) {
                    guard let cr = Range(c.range, in: text) else { continue }
                    let code = String(text[cr])
                    if !airports.contains(code), AirportLookup.bundledInfo(code)?.lat != nil { airports.append(code) }
                    if airports.count == 2 { break }
                }
                let depTZ = airports.first.flatMap { AirportLookup.bundledInfo($0)?.timeZone }.flatMap(TimeZone.init(identifier:)) ?? event.timeZone ?? .current
                let arrTZ = airports.dropFirst().first.flatMap { AirportLookup.bundledInfo($0)?.timeZone }.flatMap(TimeZone.init(identifier:)) ?? depTZ

                // the day of the flight is the local day at the departure airport
                var depCal = Calendar(identifier: .gregorian)
                depCal.timeZone = depTZ
                let day = depCal.dateComponents([.year, .month, .day, .hour, .minute], from: start)
                guard let noon = Calendar.current.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { continue }
                var c = FlightCandidate(number: number, date: noon, source: String(localized: "Kalender: \(title)"), airports: airports)
                c.departureTime = String(format: "%02d:%02d", day.hour ?? 0, day.minute ?? 0)
                if let end = event.endDate, end > start, end.timeIntervalSince(start) < 20 * 3600 {
                    var arrCal = Calendar(identifier: .gregorian)
                    arrCal.timeZone = arrTZ
                    let a = arrCal.dateComponents([.year, .month, .day, .hour, .minute], from: end)
                    c.arrivalTime = String(format: "%02d:%02d", a.hour ?? 0, a.minute ?? 0)
                    // arrival on another local day than the departure
                    if let d0 = depCal.date(from: DateComponents(year: day.year, month: day.month, day: day.day)),
                       let d1 = depCal.date(from: DateComponents(year: a.year, month: a.month, day: a.day)) {
                        c.arrivalDayOffset = Int((d1.timeIntervalSince(d0) / 86400).rounded())
                    }
                }
                // an entry with both airports is good enough to import without asking the flight data service
                c.aiVerified = airports.count == 2
                found[c.id] = c
            }
        }
        return found.values.sorted { $0.date > $1.date }
    }
}

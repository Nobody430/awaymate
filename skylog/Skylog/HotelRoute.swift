import Foundation
import MapKit
import UserNotifications

/// Links flights with imported hotel bookings: airport → hotel after landing, hotel → airport before departure.
@MainActor
enum HotelRoute {
    static var homeAirport: String { (UserDefaults.standard.string(forKey: "homeAirport") ?? "").uppercased() }

    private static var hotels: [TravelBooking] {
        BookingStore.shared.bookings.filter { $0.kind == .hotel && !$0.cancelled }
    }

    private static func sameCity(_ b: TravelBooking, _ e: FlightEndpoint) -> Bool {
        let c = b.city.lowercased()
        guard !c.isEmpty else { return false }
        return [e.city, e.name].compactMap { $0?.lowercased() }.contains { $0.contains(c) || c.contains($0) }
    }

    /// Landing here and flying on within 24 h = connection, no hotel.
    static func isConnection(after f: Flight, in flights: [Flight]) -> Bool {
        guard let arr = f.arrival.best ?? f.arrival.scheduled else { return false }
        return flights.contains { o in
            o.id != f.id && o.departure.code == f.arrival.code &&
                (o.departure.best ?? o.sortDate) > arr && (o.departure.best ?? o.sortDate) < arr.addingTimeInterval(24 * 3600)
        }
    }

    /// Flying out of here within 24 h after arriving = connection, not leaving from a hotel.
    static func isConnection(before f: Flight, in flights: [Flight]) -> Bool {
        guard let dep = f.departure.best ?? f.departure.scheduled else { return false }
        return flights.contains { o in
            o.id != f.id && o.arrival.code == f.departure.code &&
                (o.arrival.best ?? o.sortDate) < dep && (o.arrival.best ?? o.sortDate) > dep.addingTimeInterval(-24 * 3600)
        }
    }

    /// Hotel you check into after this flight (check-in from the day before until 1 day after landing).
    static func hotel(after f: Flight, flights: [Flight]) -> TravelBooking? {
        guard f.arrival.code != homeAirport, !isConnection(after: f, in: flights),
              let arr = f.arrival.best ?? f.arrival.scheduled else { return nil }
        // Compare calendar days (bookings are stored as dates, not times): the stay must cover the arrival day.
        // A check-in on the next day only counts for late-evening arrivals.
        let day = dayNumber(arr, f.arrival.tz)
        let late = Calendar.current.dateComponents(in: f.arrival.tz, from: arr).hour ?? 0 >= 21
        let cands = hotels.filter {
            let ci = dayNumber($0.start, .current), co = dayNumber($0.end, .current)
            return co > day && (ci <= day || (late && ci == day + 1)) && ci >= day - 1
        }
        // prefer the same city, then the check-in closest to the arrival day
        return cands.min { a, b in
            let sa = sameCity(a, f.arrival), sb = sameCity(b, f.arrival)
            if sa != sb { return sa }
            return abs(dayNumber(a.start, .current) - day) < abs(dayNumber(b.start, .current) - day)
        }
    }

    /// Days since 1970 of the calendar day `date` falls on in `tz`.
    private static func dayNumber(_ date: Date, _ tz: TimeZone) -> Int {
        Int(floor((date.timeIntervalSince1970 + Double(tz.secondsFromGMT(for: date))) / 86400))
    }

    /// Hotel you leave from for this flight (stay covers the departure day).
    static func hotel(before f: Flight, flights: [Flight]) -> TravelBooking? {
        guard f.departure.code != homeAirport, !isConnection(before: f, in: flights), let dep = f.departure.best ?? f.departure.scheduled else { return nil }
        // Stay must end on the departure day (or the day before, for early-morning flights)
        let day = dayNumber(dep, f.departure.tz)
        let cands = hotels.filter {
            let ci = dayNumber($0.start, .current), co = dayNumber($0.end, .current)
            return ci <= day && (co == day || co == day + 1 || co == day - 1) && ci < co
        }
        return cands.min { a, b in
            let sa = sameCity(a, f.departure), sb = sameCity(b, f.departure)
            if sa != sb { return sa }
            return abs(dayNumber(a.end, .current) - day) < abs(dayNumber(b.end, .current) - day)
        }
    }

    // MARK: Location

    static func locate(_ b: TravelBooking, near: CLLocationCoordinate2D?) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [b.name, b.address.isEmpty ? b.city : b.address].filter { !$0.isEmpty }.joined(separator: ", ")
        if let near { request.region = MKCoordinateRegion(center: near, latitudinalMeters: 150_000, longitudinalMeters: 150_000) }
        func plausible(_ i: MKMapItem?) -> MKMapItem? {
            guard let i, let near else { return i }
            let c = i.placemark.coordinate
            // hotel more than 150 km from the airport → wrong city (e.g. stopover)
            return Geo.distanceKm(c, near) < 150 ? i : nil
        }
        if let item = plausible(try? await MKLocalSearch(request: request).start().mapItems.first) { return item }
        // fallback: address only
        guard !b.address.isEmpty else { return nil }
        request.naturalLanguageQuery = b.address + ", " + b.city
        return plausible(try? await MKLocalSearch(request: request).start().mapItems.first)
    }

    struct Times: Equatable {
        var car: TimeInterval?
        var transit: TimeInterval?
        var walk: TimeInterval?
        var distanceKm: Double?
    }

    static func times(from a: MKMapItem, to b: MKMapItem, departAt: Date? = nil, arriveBy: Date? = nil) async -> Times {
        func eta(_ type: MKDirectionsTransportType) async -> MKDirections.ETAResponse? {
            let r = MKDirections.Request()
            r.source = a
            r.destination = b
            r.transportType = type
            if let arriveBy { r.arrivalDate = arriveBy } else if let departAt, departAt > Date() { r.departureDate = departAt }
            return try? await MKDirections(request: r).calculateETA()
        }
        async let car = eta(.automobile)
        async let transit = eta(.transit)
        let c = await car, t = await transit
        var times = Times(car: c?.expectedTravelTime, transit: t?.expectedTravelTime,
                          distanceKm: (c?.distance ?? t?.distance).map { $0 / 1000 })
        if let d = times.distanceKm, d < 3 { times.walk = (await eta(.walking))?.expectedTravelTime }
        return times
    }

    static func airportItem(_ e: FlightEndpoint) -> MKMapItem? {
        guard let c = e.coordinate else { return nil }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = e.name ?? String(localized: "\(e.code) Flughafen")
        return item
    }

    static func googleURL(from: CLLocationCoordinate2D, to: String, mode: String = "transit") -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        c.queryItems = [URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "origin", value: "\(from.latitude),\(from.longitude)"),
                        URLQueryItem(name: "destination", value: to),
                        URLQueryItem(name: "travelmode", value: mode)]
        return c.url
    }

    static func googleURL(fromQuery: String, to: CLLocationCoordinate2D, mode: String = "transit") -> URL? {
        var c = URLComponents(string: "https://www.google.com/maps/dir/")!
        c.queryItems = [URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: "origin", value: fromQuery),
                        URLQueryItem(name: "destination", value: "\(to.latitude),\(to.longitude)"),
                        URLQueryItem(name: "travelmode", value: mode)]
        return c.url
    }

    // MARK: Reminders

    /// "Weiter zum Hotel" shortly after landing, "Zum Flughafen aufbrechen" on departure day.
    static func scheduleReminders(for f: Flight, flights: [Flight]) {
        let center = UNUserNotificationCenter.current()
        let ids = ["\(f.id)-hotel-in", "\(f.id)-hotel-out"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard Settings.reminders, !f.isPast, !f.normalizedStatus.isFinal else { return }
        if let h = hotel(after: f, flights: flights), let arr = f.arrival.best {
            schedule(ids[0], at: arr.addingTimeInterval(25 * 60), title: String(localized: "Weiter zu \(h.name)"),
                     body: String(localized: "Tippe in Skylog auf \(f.number) für den Weg vom Flughafen zum Hotel."))
        }
        if let h = hotel(before: f, flights: flights), let dep = f.departure.best {
            let leave = dep.addingTimeInterval(-Double(AirportBuffer.minutes(for: f) + 60) * 60)
            schedule(ids[1], at: leave.addingTimeInterval(-30 * 60), title: String(localized: "\(f.number): Bald zum Flughafen"),
                     body: String(localized: "Von \(h.name) zum Flughafen \(f.departure.code) – in Skylog siehst du, wann du los musst."))
        }
    }

    private static func schedule(_ id: String, at date: Date, title: String, body: String) {
        let interval = date.timeIntervalSinceNow
        guard interval > 60 else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: id, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)))
    }
}

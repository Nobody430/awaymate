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

    /// Hotel you check into after this flight (check-in from the day before until 1 day after landing).
    static func hotel(after f: Flight) -> TravelBooking? {
        guard f.arrival.code != homeAirport, let arr = f.arrival.best ?? f.arrival.scheduled else { return nil }
        let cands = hotels.filter {
            $0.start > arr.addingTimeInterval(-36 * 3600) && $0.start < arr.addingTimeInterval(36 * 3600) && $0.end > arr
        }
        return cands.min { score($0, arr, f.arrival) < score($1, arr, f.arrival) }
    }

    /// Hotel you leave from for this flight (stay covers the departure day).
    static func hotel(before f: Flight) -> TravelBooking? {
        guard f.departure.code != homeAirport, let dep = f.departure.best ?? f.departure.scheduled else { return nil }
        let cands = hotels.filter { $0.start < dep && $0.end > dep.addingTimeInterval(-36 * 3600) }
        return cands.min { score($0, dep, f.departure, useEnd: true) < score($1, dep, f.departure, useEnd: true) }
    }

    private static func score(_ b: TravelBooking, _ t: Date, _ e: FlightEndpoint, useEnd: Bool = false) -> Double {
        abs((useEnd ? b.end : b.start).timeIntervalSince(t)) - (sameCity(b, e) ? 86400 : 0)
    }

    // MARK: Location

    static func locate(_ b: TravelBooking, near: CLLocationCoordinate2D?) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [b.name, b.address.isEmpty ? b.city : b.address].filter { !$0.isEmpty }.joined(separator: ", ")
        if let near { request.region = MKCoordinateRegion(center: near, latitudinalMeters: 150_000, longitudinalMeters: 150_000) }
        if let item = try? await MKLocalSearch(request: request).start().mapItems.first { return item }
        // fallback: address only
        guard !b.address.isEmpty else { return nil }
        request.naturalLanguageQuery = b.address + ", " + b.city
        return try? await MKLocalSearch(request: request).start().mapItems.first
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
        item.name = e.name ?? "\(e.code) Flughafen"
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
    static func scheduleReminders(for f: Flight) {
        let center = UNUserNotificationCenter.current()
        let ids = ["\(f.id)-hotel-in", "\(f.id)-hotel-out"]
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard Settings.reminders, !f.isPast, !f.normalizedStatus.isFinal else { return }
        if let h = hotel(after: f), let arr = f.arrival.best {
            schedule(ids[0], at: arr.addingTimeInterval(25 * 60), title: "Weiter zu \(h.name)",
                     body: "Tippe in Skylog auf \(f.number) für den Weg vom Flughafen zum Hotel.")
        }
        if let h = hotel(before: f), let dep = f.departure.best {
            let leave = dep.addingTimeInterval(-Double(AirportBuffer.minutes(for: f) + 60) * 60)
            schedule(ids[1], at: leave.addingTimeInterval(-30 * 60), title: "\(f.number): Bald zum Flughafen",
                     body: "Von \(h.name) zum Flughafen \(f.departure.code) – in Skylog siehst du, wann du los musst.")
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

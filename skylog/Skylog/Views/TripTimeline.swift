import SwiftUI
import MapKit

/// One entry of a trip – a flight or a booking – in the order they happen: flight, hotel, flight, hotel …
enum TripStep: Identifiable {
    case flight(Flight)
    case booking(TravelBooking)

    var id: UUID {
        switch self {
        case .flight(let f): f.id
        case .booking(let b): b.id
        }
    }

    private static func day(_ date: Date, _ tz: TimeZone) -> Int {
        Int(floor((date.timeIntervalSince1970 + Double(tz.secondsFromGMT(for: date))) / 86400))
    }

    static func timeline(flights: [Flight], bookings: [TravelBooking]) -> [TripStep] {
        var rows: [(at: Date, rank: Int, step: TripStep)] = flights.map {
            (at: $0.departure.best ?? $0.sortDate, rank: 0, step: TripStep.flight($0))
        }
        for b in bookings {
            var at = b.start
            if b.kind == .hotel {
                // A stay follows the last flight that lands on the check-in day (or shortly after midnight the next day).
                let checkIn = day(b.start, .current)
                let landings = flights.compactMap { f -> Date? in
                    guard let arr = f.arrival.best ?? f.arrival.scheduled else { return nil }
                    let d = day(arr, f.arrival.tz)
                    let hour = Calendar.current.dateComponents(in: f.arrival.tz, from: arr).hour ?? 12
                    return d == checkIn || (d == checkIn + 1 && hour < 6) ? arr : nil
                }
                at = landings.max()?.addingTimeInterval(60)
                    ?? Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: b.start) ?? b.start
            }
            rows.append((at: at, rank: 1, step: TripStep.booking(b)))
        }
        return rows.sorted { $0.at != $1.at ? $0.at < $1.at : $0.rank < $1.rank }.map { $0.step }
    }
}

/// The way between two stops of a trip: airport → hotel, hotel → hotel, hotel → airport.
struct TripLeg: Identifiable {
    enum Place {
        case airport(FlightEndpoint)
        case stay(TravelBooking)
    }

    let from: Place
    let to: Place
    /// Where to look for the hotel (the airport of the same stop)
    let near: CLLocationCoordinate2D?
    var departAt: Date? = nil
    var arriveBy: Date? = nil

    private static func key(_ p: Place) -> String {
        switch p {
        case .airport(let e): "A:" + e.code
        case .stay(let b): "S:" + b.id.uuidString
        }
    }

    var id: String { Self.key(from) + ">" + Self.key(to) }

    var title: String {
        switch (from, to) {
        case (.airport(let e), .stay): String(localized: "Vom Flughafen \(e.code) zum Hotel")
        case (.stay, .airport(let e)): String(localized: "Vom Hotel zum Flughafen \(e.code)")
        default: String(localized: "Weiter zur nächsten Unterkunft")
        }
    }
}

enum TripRow: Identifiable {
    case step(TripStep)
    case leg(TripLeg)

    var id: String {
        switch self {
        case .step(let s): s.id.uuidString
        case .leg(let l): l.id
        }
    }

    /// Puts the way from the last stop in front of every hotel and of every flight that starts from a hotel.
    static func rows(_ steps: [TripStep]) -> [TripRow] {
        var rows: [TripRow] = []
        var last: TripLeg.Place?
        var lastArrival: (coordinate: CLLocationCoordinate2D?, time: Date?)?
        for step in steps {
            switch step {
            case .flight(let f):
                if case .stay? = last, let from = last {
                    let buffer = Double(AirportBuffer.minutes(for: f)) * 60
                    rows.append(.leg(TripLeg(from: from, to: .airport(f.departure), near: f.departure.coordinate,
                                             arriveBy: f.departure.best.map { $0.addingTimeInterval(-buffer) })))
                }
                last = .airport(f.arrival)
                lastArrival = (f.arrival.coordinate, f.arrival.best)
            case .booking(let b):
                guard b.kind == .hotel, !b.cancelled else { break }
                if let from = last {
                    var leg = TripLeg(from: from, to: .stay(b), near: lastArrival?.coordinate)
                    if case .airport = from { leg.departAt = lastArrival?.time?.addingTimeInterval(30 * 60) }
                    rows.append(.leg(leg))
                }
                last = .stay(b)
            }
            rows.append(.step(step))
        }
        return rows
    }
}

/// A booking drawn like the flight cards.
struct StayCard: View {
    let booking: TravelBooking

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: booking.kind.icon)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(booking.name).font(.headline).lineLimit(2)
                Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                if !booking.bookingReference.isEmpty {
                    Text("Code \(booking.bookingReference)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(booking.cancelled ? 0.5 : 1)
    }

    private var line: String {
        var parts = [booking.city]
        let start = booking.start.formatted(.dateTime.day().month(.abbreviated))
        if booking.kind == .hotel || booking.kind == .car {
            parts.append("\(start) – \(booking.end.formatted(.dateTime.day().month(.abbreviated)))")
            if booking.kind == .hotel && booking.nights > 0 { parts.append(String(localized: "\(booking.nights) Nächte")) }
        } else {
            parts.append(start)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Travel times between two stops (Apple Maps), looked up once per leg.
@MainActor
private enum TripLegCache {
    struct Entry {
        let times: HotelRoute.Times
        let from: MKMapItem
        let to: MKMapItem
    }
    static var entries: [String: Entry] = [:]
    static var failed: Set<String> = []
}

struct TripLegRow: View {
    let leg: TripLeg
    @State private var entry: TripLegCache.Entry?
    @State private var done = false

    var body: some View {
        Menu {
            if let entry {
                Button { openMaps(entry, mode: MKLaunchOptionsDirectionsModeTransit) } label: {
                    Label("ÖV-Route in Apple Karten", systemImage: "tram.fill")
                }
                Button { openMaps(entry, mode: MKLaunchOptionsDirectionsModeDriving) } label: {
                    Label("Auto-Route in Apple Karten", systemImage: "car.fill")
                }
                Divider()
                Button { openUber(entry) } label: { Label("Uber bestellen", systemImage: "car.side.fill") }
                ForEach(RideApp.others) { app in
                    Button { app.open(destination: Self.address(entry.to)) } label: {
                        Label("\(app.name) öffnen (Zieladresse kopiert)", systemImage: "car.side")
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(leg.title).font(.caption).foregroundStyle(.secondary)
                    if let t = entry?.times {
                        HStack(spacing: 12) {
                            if let v = t.transit { Label(String(localized: "ÖV \(Fmt.duration(Int(v / 60)))"), systemImage: "tram.fill") }
                            if let v = t.car { Label(String(localized: "Taxi \(Fmt.duration(Int(v / 60)))"), systemImage: "car.fill") }
                            if let v = t.walk { Label(Fmt.duration(Int(v / 60)), systemImage: "figure.walk") }
                            if let d = t.distanceKm { Text(Fmt.km(d)) }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    } else if !done {
                        ProgressView().controlSize(.mini)
                    }
                }
                Spacer(minLength: 0)
                if entry != nil { Image(systemName: "map").font(.caption).foregroundStyle(Theme.accent) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .disabled(entry == nil)
        .task(id: leg.id) { await load() }
    }

    private func openMaps(_ entry: TripLegCache.Entry, mode: String) {
        MKMapItem.openMaps(with: [entry.from, entry.to], launchOptions: [MKLaunchOptionsDirectionsModeKey: mode])
    }

    private static func address(_ item: MKMapItem) -> String {
        [item.name, item.placemark.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Uber's universal link: opens the app (or the website) with pickup and destination filled in.
    private func openUber(_ entry: TripLegCache.Entry) {
        let a = entry.from.placemark.coordinate, b = entry.to.placemark.coordinate
        var c = URLComponents(string: "https://m.uber.com/ul/")!
        c.queryItems = [
            URLQueryItem(name: "action", value: "setPickup"),
            URLQueryItem(name: "pickup[latitude]", value: "\(a.latitude)"),
            URLQueryItem(name: "pickup[longitude]", value: "\(a.longitude)"),
            URLQueryItem(name: "pickup[nickname]", value: entry.from.name ?? ""),
            URLQueryItem(name: "dropoff[latitude]", value: "\(b.latitude)"),
            URLQueryItem(name: "dropoff[longitude]", value: "\(b.longitude)"),
            URLQueryItem(name: "dropoff[nickname]", value: entry.to.name ?? ""),
            URLQueryItem(name: "dropoff[formatted_address]", value: Self.address(entry.to)),
        ]
        if let url = c.url { UIApplication.shared.open(url) }
    }

    private func item(_ place: TripLeg.Place) async -> MKMapItem? {
        switch place {
        case .airport(let e): return HotelRoute.airportItem(e)
        case .stay(let b): return await HotelRoute.locate(b, near: leg.near)
        }
    }

    private func load() async {
        if let cached = TripLegCache.entries[leg.id] { entry = cached; done = true; return }
        if TripLegCache.failed.contains(leg.id) { done = true; return }
        guard let a = await item(leg.from), let b = await item(leg.to) else {
            TripLegCache.failed.insert(leg.id)
            done = true
            return
        }
        let times = await HotelRoute.times(from: a, to: b, departAt: leg.departAt, arriveBy: leg.arriveBy)
        guard !Task.isCancelled else { return }
        if times.car != nil || times.transit != nil || times.walk != nil {
            let e = TripLegCache.Entry(times: times, from: a, to: b)
            TripLegCache.entries[leg.id] = e
            entry = e
        } else {
            TripLegCache.failed.insert(leg.id)
        }
        done = true
    }
}


/// Ride apps without a public link format for a destination: the app is opened and the address is on the clipboard.
struct RideApp: Identifiable {
    let name: String
    let scheme: String
    let web: String
    var id: String { name }

    static let others = [
        RideApp(name: "Bolt", scheme: "bolt://", web: "https://bolt.eu"),
        RideApp(name: "Cabify", scheme: "cabify://", web: "https://cabify.com"),
        RideApp(name: "FREE NOW", scheme: "mytaxi://", web: "https://www.free-now.com"),
    ]

    @MainActor
    func open(destination: String) {
        UIPasteboard.general.string = destination
        guard let app = URL(string: scheme) else { return }
        UIApplication.shared.open(app) { ok in
            if !ok, let site = URL(string: web) { UIApplication.shared.open(site) }
        }
    }
}

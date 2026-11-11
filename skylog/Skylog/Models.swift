import Foundation
import CoreLocation

struct FlightEndpoint: Codable, Hashable {
    var iata: String?
    var icao: String?
    var name: String?
    var city: String?
    var countryCode: String?
    var lat: Double?
    var lon: Double?
    var timeZone: String?
    var scheduled: Date?
    var revised: Date?
    var predicted: Date?
    var runway: Date?
    var terminal: String?
    var gate: String?
    var checkInDesk: String?
    var baggageBelt: String?

    var code: String { iata ?? icao ?? "???" }
    var displayCity: String { city ?? name ?? code }
    /// Best known time: actual > revised > predicted > scheduled
    var best: Date? { runway ?? revised ?? predicted ?? scheduled }

    var delayMinutes: Int? {
        guard let s = scheduled, let b = best else { return nil }
        return Int((b.timeIntervalSince(s) / 60).rounded())
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var tz: TimeZone { timeZone.flatMap { TimeZone(identifier: $0) } ?? .current }
}

struct LivePosition: Codable, Hashable {
    var lat: Double
    var lon: Double
    var altitudeM: Double?
    var speedKmh: Double?
    var heading: Double?
    var verticalRate: Double?
    var onGround: Bool
    var timestamp: Date
    var source: String

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

/// How early to be at the airport. 0 in settings = automatic (depends on the flight).
enum AirportBuffer {
    static let key = "airportBuffer"
    static let choices = [0, 60, 90, 120, 150, 180, 240]

    static func isLongHaul(_ f: Flight) -> Bool { (f.computedDistanceKm ?? 0) > 3500 }
    static func isInternational(_ f: Flight) -> Bool {
        guard let a = f.departure.countryCode, let b = f.arrival.countryCode else { return false }
        return a != b
    }

    /// Recommendation: 3 h long-haul or leaving the US/UK, 2 h otherwise (Schengen/domestic).
    static func recommended(_ f: Flight) -> Int {
        let strictOrigin = ["US", "GB", "IL", "CA"].contains(f.departure.countryCode ?? "")
        if isLongHaul(f) || (isInternational(f) && strictOrigin) { return 180 }
        if isInternational(f) && !Schengen.contains(f.departure.countryCode ?? "") { return 150 }
        return 120
    }

    /// Never later than 30 min before bag drop closes.
    static func minutes(for f: Flight) -> Int {
        let setting = UserDefaults.standard.integer(forKey: key)
        let minimum = (isLongHaul(f) ? 60 : 40) + 30
        return max(setting == 0 ? recommended(f) : setting, minimum)
    }

    static func label(_ m: Int) -> String { m == 0 ? String(localized: "Automatisch") : m % 60 == 0 ? "\(m / 60) h" : String(localized: "\(m / 60) h \(m % 60) Min") }

    private static let Schengen: Set<String> = ["AT","BE","BG","CH","CZ","DE","DK","EE","ES","FI","FR","GR","HR","HU","IS","IT","LI","LT","LU","LV","MT","NL","NO","PL","PT","RO","SE","SI","SK"]
}

/// Scheduled / estimated / actual times at the gate and on the runway.
struct Timetable: Codable, Hashable {
    var outScheduled: Date?, outEstimated: Date?, outActual: Date?     // leaves the gate
    var offScheduled: Date?, offEstimated: Date?, offActual: Date?     // takes off
    var onScheduled: Date?, onEstimated: Date?, onActual: Date?        // lands
    var inScheduled: Date?, inEstimated: Date?, inActual: Date?        // arrives at the gate

    var isEmpty: Bool { outScheduled == nil && offScheduled == nil && onScheduled == nil && inScheduled == nil }
}

struct FlightUpdate: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
}

/// The plane that will operate our flight, on its previous leg.
struct InboundFlight: Codable, Hashable {
    var number: String
    var fromCode: String
    var fromCity: String?
    var status: String?
    var departure: Date?
    var departed: Bool
    var arrival: Date?
    var scheduledArrival: Date?
    var landed: Bool
    var updated: Date
    var toCode: String? = nil

    /// Arrival delay of this leg in minutes (negative = early)
    var arrivalDelay: Int? {
        guard let a = arrival, let s = scheduledArrival else { return nil }
        return Int((a.timeIntervalSince(s) / 60).rounded())
    }

    var normalizedStatus: FlightStatus { FlightStatus(raw: status) }
    var isCanceled: Bool { normalizedStatus == .canceled }

    /// Minimum ground time between arrival and next departure.
    static let turnaround: TimeInterval = 35 * 60

    /// Expected departure delay of our flight caused by a late inbound plane (minutes, 0 if none).
    func expectedDelay(ourDeparture: Date?) -> Int {
        guard !landed, let arr = arrival, let dep = ourDeparture else { return 0 }
        let ready = arr.addingTimeInterval(Self.turnaround)
        return max(0, Int(ready.timeIntervalSince(dep) / 60))
    }

    /// Short line like Flighty: "Zubringer in der Luft aus ORD"
    var headline: String {
        if isCanceled { return String(localized: "Zubringer-Flug \(number) annulliert") }
        if landed { return String(localized: "Flugzeug ist gelandet (aus \(fromCode))") }
        if departed { return String(localized: "Zubringer in der Luft aus \(fromCode)") }
        return String(localized: "Zubringer noch in \(fromCode)")
    }

    /// Arrival times are shown in local time of our departure airport (where the inbound lands).
    func detail(tz: TimeZone) -> String {
        let arr = Fmt.time(arrival, tz)
        if isCanceled { return String(localized: "Flugzeugwechsel oder Verspätung möglich") }
        if landed { return String(localized: "\(number) gelandet um \(arr)") }
        if departed { return String(localized: "\(number) · Landung ca. \(arr)") }
        if let d = departure, d < Date() { return String(localized: "\(number) · Abflug überfällig · Landung ca. \(arr)") }
        return String(localized: "\(number) · Abflug in \(Fmt.countdown(max(0, (departure ?? Date()).timeIntervalSinceNow))) · Landung \(arr)")
    }
}

enum FlightStatus: String {
    case scheduled, delayed, checkIn, boarding, gateClosed, taxiing, departed, enRoute, approaching, arrived, canceled, diverted, unknown

    init(raw: String?) {
        switch raw?.lowercased() ?? "" {
        case "expected", "scheduled": self = .scheduled
        case "delayed": self = .delayed
        case "checkin": self = .checkIn
        case "boarding": self = .boarding
        case "gateclosed": self = .gateClosed
        case "taxiing": self = .taxiing
        case "departed": self = .departed
        case "enroute": self = .enRoute
        case "approaching": self = .approaching
        case "arrived": self = .arrived
        case "canceled", "cancelled", "canceleduncertain": self = .canceled
        case "diverted": self = .diverted
        default: self = .unknown
        }
    }

    var label: String {
        switch self {
        case .scheduled: String(localized: "Planmässig")
        case .delayed: String(localized: "Verspätet")
        case .checkIn: String(localized: "Check-in")
        case .boarding: String(localized: "Boarding")
        case .gateClosed: String(localized: "Gate geschlossen")
        case .taxiing: String(localized: "Rollt zum Start")
        case .departed: String(localized: "Gestartet")
        case .enRoute: String(localized: "In der Luft")
        case .approaching: String(localized: "Im Anflug")
        case .arrived: String(localized: "Gelandet")
        case .canceled: String(localized: "Annulliert")
        case .diverted: String(localized: "Umgeleitet")
        case .unknown: String(localized: "Geplant")
        }
    }

    var isAirborne: Bool { self == .departed || self == .enRoute || self == .approaching }
    var isFinal: Bool { self == .arrived || self == .canceled || self == .diverted }
}

struct Flight: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var number: String
    /// Local departure date, yyyy-MM-dd
    var date: String
    var callSign: String?
    var airlineName: String?
    var airlineIata: String?
    var airlineIcao: String?
    var status: String?
    var departure: FlightEndpoint
    var arrival: FlightEndpoint
    var aircraftModel: String?
    var aircraftReg: String?
    var icao24: String?
    var distanceKm: Double?
    var lastUpdated: Date?
    var lastPosition: LivePosition?
    /// FlightAware flight id (for live positions)
    var faFlightID: String? = nil
    /// FlightAware id of the inbound flight (the plane's previous leg)
    var inboundFAID: String? = nil
    /// The aircraft's previous leg arriving at our departure airport
    var inbound: InboundFlight? = nil
    /// Departure time the user was last told about (so creeping delays are noticed)
    var lastNotifiedDeparture: Date? = nil
    /// Last change on any device (for the sync between devices)
    var modified: Date? = nil
    /// Random id of the public status link shared with family & friends (nil = not shared)
    var shareToken: String? = nil
    /// Booking code (PNR) from the mail – links re-bookings to the flight they replace
    var bookingReference: String? = nil
    /// For a suggestion from a re-booking mail: the stored flight it replaces
    var replacesID: UUID? = nil
    /// Layover the user was last warned about (minutes), so the warning isn't repeated
    var warnedLayover: Int? = nil
    /// Departure gate as reported by AeroDataBox (airport data) – preferred over FlightAware's
    var adbGate: String? = nil
    /// A different departure gate reported by the other source (shown as a hint)
    var gateConflict: String? = nil
    /// Gate / runway times in detail (FlightAware)
    var timetable: Timetable? = nil
    /// What changed and when (gate, times, status …), newest last
    var updates: [FlightUpdate]? = nil
    /// The aircraft's previous legs, newest first ("Wo ist mein Flugzeug?")
    var planeLegs: [InboundFlight]? = nil

    /// Airline codes that were reassigned: the data source still returns the previous owner's name.
    private static let airlineNameFixes: [String: String] = ["QP": "Akasa Air"]

    /// Corrects a known outdated airline name (by the code in the flight number).
    mutating func fixAirlineName() {
        let code = String(number.replacingOccurrences(of: " ", with: "").uppercased().prefix(2))
        if let name = Self.airlineNameFixes[code] { airlineName = name }
    }

    mutating func log(_ text: String, at date: Date = Date()) {
        var list = updates ?? []
        if list.last?.text == text { return }
        list.append(FlightUpdate(date: date, text: text))
        updates = Array(list.suffix(40))
    }
    var notes: String = ""
    var seat: String = ""

    var normalizedStatus: FlightStatus { FlightStatus(raw: status) }

    /// Local arrival day minus local departure day (ZRH 22:40 → BKK 15:30 = +1).
    var arrivalDayOffset: Int {
        guard let d = departure.best, let a = arrival.best else { return 0 }
        func day(_ date: Date, _ tz: TimeZone) -> Int { Int(floor((date.timeIntervalSince1970 + Double(tz.secondsFromGMT(for: date))) / 86400)) }
        return day(a, arrival.tz) - day(d, departure.tz)
    }

    /// Status for display: an old flight whose status was never updated counts as landed.
    var displayStatus: FlightStatus {
        let s = normalizedStatus
        return isPast && !s.isFinal ? .arrived : s
    }

    var sortDate: Date {
        departure.scheduled ?? departure.best ?? Fmt.apiDate.date(from: date) ?? .distantPast
    }

    var computedDistanceKm: Double? {
        if let distanceKm { return distanceKm }
        guard let a = departure.coordinate, let b = arrival.coordinate else { return nil }
        return Geo.distanceKm(a, b)
    }

    var durationMinutes: Int? {
        guard let d = departure.runway ?? departure.best, let a = arrival.runway ?? arrival.best, a > d else { return nil }
        return Int(a.timeIntervalSince(d) / 60)
    }

    func progress(at now: Date = Date()) -> Double {
        if normalizedStatus == .arrived { return 1 }
        guard let d = departure.runway ?? departure.best, let a = arrival.best, a > d else { return 0 }
        return min(max(now.timeIntervalSince(d) / a.timeIntervalSince(d), 0), 1)
    }

    var isInAir: Bool {
        if isPast { return false }
        if normalizedStatus == .taxiing { return false }     // left the gate, still on the ground
        if normalizedStatus.isAirborne { return true }
        if normalizedStatus.isFinal { return false }
        if [.scheduled, .delayed, .checkIn, .boarding, .gateClosed].contains(normalizedStatus),
           departure.runway == nil { return false }
        let p = progress()
        return p > 0 && p < 1
    }

    var isPast: Bool {
        let now = Date()
        // Without times: past only once the day is over (not at 04:00 on the day itself)
        let arrivalRef = arrival.best ?? (departure.best == nil ? sortDate.addingTimeInterval(28 * 3600) : sortDate.addingTimeInterval(4 * 3600))
        switch normalizedStatus {
        case .arrived: return arrivalRef < now.addingTimeInterval(-75 * 60)
        case .canceled: return (departure.best == nil ? arrivalRef : sortDate) < now
        case .diverted: return arrivalRef < now
        default: return arrivalRef < now.addingTimeInterval(-2 * 3600)
        }
    }

    /// A reported position we can trust: not the "0°/0°" placeholder some sources send when they have no fix,
    /// and somewhere near the route (not another aircraft or a stale leg on the other side of the world).
    func isPlausible(_ p: LivePosition) -> Bool {
        if abs(p.lat) < 0.05 && abs(p.lon) < 0.05 { return false }
        guard (-90...90).contains(p.lat), (-180...180).contains(p.lon) else { return false }
        guard let a = departure.coordinate, let b = arrival.coordinate else { return true }
        let route = Geo.distanceKm(a, b)
        let detour = Geo.distanceKm(a, p.coordinate) + Geo.distanceKm(p.coordinate, b)
        return detour < route * 1.6 + 400
    }

    /// Some sources report altitude and speed but 0°/0° as coordinates: the flight data is usable, the place is not.
    static func hasNoCoordinates(_ p: LivePosition) -> Bool { abs(p.lat) < 0.05 && abs(p.lon) < 0.05 }

    /// Fresh altitude / speed data, even when the coordinates are missing (the map then shows the estimated place).
    var liveTelemetry: LivePosition? {
        guard let p = lastPosition, Date().timeIntervalSince(p.timestamp) < 20 * 60,
              isPlausible(p) || Self.hasNoCoordinates(p) else { return nil }
        return p
    }

    /// Live position if it is fresh and plausible.
    var livePosition: LivePosition? {
        guard let p = lastPosition, Date().timeIntervalSince(p.timestamp) < 20 * 60, isPlausible(p) else { return nil }
        return p
    }

    /// Current plane position: live data if fresh, otherwise estimated along the great circle.
    func planePosition(at now: Date = Date()) -> (coordinate: CLLocationCoordinate2D, heading: Double)? {
        guard isInAir else { return nil }
        if let p = lastPosition, now.timeIntervalSince(p.timestamp) < 20 * 60, isPlausible(p) {
            return (p.coordinate, p.heading ?? 0)
        }
        guard let a = departure.coordinate, let b = arrival.coordinate else { return nil }
        let pos = Geo.interpolate(a, b, progress(at: now))
        return (pos, Geo.bearing(pos, b))
    }
}

enum Geo {
    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func angularDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = rad(a.latitude), φ2 = rad(b.latitude)
        let dφ = φ2 - φ1, dλ = rad(b.longitude - a.longitude)
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * asin(min(1, sqrt(h)))
    }

    static func distanceKm(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        angularDistance(a, b) * 6371.0
    }

    static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, _ f: Double) -> CLLocationCoordinate2D {
        let δ = angularDistance(a, b)
        guard δ > 1e-9 else { return a }
        let φ1 = rad(a.latitude), λ1 = rad(a.longitude)
        let φ2 = rad(b.latitude), λ2 = rad(b.longitude)
        let A = sin((1 - f) * δ) / sin(δ)
        let B = sin(f * δ) / sin(δ)
        let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
        let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
        let z = A * sin(φ1) + B * sin(φ2)
        return CLLocationCoordinate2D(latitude: deg(atan2(z, sqrt(x * x + y * y))), longitude: deg(atan2(y, x)))
    }

    static func bearing(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let φ1 = rad(a.latitude), φ2 = rad(b.latitude)
        let dλ = rad(b.longitude - a.longitude)
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        return (deg(atan2(y, x)) + 360).truncatingRemainder(dividingBy: 360)
    }
}

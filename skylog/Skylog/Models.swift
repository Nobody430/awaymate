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

enum FlightStatus: String {
    case scheduled, delayed, checkIn, boarding, gateClosed, departed, enRoute, approaching, arrived, canceled, diverted, unknown

    init(raw: String?) {
        switch raw?.lowercased() ?? "" {
        case "expected", "scheduled": self = .scheduled
        case "delayed": self = .delayed
        case "checkin": self = .checkIn
        case "boarding": self = .boarding
        case "gateclosed": self = .gateClosed
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
        case .scheduled: "Planmässig"
        case .delayed: "Verspätet"
        case .checkIn: "Check-in"
        case .boarding: "Boarding"
        case .gateClosed: "Gate geschlossen"
        case .departed: "Gestartet"
        case .enRoute: "In der Luft"
        case .approaching: "Im Anflug"
        case .arrived: "Gelandet"
        case .canceled: "Annulliert"
        case .diverted: "Umgeleitet"
        case .unknown: "Geplant"
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
    var notes: String = ""
    var seat: String = ""

    var normalizedStatus: FlightStatus { FlightStatus(raw: status) }

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
        if normalizedStatus.isAirborne { return true }
        if normalizedStatus.isFinal { return false }
        if [.scheduled, .delayed, .checkIn, .boarding, .gateClosed].contains(normalizedStatus),
           departure.runway == nil { return false }
        let p = progress()
        return p > 0 && p < 1
    }

    var isPast: Bool {
        let now = Date()
        let arrivalRef = arrival.best ?? sortDate.addingTimeInterval(4 * 3600)
        switch normalizedStatus {
        case .arrived: return arrivalRef < now.addingTimeInterval(-30 * 60)
        case .canceled, .diverted: return sortDate < now
        default: return arrivalRef < now.addingTimeInterval(-2 * 3600)
        }
    }

    /// Current plane position: live data if fresh, otherwise estimated along the great circle.
    func planePosition(at now: Date = Date()) -> (coordinate: CLLocationCoordinate2D, heading: Double)? {
        guard isInAir else { return nil }
        if let p = lastPosition, now.timeIntervalSince(p.timestamp) < 20 * 60 {
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

import Foundation
/// "18:59" in the airport's local time zone (falls back to the phone's zone).
func airportTime(_ date: Date, _ tz: String?) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "de_CH")
    f.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Data shared between the app and its widgets via the App Group.
struct WidgetFlight: Codable, Hashable, Identifiable {
    var id: String
    var number: String
    var from: String
    var to: String
    var fromCity: String
    var toCity: String
    var departure: Date
    var arrival: Date
    var gate: String?
    var terminal: String?
    var status: String
    var delayMinutes: Int
    /// Check-in desks (shown until departure)
    var checkIn: String? = nil
}

enum SharedStore {
    static let group = "group.com.nobody430.skylog"
    private static let key = "upcomingFlights"

    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }

    static func write(_ flights: [WidgetFlight]) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        defaults.set(try? e.encode(flights), forKey: key)
    }

    static func read() -> [WidgetFlight] {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        guard let data = defaults.data(forKey: key), let list = try? d.decode([WidgetFlight].self, from: data) else { return [] }
        return list
    }
}

#if canImport(ActivityKit)
struct FlightActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var status: String
        var departure: Date
        var arrival: Date
        var gate: String?
        var terminal: String?
        var delayMinutes: Int
        var belt: String?
        var inAir: Bool
        /// e.g. "Zubringer in der Luft aus ORD" (optional, may be missing in server pushes)
        var inbound: String? = nil
        var inboundWarn: Bool? = nil
        /// Arrival delay in minutes (negative = early); nil when unknown
        var arrivalDelay: Int? = nil
        /// true once the flight has landed (optional, may be missing in server pushes – then `status` is checked)
        var landed: Bool? = nil
        /// Check-in desks; only set until the flight has left (optional, may be missing in server pushes)
        var checkIn: String? = nil
        /// Expected touch-down on the runway (the arrival time is at the gate); optional, may be missing in server pushes
        var landing: Date? = nil
    }

    var flightID: String
    var flightNumber: String
    var from: String
    var to: String
    var fromCity: String
    var toCity: String
    /// Airport time zones, so times show in local airport time (like on the boarding pass)
    var fromTZ: String? = nil
    var toTZ: String? = nil
}
#endif

import Foundation
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
    }

    var flightID: String
    var flightNumber: String
    var from: String
    var to: String
    var fromCity: String
    var toCity: String
}
#endif

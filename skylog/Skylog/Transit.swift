import Foundation

/// Swiss public transport connections via transport.opendata.ch (free, no key).
enum Transit {
    /// Train/bus stop names of Swiss airports
    static let airportStations: [String: String] = [
        "ZRH": "Zürich Flughafen",
        "GVA": "Genève-Aéroport",
    ]

    struct Connection: Identifiable, Hashable {
        let id = UUID()
        let departure: Date
        let arrival: Date
        let fromName: String
        let toName: String
        let platform: String?
        let products: [String]
        let transfers: Int
    }

    private static let iso: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return f
    }()

    static func connections(from: String, to: String, at date: Date, arriveBy: Bool) async throws -> [Connection] {
        let d = DateFormatter()
        d.locale = Locale(identifier: "en_US_POSIX")
        d.timeZone = TimeZone(identifier: "Europe/Zurich")
        d.dateFormat = "yyyy-MM-dd"
        let t = DateFormatter()
        t.locale = d.locale
        t.timeZone = d.timeZone
        t.dateFormat = "HH:mm"

        var c = URLComponents(string: "https://transport.opendata.ch/v1/connections")!
        c.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "date", value: d.string(from: date)),
            URLQueryItem(name: "time", value: t.string(from: date)),
            URLQueryItem(name: "isArrivalTime", value: arriveBy ? "1" : "0"),
            URLQueryItem(name: "limit", value: "4"),
        ]
        let (data, _) = try await URLSession.shared.data(from: c.url!)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["connections"] as? [[String: Any]] else { return [] }

        return list.compactMap { conn -> Connection? in
            guard let f = conn["from"] as? [String: Any], let dest = conn["to"] as? [String: Any],
                  let depS = f["departure"] as? String, let arrS = dest["arrival"] as? String,
                  let dep = iso.date(from: depS), let arr = iso.date(from: arrS) else { return nil }
            let fromName = (f["station"] as? [String: Any])?["name"] as? String ?? from
            let toName = (dest["station"] as? [String: Any])?["name"] as? String ?? to
            return Connection(departure: dep, arrival: arr, fromName: fromName, toName: toName,
                              platform: f["platform"] as? String, products: conn["products"] as? [String] ?? [],
                              transfers: conn["transfers"] as? Int ?? 0)
        }
    }
}

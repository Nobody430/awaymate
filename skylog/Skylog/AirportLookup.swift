import Foundation

/// Looks up airport details (city, coordinates, country, time zone) by IATA code – cached forever.
enum AirportLookup {
    struct Info: Codable {
        var name: String?
        var city: String?
        var countryCode: String?
        var lat: Double?
        var lon: Double?
        var timeZone: String?
    }

    private static func cacheKey(_ code: String) -> String { "airport-\(code.uppercased())" }

    static func fill(_ e: FlightEndpoint, code: String) async -> FlightEndpoint {
        guard let info = await info(code) else { return e }
        var e = e
        e.name = e.name ?? info.name
        e.city = e.city ?? info.city
        e.countryCode = e.countryCode ?? info.countryCode
        e.lat = e.lat ?? info.lat
        e.lon = e.lon ?? info.lon
        e.timeZone = e.timeZone ?? info.timeZone
        return e
    }

    /// Bundled airport database (github.com/mwgg/Airports, MIT licence) – no API calls needed.
    private static let bundled: [String: [Any]] = {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [Any]] else { return [:] }
        return dict
    }()

    static func bundledInfo(_ code: String) -> Info? {
        guard let a = bundled[code.uppercased()], a.count >= 6 else { return nil }
        return Info(name: a[0] as? String, city: a[1] as? String, countryCode: (a[2] as? String)?.uppercased(),
                    lat: (a[3] as? NSNumber)?.doubleValue, lon: (a[4] as? NSNumber)?.doubleValue,
                    timeZone: (a[5] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }

    static func info(_ code: String) async -> Info? {
        if let local = bundledInfo(code) { return local }
        let key = cacheKey(code)
        if let data = UserDefaults.standard.data(forKey: key), let i = try? JSONDecoder().decode(Info.self, from: data) { return i }
        var result: Info?
        if FlightAware.hasKey, let a = await FlightAware.airport(code.uppercased()) {
            result = Info(name: a.name, city: a.city, countryCode: a.country_code?.uppercased(), lat: a.latitude, lon: a.longitude, timeZone: a.timezone)
        } else if Settings.hasKey {
            result = try? await aeroDataBox(code)
        }
        if let result, let data = try? JSONEncoder().encode(result) { UserDefaults.standard.set(data, forKey: key) }
        return result
    }

    private struct ADBAirportFull: Decodable {
        let shortName: String?
        let fullName: String?
        let municipalityName: String?
        let countryCode: String?
        let timeZone: String?
        let location: ADBCoord?
    }

    private static func aeroDataBox(_ code: String) async throws -> Info? {
        var request = URLRequest(url: URL(string: "https://\(AeroDataBox.host)/airports/iata/\(code.uppercased())")!)
        request.setValue(Settings.apiKey, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(AeroDataBox.host, forHTTPHeaderField: "X-RapidAPI-Host")
        let (data, response) = try await URLSession.shared.data(for: request)
        Usage.increment()
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        let a = try JSONDecoder().decode(ADBAirportFull.self, from: data)
        return Info(name: a.shortName ?? a.fullName, city: a.municipalityName, countryCode: a.countryCode?.uppercased(),
                    lat: a.location?.lat, lon: a.location?.lon, timeZone: a.timeZone)
    }
}

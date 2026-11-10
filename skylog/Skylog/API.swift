import Foundation

enum APIError: LocalizedError {
    case noKey, notFound, http(Int), quota, rateLimited

    var errorDescription: String? {
        switch self {
        case .noKey: "Kein API-Key hinterlegt. Bitte in den Einstellungen eintragen."
        case .notFound: "Kein Flug gefunden. Flugnummer und Datum prüfen."
        case .quota: "API-Kontingent aufgebraucht (Gratis-Limit erreicht)."
        case .rateLimited: "Zu viele Abfragen in kurzer Zeit – gleich nochmal versuchen."
        case .http(let code): "Serverfehler (\(code))."
        }
    }
}

// MARK: - AeroDataBox (flight status, gates, times)

enum AeroDataBox {
    static let host = "aerodatabox.p.rapidapi.com"

    static func search(number: String, date: Date) async throws -> [Flight] {
        let num = number.replacingOccurrences(of: " ", with: "").uppercased()
        let dateString = Fmt.apiDate.string(from: date)
        let items = try await fetch("/flights/number/\(num)/\(dateString)", extra: [
            URLQueryItem(name: "withLocation", value: "true"),
            URLQueryItem(name: "dateLocalRole", value: "Departure"),
        ])
        return items.map { $0.toFlight(fallbackNumber: num, date: dateString) }
    }

    /// All flights of one aircraft (registration) on a local date – used to find the inbound leg.
    static func flights(registration reg: String, date: Date) async throws -> [Flight] {
        let r = reg.replacingOccurrences(of: " ", with: "").uppercased()
        let dateString = Fmt.apiDate.string(from: date)
        let items = try await fetch("/flights/reg/\(r)/\(dateString)", extra: [])
        return items.map { $0.toFlight(fallbackNumber: $0.number ?? "?", date: dateString) }
    }

    private static func fetch(_ path: String, extra: [URLQueryItem]) async throws -> [ADBFlight] {
        let key = Settings.apiKey
        guard !key.isEmpty else { throw APIError.noKey }
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = host
        comps.path = path
        comps.queryItems = [URLQueryItem(name: "withAircraftImage", value: "false")] + extra
        guard let url = comps.url else { throw APIError.notFound }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(host, forHTTPHeaderField: "X-RapidAPI-Host")

        let (data, response) = try await URLSession.shared.data(for: request)
        Usage.increment()
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300 where code != 204: break
        case 204, 404: throw APIError.notFound
        case 429: throw APIError.quota
        default: throw APIError.http(code)
        }
        let items = try JSONDecoder().decode([ADBFlight].self, from: data)
        if items.isEmpty { throw APIError.notFound }
        return items
    }
}

struct ADBFlight: Decodable {
    let number: String?
    let callSign: String?
    let status: String?
    let departure: ADBMovement?
    let arrival: ADBMovement?
    let airline: ADBAirline?
    let aircraft: ADBAircraft?
    let greatCircleDistance: ADBDistance?
    let location: ADBLocation?

    func toFlight(fallbackNumber: String, date: String) -> Flight {
        var flight = Flight(
            number: number ?? fallbackNumber,
            date: date,
            departure: departure?.endpoint ?? FlightEndpoint(),
            arrival: arrival?.endpoint ?? FlightEndpoint()
        )
        flight.callSign = callSign
        flight.status = status
        flight.airlineName = airline?.name
        flight.airlineIata = airline?.iata
        flight.airlineIcao = airline?.icao
        flight.aircraftModel = aircraft?.model
        flight.aircraftReg = aircraft?.reg
        flight.icao24 = aircraft?.modeS?.lowercased()
        flight.distanceKm = greatCircleDistance?.km
        flight.lastUpdated = Date()
        if let loc = location, let lat = loc.lat, let lon = loc.lon {
            flight.lastPosition = LivePosition(
                lat: lat, lon: lon,
                altitudeM: loc.altitude?.meter,
                speedKmh: loc.groundSpeed?.kmPerHour,
                heading: loc.trueTrack?.deg,
                verticalRate: nil,
                onGround: false,
                timestamp: Fmt.parse(loc.reportedAtUtc) ?? Date(),
                source: "AeroDataBox"
            )
        }
        return flight
    }
}

struct ADBMovement: Decodable {
    let airport: ADBAirport?
    let scheduledTime: ADBTime?
    let revisedTime: ADBTime?
    let predictedTime: ADBTime?
    let runwayTime: ADBTime?
    let terminal: String?
    let gate: String?
    let checkInDesk: String?
    let baggageBelt: String?

    var endpoint: FlightEndpoint {
        FlightEndpoint(
            iata: airport?.iata,
            icao: airport?.icao,
            name: airport?.shortName ?? airport?.name,
            city: airport?.municipalityName,
            countryCode: airport?.countryCode,
            lat: airport?.location?.lat,
            lon: airport?.location?.lon,
            timeZone: airport?.timeZone,
            scheduled: scheduledTime?.date,
            revised: revisedTime?.date,
            predicted: predictedTime?.date,
            runway: runwayTime?.date,
            terminal: terminal,
            gate: gate,
            checkInDesk: checkInDesk,
            baggageBelt: baggageBelt
        )
    }
}

struct ADBTime: Decodable {
    let utc: String?
    let local: String?
    var date: Date? { Fmt.parse(utc) ?? Fmt.parse(local) }
}

struct ADBAirport: Decodable {
    let icao, iata, name, shortName, municipalityName, countryCode, timeZone: String?
    let location: ADBCoord?
}

struct ADBCoord: Decodable { let lat, lon: Double? }
struct ADBAirline: Decodable { let name, iata, icao: String? }
struct ADBAircraft: Decodable { let reg, modeS, model: String? }
struct ADBDistance: Decodable { let km: Double? }
struct ADBAltitude: Decodable { let meter: Double? }
struct ADBSpeed: Decodable { let kmPerHour: Double? }
struct ADBTrack: Decodable { let deg: Double? }

struct ADBLocation: Decodable {
    let lat, lon: Double?
    let altitude: ADBAltitude?
    let groundSpeed: ADBSpeed?
    let trueTrack: ADBTrack?
    let reportedAtUtc: String?
}

// MARK: - OpenSky (free live ADS-B positions)

enum OpenSky {
    static func position(icao24: String) async throws -> LivePosition? {
        guard let url = URL(string: "https://opensky-network.org/api/states/all?icao24=\(icao24.lowercased())") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = obj["states"] as? [[Any]],
              let s = states.first else { return nil }

        func num(_ i: Int) -> Double? { i < s.count ? (s[i] as? NSNumber)?.doubleValue : nil }
        guard let lon = num(5), let lat = num(6) else { return nil }
        let onGround = (s.count > 8 ? s[8] as? Bool : nil) ?? false
        return LivePosition(
            lat: lat, lon: lon,
            altitudeM: num(7) ?? num(13),
            speedKmh: num(9).map { $0 * 3.6 },
            heading: num(10),
            verticalRate: num(11),
            onGround: onGround,
            timestamp: num(4).map { Date(timeIntervalSince1970: $0) } ?? Date(),
            source: "OpenSky"
        )
    }
}

// MARK: - Settings & usage

enum Settings {
    static var apiKey: String {
        (UserDefaults.standard.string(forKey: "apiKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var hasKey: Bool { !apiKey.isEmpty }
    static var autoRefresh: Bool { bool("autoRefresh") }
    static var notifyChanges: Bool { bool("notifyChanges") }
    static var reminders: Bool { bool("reminders") }

    private static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}

enum Usage {
    static var key: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return "usage-" + f.string(from: Date())
    }
    static var thisMonth: Int { UserDefaults.standard.integer(forKey: key) }
    static func increment() { UserDefaults.standard.set(thisMonth + 1, forKey: key) }
}

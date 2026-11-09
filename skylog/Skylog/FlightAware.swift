import Foundation

/// Which flight data service to use.
enum FlightProvider: String, CaseIterable, Identifiable {
    case aerodatabox, flightaware
    var id: String { rawValue }
    var label: String { self == .aerodatabox ? "AeroDataBox (RapidAPI)" : "FlightAware AeroAPI" }

    static var current: FlightProvider {
        FlightProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .aerodatabox
    }
}

/// Entry point for flight lookups – dispatches to the selected provider.
enum FlightData {
    static var isConfigured: Bool {
        switch FlightProvider.current {
        case .aerodatabox: Settings.hasKey
        case .flightaware: FlightAware.hasKey
        }
    }

    static func search(number: String, date: Date) async throws -> [Flight] {
        if FlightProvider.current == .flightaware {
            return try await FlightAware.search(number: number, date: date)
        }
        return try await AeroDataBox.search(number: number, date: date)
    }
}

/// FlightAware AeroAPI v4 (Personal tier: monthly free credit, then pay per query).
enum FlightAware {
    static let base = "https://aeroapi.flightaware.com/aeroapi"

    static var apiKey: String {
        (UserDefaults.standard.string(forKey: "flightawareKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static var hasKey: Bool { !apiKey.isEmpty }

    private static func get(_ path: String, query: [URLQueryItem] = []) async throws -> Data {
        guard hasKey else { throw APIError.noKey }
        var c = URLComponents(string: base + path)!
        if !query.isEmpty { c.queryItems = query }
        var request = URLRequest(url: c.url!)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-apikey")
        let (data, response) = try await URLSession.shared.data(for: request)
        Usage.increment()
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return data
        case 400, 404: throw APIError.notFound
        case 401, 403: throw APIError.http(code)
        case 429: throw APIError.quota
        default: throw APIError.http(code)
        }
    }

    // MARK: Models

    struct FAAirport: Decodable {
        let code: String?
        let code_iata: String?
        let code_icao: String?
        let timezone: String?
        let name: String?
        let city: String?
    }

    struct FAFlight: Decodable {
        let ident: String?
        let ident_iata: String?
        let fa_flight_id: String?
        let operator_iata: String?
        let atc_ident: String?
        let registration: String?
        let aircraft_type: String?
        let origin: FAAirport?
        let destination: FAAirport?
        let scheduled_out: String?, estimated_out: String?, actual_out: String?
        let scheduled_off: String?, estimated_off: String?, actual_off: String?
        let scheduled_on: String?, estimated_on: String?, actual_on: String?
        let scheduled_in: String?, estimated_in: String?, actual_in: String?
        let gate_origin: String?, gate_destination: String?
        let terminal_origin: String?, terminal_destination: String?
        let baggage_claim: String?
        let cancelled: Bool?
        let diverted: Bool?
        let route_distance: Double?
        let status: String?
    }

    private struct FlightsResponse: Decodable { let flights: [FAFlight] }

    struct AirportInfo: Codable {
        let latitude: Double?
        let longitude: Double?
        let country_code: String?
        let timezone: String?
        let name: String?
        let city: String?
    }

    private static let iso = ISO8601DateFormatter()
    private static func date(_ s: String?) -> Date? { s.flatMap { iso.date(from: $0) } }

    // MARK: Airports (cached – each airport costs one query only once)

    static func airport(_ code: String) async -> AirportInfo? {
        let key = "fa-airport-\(code)"
        if let data = UserDefaults.standard.data(forKey: key), let a = try? JSONDecoder().decode(AirportInfo.self, from: data) { return a }
        guard let data = try? await get("/airports/\(code)"),
              let a = try? JSONDecoder().decode(AirportInfo.self, from: data) else { return nil }
        UserDefaults.standard.set(data, forKey: key)
        return a
    }

    // MARK: Search

    static func search(number: String, date: Date) async throws -> [Flight] {
        let ident = number.replacingOccurrences(of: " ", with: "").uppercased()
        let day = Calendar.current.startOfDay(for: date)
        let start = day.addingTimeInterval(-14 * 3600), end = day.addingTimeInterval(38 * 3600)
        var items = [URLQueryItem(name: "ident_type", value: "designator")]
        let now = Date()
        // AeroAPI only allows a limited window around today on this endpoint
        if start > now.addingTimeInterval(-10 * 86400) && end < now.addingTimeInterval(2 * 86400) {
            items += [URLQueryItem(name: "start", value: iso.string(from: start)), URLQueryItem(name: "end", value: iso.string(from: end))]
        }
        let data = try await get("/flights/\(ident)", query: items)
        let all = try JSONDecoder().decode(FlightsResponse.self, from: data).flights
        let dateString = Fmt.apiDate.string(from: date)

        var result: [Flight] = []
        for fa in all {
            guard let schedOut = Self.date(fa.scheduled_out ?? fa.scheduled_off) else { continue }
            let tz = fa.origin?.timezone.flatMap(TimeZone.init(identifier:)) ?? .current
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = tz
            f.dateFormat = "yyyy-MM-dd"
            guard f.string(from: schedOut) == dateString else { continue }
            result.append(await convert(fa, date: dateString, fallbackNumber: ident))
        }
        if result.isEmpty { throw APIError.notFound }
        return result
    }

    static func convert(_ fa: FAFlight, date: String, fallbackNumber: String) async -> Flight {
        func endpoint(_ a: FAAirport?, scheduled: String?, estimated: String?, actual: String?,
                      gate: String?, terminal: String?, belt: String?) async -> FlightEndpoint {
            var info: AirportInfo?
            if let code = a?.code ?? a?.code_icao { info = await airport(code) }
            return FlightEndpoint(
                iata: a?.code_iata, icao: a?.code_icao, name: a?.name ?? info?.name, city: a?.city ?? info?.city,
                countryCode: info?.country_code?.uppercased(), lat: info?.latitude, lon: info?.longitude,
                timeZone: a?.timezone ?? info?.timezone,
                scheduled: Self.date(scheduled), revised: Self.date(estimated), predicted: nil, runway: Self.date(actual),
                terminal: terminal, gate: gate, checkInDesk: nil, baggageBelt: belt)
        }
        let dep = await endpoint(fa.origin, scheduled: fa.scheduled_out ?? fa.scheduled_off,
                                 estimated: fa.estimated_out ?? fa.estimated_off, actual: fa.actual_out ?? fa.actual_off,
                                 gate: fa.gate_origin, terminal: fa.terminal_origin, belt: nil)
        let arr = await endpoint(fa.destination, scheduled: fa.scheduled_in ?? fa.scheduled_on,
                                 estimated: fa.estimated_in ?? fa.estimated_on, actual: fa.actual_in ?? fa.actual_on,
                                 gate: fa.gate_destination, terminal: fa.terminal_destination, belt: fa.baggage_claim)

        let status: String
        if fa.cancelled == true { status = "Canceled" }
        else if fa.diverted == true { status = "Diverted" }
        else if fa.actual_in != nil || fa.actual_on != nil { status = "Arrived" }
        else if fa.actual_off != nil { status = "EnRoute" }
        else if fa.actual_out != nil { status = "Departed" }
        else if (dep.delayMinutes ?? 0) >= 15 { status = "Delayed" }
        else { status = "Expected" }

        var flight = Flight(number: fa.ident_iata ?? fallbackNumber, date: date, departure: dep, arrival: arr)
        flight.callSign = fa.atc_ident ?? fa.ident
        flight.status = status
        flight.airlineIata = fa.operator_iata
        flight.aircraftModel = fa.aircraft_type
        flight.aircraftReg = fa.registration
        flight.faFlightID = fa.fa_flight_id
        flight.distanceKm = fa.route_distance.map { $0 * 1.60934 }
        flight.lastUpdated = Date()
        return flight
    }

    // MARK: Live position

    private struct PositionResponse: Decodable {
        struct Pos: Decodable {
            let latitude: Double
            let longitude: Double
            let altitude: Double?
            let groundspeed: Double?
            let heading: Double?
            let timestamp: String?
        }
        let last_position: Pos?
    }

    static func position(_ faFlightID: String) async throws -> LivePosition? {
        let data = try await get("/flights/\(faFlightID)/position")
        guard let p = try JSONDecoder().decode(PositionResponse.self, from: data).last_position else { return nil }
        return LivePosition(lat: p.latitude, lon: p.longitude,
                            altitudeM: p.altitude.map { $0 * 100 * 0.3048 },
                            speedKmh: p.groundspeed.map { $0 * 1.852 },
                            heading: p.heading, verticalRate: nil, onGround: false,
                            timestamp: Self.date(p.timestamp) ?? Date(), source: "FlightAware")
    }
}

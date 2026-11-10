import Foundation

/// Which flight data service to use.
enum FlightProvider: String, CaseIterable, Identifiable {
    case aerodatabox, flightaware, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aerodatabox: "AeroDataBox (RapidAPI)"
        case .flightaware: "FlightAware AeroAPI"
        case .both: "Beide kombiniert (empfohlen)"
        }
    }

    static var current: FlightProvider {
        FlightProvider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .aerodatabox
    }
}

/// Entry point for flight lookups – dispatches to the selected provider(s).
enum FlightData {
    static var isConfigured: Bool {
        switch FlightProvider.current {
        case .aerodatabox: Settings.hasKey
        case .flightaware: FlightAware.hasKey
        case .both: Settings.hasKey || FlightAware.hasKey
        }
    }

    static func search(number: String, date: Date, stored: Flight? = nil) async throws -> [Flight] {
        switch FlightProvider.current {
        case .flightaware: return try await FlightAware.search(number: number, date: date)
        case .aerodatabox: return try await adb(number: number, date: date)
        case .both: return try await combined(number: number, date: date, stored: stored)
        }
    }

    /// AeroDataBox is usable: key present and its quota not known to be used up.
    static var adbAvailable: Bool {
        Settings.hasKey && Date() > (UserDefaults.standard.object(forKey: "adbPausedUntil") as? Date ?? .distantPast)
    }

    static func pauseADB() { UserDefaults.standard.set(Date().addingTimeInterval(6 * 3600), forKey: "adbPausedUntil") }

    /// AeroDataBox query; remembers an exhausted quota so we stop asking for 6 h.
    private static func adb(number: String, date: Date) async throws -> [Flight] {
        do { return try await AeroDataBox.search(number: number, date: date) } catch {
            if case APIError.quota = error { pauseADB() }
            throw error
        }
    }

    private static var lastEnrich: [String: Date] = [:]
    /// Previous legs of the aircraft found by the last inbound lookup (picked up by the store)
    static var lastLegs: [UUID: [InboundFlight]] = [:]

    /// FlightAware for the next ~2 days (best live data), AeroDataBox for flights further ahead.
    /// Each falls back to the other; close to departure / after landing, missing fields are filled from AeroDataBox
    /// (at most every 30 min per flight, and only if the stored flight doesn't have them yet).
    private static func combined(number: String, date: Date, stored: Flight?) async throws -> [Flight] {
        let near = abs(date.timeIntervalSinceNow) < 2 * 86400
        let faFirst = FlightAware.hasKey && (near || !adbAvailable)
        var results: [Flight]
        if faFirst {
            do { results = try await FlightAware.search(number: number, date: date) } catch {
                if case APIError.rateLimited = error { throw error }
                guard adbAvailable else { throw error }
                return try await adb(number: number, date: date)
            }
        } else {
            guard adbAvailable else { throw Settings.hasKey ? APIError.quota : APIError.noKey }
            do { return try await adb(number: number, date: date) } catch {
                guard FlightAware.hasKey else { throw error }
                return try await FlightAware.search(number: number, date: date)
            }
        }
        guard adbAvailable, let first = results.first else { return results }
        let known = stored.map { merge(first, with: $0) } ?? first
        let key = FlightStore.normalizedNumber(number) + "|" + Fmt.apiDate.string(from: date)
        guard needsEnrichment(known), Date().timeIntervalSince(lastEnrich[key] ?? .distantPast) > 30 * 60 else { return results }
        lastEnrich[key] = Date()
        if let extra = try? await adb(number: number, date: date) {
            results = results.map { f in
                guard let other = extra.first(where: { $0.departure.code == f.departure.code }) ?? extra.first else { return f }
                var m = merge(f, with: other)
                // Gates, terminals, desks and belts are airport data: AeroDataBox gets them from the airports,
                // FlightAware's are often outdated outside North America. Prefer AeroDataBox, remember the difference.
                if let g = other.departure.gate, !g.isEmpty {
                    m.adbGate = g
                    m.gateConflict = (f.departure.gate != nil && f.departure.gate != g) ? f.departure.gate : nil
                    m.departure.gate = g
                }
                if let t = other.departure.terminal, !t.isEmpty { m.departure.terminal = t }
                if let t = other.arrival.terminal, !t.isEmpty { m.arrival.terminal = t }
                if let g = other.arrival.gate, !g.isEmpty { m.arrival.gate = g }
                if let b = other.arrival.baggageBelt, !b.isEmpty { m.arrival.baggageBelt = b }
                return m
            }
        }
        return results
    }

    /// Only spend an AeroDataBox query when something useful is missing at the right moment.
    private static func needsEnrichment(_ f: Flight) -> Bool {
        let now = Date()
        if f.icao24 == nil && f.isInAir { return true }
        if let dep = f.departure.best, dep.timeIntervalSince(now) < 3 * 3600, dep > now.addingTimeInterval(-30 * 60),
           f.departure.runway == nil, f.departure.gate == nil || f.departure.terminal == nil { return true }
        // Cross-check the gate with the airport data in the last 2 h (and keep checking while the sources disagree)
        if let dep = f.departure.best, dep.timeIntervalSince(now) < 2 * 3600, dep > now, f.departure.runway == nil,
           f.adbGate == nil || f.gateConflict != nil { return true }
        if f.normalizedStatus == .arrived, f.arrival.baggageBelt == nil,
           let arr = f.arrival.best, now.timeIntervalSince(arr) < 2 * 3600 { return true }
        return false
    }

    /// Fills empty fields of `a` with values from `b`.
    static func merge(_ a: Flight, with b: Flight) -> Flight {
        var f = a
        func fill(_ e: inout FlightEndpoint, _ o: FlightEndpoint) {
            e.gate = e.gate ?? o.gate
            e.terminal = e.terminal ?? o.terminal
            e.checkInDesk = e.checkInDesk ?? o.checkInDesk
            e.baggageBelt = e.baggageBelt ?? o.baggageBelt
            e.name = e.name ?? o.name
            e.city = e.city ?? o.city
            e.countryCode = e.countryCode ?? o.countryCode
            e.lat = e.lat ?? o.lat
            e.lon = e.lon ?? o.lon
            e.timeZone = e.timeZone ?? o.timeZone
        }
        fill(&f.departure, b.departure)
        fill(&f.arrival, b.arrival)
        f.icao24 = f.icao24 ?? b.icao24
        f.aircraftReg = f.aircraftReg ?? b.aircraftReg
        f.aircraftModel = f.aircraftModel ?? b.aircraftModel
        f.airlineName = f.airlineName ?? b.airlineName
        f.airlineIata = f.airlineIata ?? b.airlineIata
        f.airlineIcao = f.airlineIcao ?? b.airlineIcao
        f.faFlightID = f.faFlightID ?? b.faFlightID
        f.timetable = f.timetable ?? b.timetable
        f.adbGate = f.adbGate ?? b.adbGate
        f.updates = f.updates ?? b.updates
        f.planeLegs = f.planeLegs ?? b.planeLegs
        f.callSign = f.callSign ?? b.callSign
        f.distanceKm = f.distanceKm ?? b.distanceKm
        f.lastPosition = f.lastPosition ?? b.lastPosition
        f.inboundFAID = f.inboundFAID ?? b.inboundFAID
        return f
    }

    // MARK: Inbound aircraft

    /// Previous leg of our aircraft: FlightAware knows it directly (inbound id),
    /// AeroDataBox via the aircraft registration's flights of the day.
    static func inbound(for f: Flight) async throws -> InboundFlight? {
        if FlightAware.hasKey, FlightProvider.current != .aerodatabox {
            // With the registration, one query gives the inbound leg and the legs before it
            if let reg = f.aircraftReg, !reg.isEmpty, let dep = f.departure.scheduled ?? f.departure.best,
               let legs = try? await FlightAware.planeLegs(registration: reg, before: dep),
               let i = legs.first(where: { $0.toCode == f.departure.code && ($0.scheduledArrival ?? .distantPast) > dep.addingTimeInterval(-18 * 3600) }) {
                lastLegs[f.id] = Array(legs.prefix(4))
                return i
            }
            if let id = f.inboundFAID, let i = try? await FlightAware.inbound(id) { return i }
        }
        guard FlightProvider.current != .flightaware, adbAvailable, let reg = f.aircraftReg, !reg.isEmpty,
              let ourDep = f.departure.scheduled ?? f.departure.best else { return nil }
        var legs: [Flight] = []
        let local = Fmt.apiDate.date(from: f.date) ?? ourDep
        func isCandidate(_ l: Flight) -> Bool {
            l.arrival.code == f.departure.code && FlightStore.normalizedNumber(l.number) != FlightStore.normalizedNumber(f.number)
                && (l.arrival.scheduled ?? .distantFuture) < ourDep
        }
        for day in [local, local.addingTimeInterval(-86400)] {
            do { legs += try await AeroDataBox.flights(registration: reg, date: day) } catch {
                if case APIError.quota = error { pauseADB(); break }
            }
            if legs.contains(where: isCandidate) { break }
        }
        // latest leg that arrives at our departure airport before we leave
        let candidates = legs.filter(isCandidate)
        guard let leg = candidates.max(by: { ($0.arrival.scheduled ?? .distantPast) < ($1.arrival.scheduled ?? .distantPast) })
        else { return nil }
        let st = leg.normalizedStatus
        let landed = st == .arrived || leg.arrival.runway != nil
        return InboundFlight(
            number: leg.number, fromCode: leg.departure.code, fromCity: leg.departure.city,
            status: leg.status, departure: leg.departure.runway ?? leg.departure.best,
            departed: landed || st.isAirborne || leg.departure.runway != nil,
            arrival: leg.arrival.best, scheduledArrival: leg.arrival.scheduled,
            landed: landed, updated: Date())
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
        case 429: throw APIError.rateLimited   // AeroAPI: per-minute limit, not a monthly quota
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
        let inbound_fa_flight_id: String?
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

    static func airport(_ code: String, iata: String? = nil) async -> AirportInfo? {
        // the bundled database is free – only ask FlightAware for airports it doesn't know
        if let b = AirportLookup.bundledInfo(iata ?? code), b.lat != nil {
            return AirportInfo(latitude: b.lat, longitude: b.lon, country_code: b.countryCode, timezone: b.timeZone, name: b.name, city: b.city)
        }
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
            if let code = a?.code ?? a?.code_icao ?? a?.code_iata { info = await airport(code, iata: a?.code_iata) }
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
        flight.inboundFAID = fa.inbound_fa_flight_id
        let tt = Timetable(
            outScheduled: Self.date(fa.scheduled_out), outEstimated: Self.date(fa.estimated_out), outActual: Self.date(fa.actual_out),
            offScheduled: Self.date(fa.scheduled_off), offEstimated: Self.date(fa.estimated_off), offActual: Self.date(fa.actual_off),
            onScheduled: Self.date(fa.scheduled_on), onEstimated: Self.date(fa.estimated_on), onActual: Self.date(fa.actual_on),
            inScheduled: Self.date(fa.scheduled_in), inEstimated: Self.date(fa.estimated_in), inActual: Self.date(fa.actual_in))
        if !tt.isEmpty { flight.timetable = tt }
        flight.distanceKm = fa.route_distance.map { $0 * 1.60934 }
        flight.lastUpdated = Date()
        return flight
    }

    // MARK: Airport delays

    struct AirportDelay {
        var minutes: Int
        var reasons: [String]
    }

    private struct DelayResponse: Decodable {
        struct Reason: Decodable { let reason: String?; let category: String?; let delay_secs: Double? }
        let delay_secs: Double?
        let category: String?
        let reasons: [Reason]?
    }

    private static var delayCache: [String: (at: Date, value: AirportDelay?)] = [:]

    /// Current general delay at an airport (nil = none reported). One query per airport every 30 min at most.
    static func airportDelay(_ code: String) async -> AirportDelay? {
        if let c = delayCache[code], Date().timeIntervalSince(c.at) < 30 * 60 { return c.value }
        var value: AirportDelay? = nil
        if let data = try? await get("/airports/\(code)/delays"),
           let r = try? JSONDecoder().decode(DelayResponse.self, from: data), let secs = r.delay_secs, secs >= 300 {
            let reasons = (r.reasons ?? []).compactMap { $0.reason ?? $0.category }
            value = AirportDelay(minutes: Int(secs / 60), reasons: Array(Set(reasons)).sorted())
        }
        delayCache[code] = (Date(), value)
        return value
    }

    // MARK: Inbound aircraft

    /// Status of the inbound flight (one query, no airport lookups).
    static func inbound(_ faFlightID: String) async throws -> InboundFlight? {
        let data = try await get("/flights/\(faFlightID)")
        guard let fa = try JSONDecoder().decode(FlightsResponse.self, from: data).flights.first else { return nil }
        return inbound(from: fa)
    }

    /// Fallback when FlightAware gives no inbound id: the aircraft's recent legs by registration –
    /// the latest one that arrives at our departure airport before we leave.
    static func inbound(registration: String, arrivingAt code: String, before dep: Date) async throws -> InboundFlight? {
        try await planeLegs(registration: registration, before: dep).first {
            $0.toCode == code && ($0.scheduledArrival ?? .distantPast) > dep.addingTimeInterval(-18 * 3600)
        }
    }

    /// The aircraft's legs before `dep`, newest first (one query).
    static func planeLegs(registration: String, before dep: Date) async throws -> [InboundFlight] {
        let reg = registration.replacingOccurrences(of: " ", with: "").uppercased()
        let data = try await get("/flights/\(reg)", query: [URLQueryItem(name: "ident_type", value: "registration")])
        return try JSONDecoder().decode(FlightsResponse.self, from: data).flights
            .filter { fa in (date(fa.scheduled_in ?? fa.scheduled_on)).map { $0 < dep } ?? false }
            .map(inbound(from:))
            .sorted { ($0.scheduledArrival ?? .distantPast) > ($1.scheduledArrival ?? .distantPast) }
    }

    private static func inbound(from fa: FAFlight) -> InboundFlight {
        let landed = fa.actual_on != nil || fa.actual_in != nil
        return InboundFlight(
            number: fa.ident_iata ?? fa.ident ?? "?",
            fromCode: fa.origin?.code_iata ?? fa.origin?.code ?? "?",
            fromCity: fa.origin?.city,
            status: fa.cancelled == true ? "Canceled" : landed ? "Arrived" : fa.actual_off != nil ? "EnRoute" : nil,
            departure: date(fa.actual_off ?? fa.actual_out ?? fa.estimated_off ?? fa.estimated_out ?? fa.scheduled_off ?? fa.scheduled_out),
            departed: fa.actual_off != nil || fa.actual_out != nil,
            arrival: date(fa.actual_in ?? fa.actual_on ?? fa.estimated_in ?? fa.estimated_on ?? fa.scheduled_in ?? fa.scheduled_on),
            scheduledArrival: date(fa.scheduled_in ?? fa.scheduled_on),
            landed: landed,
            updated: Date(),
            toCode: fa.destination?.code_iata ?? fa.destination?.code)
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

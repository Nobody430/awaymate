import Foundation
import CoreLocation

// MARK: - Aircraft details (AeroDataBox, on demand)

struct AircraftDetails: Codable {
    let reg: String?
    let typeName: String?
    let model: String?
    let modelCode: String?
    let numSeats: Int?
    let engineType: String?
    let numEngines: Int?
    let firstFlightDate: String?
    let deliveryDate: String?
    let rolloutDate: String?
    let ageYears: Double?
    let airlineName: String?
    let productionLine: String?
    let serial: String?

    var ageText: String? {
        if let a = ageYears { return String(localized: "\(a.formatted(.number.precision(.fractionLength(1)))) Jahre") }
        guard let s = firstFlightDate ?? deliveryDate ?? rolloutDate,
              let d = Fmt.parse(s) ?? Fmt.apiDate.date(from: String(s.prefix(10))) else { return nil }
        return String(localized: "\((Date().timeIntervalSince(d) / (365.25 * 86400)).formatted(.number.precision(.fractionLength(1)))) Jahre")
    }
}

enum AircraftService {
    private static let cacheKey = "aircraftCache"

    static func cached(_ reg: String) -> AircraftDetails? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let dict = try? JSONDecoder().decode([String: AircraftDetails].self, from: data) else { return nil }
        return dict[reg.uppercased()]
    }

    static func load(_ reg: String) async throws -> AircraftDetails {
        if let c = cached(reg) { return c }
        let key = Settings.apiKey
        guard !key.isEmpty else { throw APIError.noKey }
        let r = reg.uppercased().addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reg
        var request = URLRequest(url: URL(string: "https://\(AeroDataBox.host)/aircrafts/reg/\(r)")!)
        request.setValue(key, forHTTPHeaderField: "X-RapidAPI-Key")
        request.setValue(AeroDataBox.host, forHTTPHeaderField: "X-RapidAPI-Host")
        let (data, response) = try await URLSession.shared.data(for: request)
        Usage.increment()
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 || code == 204 { throw APIError.notFound }
        if code == 429 { throw APIError.quota }
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        let details = try JSONDecoder().decode(AircraftDetails.self, from: data)
        var dict = (UserDefaults.standard.data(forKey: cacheKey).flatMap { try? JSONDecoder().decode([String: AircraftDetails].self, from: $0) }) ?? [:]
        dict[reg.uppercased()] = details
        UserDefaults.standard.set(try? JSONEncoder().encode(dict), forKey: cacheKey)
        return details
    }
}

// MARK: - Seat analysis

enum SeatInfo {
    enum Kind: String { case window = "Fenster", middle = "Mitte", aisle = "Gang" }

    /// Typical cabin layout by aircraft model (economy).
    static func layout(for model: String?) -> [String] {
        let m = (model ?? "").lowercased()
        if m.contains("a220") || m.contains("bcs") { return ["AC", "DEF"] }
        if m.contains("embraer") || m.contains("e19") || m.contains("e17") || m.contains("crj") || m.contains("erj") { return ["AC", "DF"] }
        if m.contains("dash") || m.contains("atr") || m.contains("q400") { return ["AC", "DF"] }
        if m.contains("380") || m.contains("777") || m.contains("747") { return ["ABC", "DEFG", "HJK"] }
        if m.contains("787") || m.contains("a350") || m.contains("350") { return ["ABC", "DEF", "HJK"] }
        if m.contains("330") || m.contains("340") || m.contains("767") { return ["AC", "DEFG", "HK"] }
        return ["ABC", "DEF"]
    }

    static func parse(_ seat: String) -> (row: Int, letter: Character)? {
        let s = seat.uppercased().trimmingCharacters(in: .whitespaces)
        guard let letter = s.last, letter.isLetter, let row = Int(s.dropLast()) else { return nil }
        return (row, letter)
    }

    static func describe(seat: String, model: String?) -> String? {
        guard let parsed = parse(seat) else { return nil }
        let (row, letter) = parsed
        let blocks = layout(for: model)
        guard let blockIndex = blocks.firstIndex(where: { $0.contains(letter) }) else {
            return String(localized: "Reihe \(row), Platz \(String(letter))")
        }
        let block = Array(blocks[blockIndex])
        let pos = block.firstIndex(of: letter)!
        let middleBlock = blockIndex != 0 && blockIndex != blocks.count - 1
        let side = blockIndex == 0 ? String(localized: "links") : String(localized: "rechts")
        let kind: Kind
        if (blockIndex == 0 && pos == 0) || (blockIndex == blocks.count - 1 && pos == block.count - 1) { kind = .window }
        else if pos == 0 || pos == block.count - 1 { kind = .aisle }
        else { kind = .middle }
        let kindLabel: String
        switch kind {
        case .window: kindLabel = String(localized: "Fenster")
        case .middle: kindLabel = String(localized: "Mitte")
        case .aisle: kindLabel = String(localized: "Gang")
        }
        let place = middleBlock ? String(localized: "mittlerer Block") : String(localized: "Seite \(side)")
        return String(localized: "Reihe \(row) · \(kindLabel), \(place) (typische Bestuhlung)")
    }

    static func side(of seat: String, model: String?) -> String? {
        guard let letter = parse(seat)?.letter else { return nil }
        let blocks = layout(for: model)
        if blocks.first?.contains(letter) == true { return "links" }
        if blocks.last?.contains(letter) == true { return "rechts" }
        return nil
    }
}

// MARK: - Sun side

enum SunSide {
    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Solar azimuth (0° = north, clockwise) and elevation in degrees (NOAA approximation).
    static func position(at date: Date, lat: Double, lon: Double) -> (azimuth: Double, elevation: Double) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let doy = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let g = 2 * .pi / 365 * (doy - 1 + (hour - 12) / 24)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g) + 0.000907 * sin(2 * g)
            - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let trueSolarMinutes = hour * 60 + eqTime + 4 * lon
        let ha = rad(trueSolarMinutes / 4 - 180)
        let phi = rad(lat)
        let elevation = deg(asin(sin(phi) * sin(decl) + cos(phi) * cos(decl) * cos(ha)))
        let azimuth = (deg(atan2(sin(ha), cos(ha) * sin(phi) - tan(decl) * cos(phi))) + 180).truncatingRemainder(dividingBy: 360)
        return (azimuth, elevation)
    }

    struct Result {
        let leftMinutes: Int
        let rightMinutes: Int
        let darkMinutes: Int
        var summary: String {
            let total = max(1, leftMinutes + rightMinutes + darkMinutes)
            if darkMinutes * 10 >= total * 9 { return String(localized: "Fast nur im Dunkeln – Seite egal 🌙") }
            if leftMinutes > rightMinutes * 2 { return String(localized: "Sonne meist LINKS ☀️ – für Aussicht ohne Blendung rechts sitzen") }
            if rightMinutes > leftMinutes * 2 { return String(localized: "Sonne meist RECHTS ☀️ – für Aussicht ohne Blendung links sitzen") }
            return String(localized: "Sonne wechselt die Seite – beide Seiten ähnlich")
        }
    }

    static func analyse(_ f: Flight) -> Result? {
        guard let a = f.departure.coordinate, let b = f.arrival.coordinate,
              let dep = f.departure.best, let arr = f.arrival.best, arr > dep else { return nil }
        let steps = 24
        let stepMinutes = arr.timeIntervalSince(dep) / 60 / Double(steps)
        var left = 0.0, right = 0.0, dark = 0.0
        for i in 0..<steps {
            let frac = (Double(i) + 0.5) / Double(steps)
            let p = Geo.interpolate(a, b, frac)
            let next = Geo.interpolate(a, b, min(1, frac + 0.02))
            let heading = Geo.bearing(p, next)
            let sun = position(at: dep.addingTimeInterval(arr.timeIntervalSince(dep) * frac), lat: p.latitude, lon: p.longitude)
            if sun.elevation < -2 { dark += stepMinutes; continue }
            let relative = (sun.azimuth - heading + 360).truncatingRemainder(dividingBy: 360)
            if relative < 180 { right += stepMinutes } else { left += stepMinutes }
        }
        return Result(leftMinutes: Int(left), rightMinutes: Int(right), darkMinutes: Int(dark))
    }
}

// MARK: - Live links for family

@MainActor
enum FamilyShare {
    static func trackingLinks(_ f: Flight) -> [(String, URL)] {
        var out: [(String, URL)] = []
        let number = f.number.replacingOccurrences(of: " ", with: "").lowercased()
        if let u = URL(string: "https://www.flightradar24.com/data/flights/\(number)") { out.append(("Flightradar24", u)) }
        let ident = (f.callSign?.replacingOccurrences(of: " ", with: "") ?? number).uppercased()
        if let u = URL(string: "https://www.flightaware.com/live/flight/\(ident)") { out.append(("FlightAware", u)) }
        return out
    }

    static func statusMessage(_ f: Flight) -> String {
        var s: String
        switch f.normalizedStatus {
        case .arrived: s = String(localized: "Bin gut in \(f.arrival.displayCity) gelandet ✈️😊")
        case .canceled: s = String(localized: "Mein Flug \(f.number) wurde leider annulliert – melde mich gleich.")
        default:
            if f.isInAir {
                s = String(localized: "Bin in der Luft ✈️ \(f.number) nach \(f.arrival.displayCity), Landung ca. \(Fmt.time(f.arrival.best, f.arrival.tz)) Ortszeit.")
            } else {
                s = String(localized: "Mein Flug \(f.number) nach \(f.arrival.displayCity) startet um \(Fmt.time(f.departure.best, f.departure.tz))")
                if let d = Fmt.delay(f.departure.delayMinutes) { s += String(localized: " (\(d) verspätet)") }
                s += String(localized: ", Landung ca. \(Fmt.time(f.arrival.best, f.arrival.tz)) Ortszeit.")
            }
        }
        // own status link if there is one; the public tracking sites only for people without their own server
        let own = PushClient.isConfigured ? f.shareToken.flatMap { PushClient.endpoint("/s/" + $0) } : trackingLinks(f).first?.1
        if let link = own, !f.isPast { s += "\n" + String(localized: "Live verfolgen: \(link.absoluteString)") }
        return s
    }
}

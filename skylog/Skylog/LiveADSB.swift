import Foundation
import CoreLocation

/// Free, unlimited live data from community ADS-B networks (adsb.lol, airplanes.live – readsb v2 format).
/// Gives position, altitude, speed and on-ground state by ATC callsign. No gates/terminals.
enum LiveADSB {
    /// IATA → ICAO airline codes (ATC callsign prefix).
    static let icaoAirline: [String: String] = [
        "LX": "SWR", "WK": "EDW", "2L": "OAW", "LH": "DLH", "OS": "AUA", "SN": "BEL", "EW": "EWG", "4U": "GWI",
        "DE": "CFG", "X3": "TUI", "U2": "EZY", "DS": "EZS", "EC": "EJU", "FR": "RYR", "RK": "RUK", "W6": "WZZ",
        "W4": "WMT", "VY": "VLG", "IB": "IBE", "I2": "IBS", "UX": "AEA", "AF": "AFR", "KL": "KLM", "HV": "TRA",
        "TO": "TVF", "BA": "BAW", "VS": "VIR", "EI": "EIN", "AZ": "ITY", "TP": "TAP", "SK": "SAS", "AY": "FIN",
        "DY": "NOZ", "D8": "NSZ", "LO": "LOT", "A3": "AEE", "OA": "OAL", "TK": "THY", "PC": "PGT", "EK": "UAE",
        "QR": "QTR", "EY": "ETD", "SV": "SVA", "MS": "MSR", "LY": "ELY", "ET": "ETH", "UA": "UAL", "AA": "AAL",
        "DL": "DAL", "AC": "ACA", "B6": "JBU", "AS": "ASA", "WN": "SWA", "AM": "AMX", "LA": "LAN", "JJ": "TAM",
        "AV": "AVA", "CM": "CMP", "G3": "GLO", "AD": "AZU", "AR": "ARG", "JA": "JAT", "H2": "SKU", "FO": "FBZ",
        "CX": "CPA", "SQ": "SIA", "TR": "TGW", "MH": "MAS", "AK": "AXM", "FD": "AIQ", "TG": "THA", "VN": "HVN",
        "GA": "GIA", "PR": "PAL", "CI": "CAL", "BR": "EVA", "JL": "JAL", "NH": "ANA", "KE": "KAL", "OZ": "AAR",
        "CA": "CCA", "MU": "CES", "CZ": "CSN", "QF": "QFA", "VA": "VOZ", "NZ": "ANZ", "AI": "AIC", "6E": "IGO",
        "WY": "OMA", "GF": "GFA", "KU": "KAC", "FZ": "FDB", "RJ": "RJA", "KQ": "KQA", "SA": "SAA", "AT": "RAM",
        "PG": "BKP", "SL": "TLM", "UL": "ALK", "UK": "VTI", "JQ": "JST", "LS": "EXS", "BT": "BTI", "FB": "LZB",
        "RO": "ROT", "HU": "CHH", "ZF": "AZV",
    ]

    /// The real ATC callsign if the data source gave us one (many airlines use alphanumeric ones), else derived.
    static func callsign(for f: Flight) -> String? {
        if let cs = f.callSign?.replacingOccurrences(of: " ", with: "").uppercased(), cs.count >= 4, cs.count <= 8,
           cs.prefix(3).allSatisfy(\.isLetter), cs.dropFirst(3).allSatisfy({ $0.isLetter || $0.isNumber }) { return cs }
        return callsign(for: f.number)
    }

    static func callsign(for flightNumber: String) -> String? {
        let n = flightNumber.replacingOccurrences(of: " ", with: "").uppercased()
        guard n.count >= 3 else { return nil }
        let iata = String(n.prefix(2))
        guard let icao = icaoAirline[iata] else { return nil }
        let digits = n.dropFirst(2).drop { $0 == "0" }
        guard !digits.isEmpty else { return nil }
        return icao + digits
    }

    struct Fix {
        let position: LivePosition
        let onGround: Bool
    }

    private static let hosts = ["https://api.adsb.lol/v2/", "https://api.airplanes.live/v2/"]

    static func lookup(callsign: String) async -> Fix? {
        await lookup(path: "callsign/" + callsign) {
            (($0["flight"] as? String) ?? "").trimmingCharacters(in: .whitespaces).uppercased() == callsign
        }
    }

    /// By the aircraft's transponder code (24-bit address) – the most reliable key once it is known.
    static func lookup(hex: String) async -> Fix? {
        let code = hex.trimmingCharacters(in: .whitespaces).lowercased()
        guard code.count == 6, code.allSatisfy(\.isHexDigit) else { return nil }
        return await lookup(path: "hex/" + code) { (($0["hex"] as? String) ?? "").lowercased() == code }
    }

    /// By aircraft registration – for flights whose callsign on the transponder differs from the published one.
    static func lookup(registration: String) async -> Fix? {
        let reg = registration.replacingOccurrences(of: " ", with: "").uppercased()
        guard reg.count >= 4 else { return nil }
        let isMatch: ([String: Any]) -> Bool = { (($0["r"] as? String) ?? "").replacingOccurrences(of: " ", with: "").uppercased() == reg }
        // the networks don't agree on the path name
        if let fix = await lookup(path: "reg/" + reg, matches: isMatch) { return fix }
        return await lookup(path: "registration/" + reg, matches: isMatch)
    }

    private static func lookup(path: String, matches isMatch: ([String: Any]) -> Bool) async -> Fix? {
        for base in hosts {
            guard let url = URL(string: base + path) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("Skylog/1.0 (personal flight tracker)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["ac"] as? [[String: Any]] else { continue }
            // pick the freshest aircraft that matches exactly
            let matches = list.filter(isMatch)
            guard let ac = matches.min(by: { (($0["seen"] as? NSNumber)?.doubleValue ?? 99) < (($1["seen"] as? NSNumber)?.doubleValue ?? 99) }),
                  let lat = (ac["lat"] as? NSNumber)?.doubleValue,
                  let lon = (ac["lon"] as? NSNumber)?.doubleValue else { continue }
            let onGround = (ac["alt_baro"] as? String) == "ground"
            let altFt = (ac["alt_baro"] as? NSNumber)?.doubleValue ?? (ac["alt_geom"] as? NSNumber)?.doubleValue
            let seen = (ac["seen_pos"] as? NSNumber)?.doubleValue ?? (ac["seen"] as? NSNumber)?.doubleValue ?? 0
            let pos = LivePosition(
                lat: lat, lon: lon,
                altitudeM: onGround ? 0 : altFt.map { $0 * 0.3048 },
                speedKmh: (ac["gs"] as? NSNumber).map { $0.doubleValue * 1.852 },
                heading: (ac["track"] as? NSNumber)?.doubleValue ?? (ac["true_heading"] as? NSNumber)?.doubleValue,
                verticalRate: (ac["baro_rate"] as? NSNumber).map { $0.doubleValue * 0.00508 },
                onGround: onGround,
                timestamp: Date().addingTimeInterval(-seen),
                source: base.contains("adsb.lol") ? "adsb.lol" : "airplanes.live")
            return Fix(position: pos, onGround: onGround)
        }
        return nil
    }

    /// Applies an ADS-B fix to a flight: departure/landing detection and a live ETA. Returns notification texts.
    static func apply(_ fix: Fix?, to f: inout Flight, now: Date = Date()) -> [(title: String, body: String, takeoff: Bool)] {
        var notes: [(title: String, body: String, takeoff: Bool)] = []
        let status = f.normalizedStatus
        guard let fix else {
            // Was airborne and is no longer seen well after the expected arrival → landed
            if status.isAirborne, let arr = f.arrival.best, now > arr.addingTimeInterval(20 * 60),
               let last = f.lastPosition, now.timeIntervalSince(last.timestamp) > 15 * 60 {
                f.status = "Arrived"
                if f.arrival.runway == nil { f.arrival.runway = last.timestamp }
                notes.append((String(localized: "\(f.number) ist gelandet"), String(localized: "Willkommen in \(f.arrival.displayCity)!"), false))
            }
            return notes
        }
        // another aircraft with the same callsign, or a bogus fix: ignore
        guard f.isPlausible(fix.position) else { return notes }
        f.lastPosition = fix.position
        let p = fix.position.coordinate
        let distToDest = f.arrival.coordinate.map { Geo.distanceKm(p, $0) } ?? .infinity
        let distToOrigin = f.departure.coordinate.map { Geo.distanceKm(p, $0) } ?? .infinity

        // Takeoff: only around/after our departure time and on our route (not yesterday's rotation or an earlier leg)
        let route = f.computedDistanceKm ?? 2500
        let timeOK = f.departure.best.map { now > $0.addingTimeInterval(-15 * 60) } ?? true
        if !fix.onGround && !status.isAirborne && !status.isFinal && timeOK && distToOrigin < max(300, route * 1.1) {
            f.status = "EnRoute"
            if f.departure.runway == nil { f.departure.runway = now }
            notes.append((String(localized: "\(f.number) ist gestartet"), String(localized: "Unterwegs nach \(f.arrival.displayCity)."), true))
        } else if fix.onGround && status.isAirborne && distToDest < 15 {
            f.status = "Arrived"
            if f.arrival.runway == nil { f.arrival.runway = now }
            notes.append((String(localized: "\(f.number) ist gelandet"), String(localized: "Willkommen in \(f.arrival.displayCity)!") + (f.arrival.baggageBelt.map { String(localized: " Gepäckband \($0).") } ?? ""), false))
        }

        // Live ETA from remaining distance and ground speed (+10 min for approach and taxi)
        if !fix.onGround, let kmh = fix.position.speedKmh, kmh > 200, distToDest.isFinite {
            f.arrival.predicted = now.addingTimeInterval(distToDest / kmh * 3600 + 10 * 60)
        }
        return notes
    }
}

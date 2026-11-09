import Foundation

/// Extracts the mailbox owner's real flights from mails with Claude (much more accurate than pattern matching).
enum MailAI {
    struct Extracted: Codable {
        let flightNumber: String
        let date: String
        let from: String
        let to: String
        let departureTime: String
        let arrivalTime: String
        let arrivalDayOffset: Int
        let bookingReference: String
        let status: String
        let mailIndex: Int
        let passengers: [String]
        let forwarded: Bool
        let mailType: String
    }
    struct ExtractedBooking: Codable {
        let kind: String
        let name: String
        let city: String
        let address: String
        let startDate: String
        let endDate: String
        let bookingReference: String
        let provider: String
        let status: String
        let guests: [String]
        let forwarded: Bool
        let mailIndex: Int
    }
    private struct Response: Codable { let flights: [Extracted]; let bookings: [ExtractedBooking] }

    static var passengerName: String {
        (UserDefaults.standard.string(forKey: "passengerName") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static var fullSystem: String {
        guard !passengerName.isEmpty else { return system }
        return system + """

        WICHTIG: Der Postfach-Inhaber heisst „\(passengerName)“. Liefere nur Flüge, bei denen diese Person als Passagier aufgeführt ist         (auch Schreibweisen wie NACHNAME/VORNAME MR, nur Nachname + Initiale, oder ohne Umlaute).         Buchungen ausschliesslich für andere Personen ignorieren. Wenn eine Bestätigung keine Passagiernamen enthält,         aber eindeutig an den Inhaber gerichtet ist (z.B. „Hallo \(passengerName.split(separator: " ").first ?? "")“), darf sie übernommen werden.
        """
    }

    static let system = """
    Du extrahierst Flugbuchungen aus E-Mails. Gib NUR Flüge zurück, auf denen der Postfach-Inhaber (oder seine Mitreisenden in derselben Buchung) tatsächlich gebucht ist: \
    Buchungsbestätigungen, E-Tickets, Reisepläne, Check-in-Bestätigungen, Bordkarten, Umbuchungs- oder Stornierungsmitteilungen.
    Ignoriere komplett: Werbung, Newsletter, Preisalarme, Angebote, Flugsuche-Ergebnisse, Bonusmeilen-Kontoauszüge, Umfragen, Rechnungen ohne Flugdaten, \
    Hotel- und Mietwagenbuchungen, Flugnummern in Signaturen oder Fussnoten.
    Für jeden Flugabschnitt (jede Teilstrecke einzeln, auch Hin- und Rückflug):
    - flightNumber: Airline-Code + Nummer ohne Leerzeichen, z.B. LX1612 (IATA-Code bevorzugen)
    - date: lokales Abflugdatum YYYY-MM-DD (Jahr aus dem Mail-Datum ableiten, falls im Text fehlend)
    - from/to: IATA-Flughafencodes (3 Buchstaben); falls nur Stadtnamen, den üblichen Hauptflughafen
    - departureTime/arrivalTime: lokale Zeit HH:mm, leer wenn unbekannt; arrivalDayOffset: 0, 1 oder 2
    - bookingReference: Buchungscode/PNR, sonst leer
    - status: "booked", "changed" (neue/geänderte Zeiten durch Umbuchung) oder "cancelled"
    - mailIndex: Nummer der Mail, aus der die Info stammt
    - passengers: alle Passagiernamen dieses Flugs genau wie in der Mail (leer, wenn keine genannt)
    - mailType: Art der Mail: "confirmation" (Buchungsbestätigung/E-Ticket mit vollständigem Reiseplan), "change" (Umbuchung/Flugplanänderung mit neuem Reiseplan), \
      "cancellation" (Storno), "checkin" (Check-in-Bestätigung), "boardingpass" (Bordkarte), "reminder" (Reiseerinnerung), "other"
    - Bei "confirmation" und "change" ALLE Teilstrecken des aktuellen Reiseplans auflisten, auch Rückflüge und Anschlussflüge.
    - Codeshares: nur die durchführende (operating) Flugnummer angeben, nicht zusätzlich die Marketing-Nummer.
    - forwarded: true, wenn die Mail weitergeleitet wurde (z.B. „WG:“, „Fwd:“, „Weitergeleitete Nachricht“) oder an jemand anderen gerichtet ist
    Zusätzlich unter "bookings" weitere Reisebuchungen des Inhabers: Unterkünfte (Hotel, Booking.com, Airbnb → kind "hotel"), \
    Mietwagen ("car"), Zug ("train"), Fernbus ("bus"), Fähre ("ferry"), gebuchte Touren/Tickets ("activity"). \
    startDate/endDate im Format YYYY-MM-DD (Hotel: Check-in/Check-out; Mietwagen: Abholung/Rückgabe; Zug: Reisedatum für beide). \
    name = Hotel-/Firmenname bzw. Strecke („Zürich → Mailand“), city = Ort, provider = Buchungsplattform (z.B. Booking.com), \
    guests = Namen der Gäste/Mieter/Reisenden, status wie bei Flügen. Keine Werbung oder Angebote.
    Erfinde nichts. Wenn eine Mail keine echte Buchung enthält, liefere für sie nichts.
    """

    static let schema: [String: Any] = {
        let flight: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["flightNumber", "date", "from", "to", "departureTime", "arrivalTime", "arrivalDayOffset", "bookingReference", "status", "mailIndex", "passengers", "forwarded", "mailType"],
            "properties": [
                "flightNumber": ["type": "string"], "date": ["type": "string"], "from": ["type": "string"], "to": ["type": "string"],
                "departureTime": ["type": "string"], "arrivalTime": ["type": "string"], "arrivalDayOffset": ["type": "integer"],
                "bookingReference": ["type": "string"], "status": ["type": "string", "enum": ["booked", "changed", "cancelled"]],
                "mailIndex": ["type": "integer"],
                "passengers": ["type": "array", "items": ["type": "string"]],
                "forwarded": ["type": "boolean"],
                "mailType": ["type": "string", "enum": ["confirmation", "change", "cancellation", "checkin", "boardingpass", "reminder", "other"]],
            ],
        ]
        let booking: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["kind", "name", "city", "address", "startDate", "endDate", "bookingReference", "provider", "status", "guests", "forwarded", "mailIndex"],
            "properties": [
                "kind": ["type": "string", "enum": ["hotel", "car", "train", "bus", "ferry", "activity", "other"]],
                "name": ["type": "string"], "city": ["type": "string"], "address": ["type": "string"],
                "startDate": ["type": "string"], "endDate": ["type": "string"],
                "bookingReference": ["type": "string"], "provider": ["type": "string"],
                "status": ["type": "string", "enum": ["booked", "changed", "cancelled"]],
                "guests": ["type": "array", "items": ["type": "string"]],
                "forwarded": ["type": "boolean"], "mailIndex": ["type": "integer"],
            ],
        ]
        return ["type": "object", "additionalProperties": false, "required": ["flights", "bookings"],
                "properties": ["flights": ["type": "array", "items": flight], "bookings": ["type": "array", "items": booking]]]
    }()

    /// True if the flight is the owner's: name among the passengers, or (no names) a direct, non-forwarded mail.
    static func belongsToOwner(_ e: Extracted) -> Bool {
        let parts = passengerName.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !parts.isEmpty else { return !e.forwarded }
        if e.passengers.isEmpty { return !e.forwarded }
        return e.passengers.contains { p in
            let n = p.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            // surname (last part) must match; first name or initial optional
            guard let surname = parts.last, n.contains(surname) else { return false }
            return true
        }
    }

    private static func flightKey(_ e: Extracted) -> String {
        e.flightNumber.uppercased().replacingOccurrences(of: " ", with: "") + "|" + e.date
    }

    /// Per booking reference, only the legs of the newest full itinerary count (older legs were re-booked).
    /// Boarding passes / check-ins prove a flight and are always kept; cancellations remove legs.
    static func reconcileBookings(_ items: [(Extracted, OutlookMail.MailItem)]) -> [(Extracted, OutlookMail.MailItem)] {
        let groups = Dictionary(grouping: items) { $0.0.bookingReference.uppercased().trimmingCharacters(in: .whitespaces) }
        var result: [(Extracted, OutlookMail.MailItem)] = []
        for (ref, group) in groups {
            guard !ref.isEmpty else { result += group; continue }
            let full = group.filter { ["confirmation", "change"].contains($0.0.mailType) }
            guard let newestFull = full.max(by: { $0.1.received < $1.1.received })?.1 else { result += group; continue }
            let current = full.filter { $0.1.id == newestFull.id }
            let currentKeys = Set(current.map { flightKey($0.0) })
            result += current
            for item in group where !currentKeys.contains(flightKey(item.0)) {
                switch item.0.mailType {
                case "boardingpass", "checkin":
                    result.append(item)                        // proof of travel
                case "reminder", "other":
                    if item.1.received > newestFull.received { result.append(item) }
                case "cancellation":
                    result.append(item)                        // handled as cancelled below
                default:
                    break                                      // legs of an outdated itinerary
                }
            }
        }
        return result
    }

    static let maxCharsPerMail = 9000

    /// Text sent to the AI: the start of the mail plus the passages around every flight number (long mails are not just cut off).
    static func relevantText(_ m: OutlookMail.MailItem) -> String {
        let text = m.text
        guard text.count > maxCharsPerMail else { return text }
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: "\\b[A-Z0-9]{2}\\s?\\d{1,4}\\b")
        var ranges: [NSRange] = [NSRange(location: 0, length: min(2000, ns.length))]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let start = max(0, match.range.location - 350)
            let end = min(ns.length, match.range.location + 550)
            if let last = ranges.last, start <= last.location + last.length {
                ranges[ranges.count - 1] = NSRange(location: last.location, length: max(last.length, end - last.location))
            } else {
                ranges.append(NSRange(location: start, length: end - start))
            }
        }
        var out = ""
        for r in ranges {
            out += ns.substring(with: r) + "\n[…]\n"
            if out.count > maxCharsPerMail { break }
        }
        return String(out.prefix(maxCharsPerMail))
    }
    static let mailsPerRequest = 6

    /// Mails worth sending to the AI (cheap pre-filter).
    static func relevant(_ mails: [OutlookMail.MailItem]) -> [OutlookMail.MailItem] {
        let keywords = ["boarding", "bordkarte", "e-ticket", "eticket", "itinerary", "reiseplan", "buchung", "booking", "flug", "flight",
                        "vol ", "vuelo", "check-in", "pnr", "reservation", "reservierung", "ticket"]
        let nameParts = passengerName.lowercased().split(separator: " ").map(String.init).filter { $0.count >= 3 }
        return mails.filter { m in
            let t = (m.subject + " " + m.text.prefix(6000)).lowercased()
            guard keywords.contains(where: { t.contains($0) }) else { return false }
            // With a name set, the mail must mention at least part of it
            if !nameParts.isEmpty, !nameParts.contains(where: { t.contains($0) }) { return false }
            let stay = ["hotel", "booking.com", "airbnb", "unterkunft", "übernachtung", "check-in:", "anreise", "mietwagen", "car rental",
                        "sixt", "hertz", "europcar", "avis", "enterprise", "zugticket", "sbb", "trainline", "deutsche bahn", "flixbus"]
            if stay.contains(where: { t.contains($0) }) { return true }
            return t.range(of: "\\b[a-z0-9]{2}\\s?-?\\d{1,4}\\b", options: .regularExpression) != nil
        }
    }

    /// Rough cost in CHF for the selected model.
    static func estimatedCost(_ mails: [OutlookMail.MailItem]) -> Double {
        let (inPrice, outPrice): (Double, Double) = switch AIClient.provider {
        case .claudeBest: (4, 20)
        case .claudeFast: (0.10, 0.50)
        case .openai: (0.5, 2)
        }
        let chars = mails.reduce(0) { $0 + min($1.text.count, maxCharsPerMail) + $1.subject.count + 80 }
        let requests = Double((mails.count + mailsPerRequest - 1) / mailsPerRequest)
        let input = Double(chars) / 3.5 + requests * 900
        let output = requests * 1200
        return (input * inPrice + output * outPrice) / 1_000_000 * 0.9
    }

    private static func request(_ batch: [(Int, OutlookMail.MailItem)]) async throws -> ([(Extracted, OutlookMail.MailItem)], [(ExtractedBooking, OutlookMail.MailItem)]) {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let body = batch.map { index, m in
            "### Mail \(index)\nVon: \(m.from)\nDatum: \(f.string(from: m.received))\nBetreff: \(m.subject)\n\n\(relevantText(m))"
        }.joined(separator: "\n\n")
        let text = try await AIClient.send(system: fullSystem, user: body, schema: schema, effort: "low", maxTokens: 8000)
        let response = try JSONDecoder().decode(Response.self, from: Data(text.utf8))
        let byIndex = Dictionary(uniqueKeysWithValues: batch.map { ($0.0, $0.1) })
        return (response.flights.compactMap { e in byIndex[e.mailIndex].map { (e, $0) } },
                response.bookings.compactMap { b in byIndex[b.mailIndex].map { (b, $0) } })
    }

    struct ExtractResult {
        var flights: [FlightCandidate]
        var bookings: [TravelBooking]
    }

    static func extract(_ mails: [OutlookMail.MailItem], progress: @escaping @MainActor (String) -> Void) async throws -> [FlightCandidate] {
        try await extractAll(mails, progress: progress).flights
    }

    /// Runs the extraction over all mails (3 requests in parallel) and reconciles changes/cancellations.
    static func extractAll(_ mails: [OutlookMail.MailItem], progress: @escaping @MainActor (String) -> Void) async throws -> ExtractResult {
        let indexed = Array(mails.enumerated()).map { ($0.offset + 1, $0.element) }
        let batches = stride(from: 0, to: indexed.count, by: mailsPerRequest).map { Array(indexed[$0..<min($0 + mailsPerRequest, indexed.count)]) }
        var found: [(Extracted, OutlookMail.MailItem)] = []
        var foundBookings: [(ExtractedBooking, OutlookMail.MailItem)] = []
        var done = 0
        var lastError: Error?

        for chunk in stride(from: 0, to: batches.count, by: 3).map({ Array(batches[$0..<min($0 + 3, batches.count)]) }) {
            await withTaskGroup(of: Result<([(Extracted, OutlookMail.MailItem)], [(ExtractedBooking, OutlookMail.MailItem)]), Error>.self) { group in
                for b in chunk { group.addTask { do { return .success(try await request(b)) } catch { return .failure(error) } } }
                for await r in group {
                    switch r {
                    case .success(let pair):
                        found += pair.0
                        foundBookings += pair.1
                    case .failure(let e): lastError = e
                    }
                    done += 1
                    await progress("KI liest Mails … \(min(done * mailsPerRequest, mails.count))/\(mails.count) · \(found.count) Flugabschnitte")
                }
            }
        }
        if found.isEmpty && foundBookings.isEmpty, let lastError { throw lastError }

        found = reconcileBookings(found)

        // Latest mail per flight wins (re-bookings / cancellations)
        var latest: [String: (Extracted, OutlookMail.MailItem)] = [:]
        for item in found {
            let key = item.0.flightNumber.uppercased().replacingOccurrences(of: " ", with: "") + "|" + item.0.date
            if let existing = latest[key], existing.1.received > item.1.received { continue }
            latest[key] = item
        }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        let flights: [FlightCandidate] = latest.values.compactMap { item -> FlightCandidate? in
            let (e, mail) = item
            guard Self.belongsToOwner(e), let d = day.date(from: e.date),
                  e.flightNumber.count >= 3, e.from.count == 3, e.to.count == 3 else { return nil }
            let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: d) ?? d
            var c = FlightCandidate(number: e.flightNumber.uppercased().replacingOccurrences(of: " ", with: ""),
                                    date: noon, source: mail.subject.isEmpty ? mail.from : mail.subject,
                                    airports: [e.from.uppercased(), e.to.uppercased()])
            c.departureTime = e.departureTime.isEmpty ? nil : e.departureTime
            c.arrivalTime = e.arrivalTime.isEmpty ? nil : e.arrivalTime
            c.arrivalDayOffset = e.arrivalDayOffset
            c.bookingReference = e.bookingReference.isEmpty ? nil : e.bookingReference
            c.aiVerified = true
            c.cancelled = e.status == "cancelled" || e.mailType == "cancellation"
            return c
        }
        .sorted { $0.date > $1.date }

        return ExtractResult(flights: flights, bookings: convertBookings(foundBookings))
    }

    /// Newest mail per booking wins; only bookings with the owner as guest (if a name is set).
    static func convertBookings(_ items: [(ExtractedBooking, OutlookMail.MailItem)]) -> [TravelBooking] {
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")
        let surname = passengerName.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(separator: " ").last.map(String.init)
        var latest: [String: (ExtractedBooking, OutlookMail.MailItem)] = [:]
        for item in items {
            let b = item.0
            let k = b.kind + "|" + (b.bookingReference.isEmpty ? b.name.lowercased() + b.startDate : b.bookingReference.uppercased())
            if let existing = latest[k], existing.1.received > item.1.received { continue }
            latest[k] = item
        }
        return latest.values.compactMap { item -> TravelBooking? in
            let (b, mail) = item
            if let surname, !b.guests.isEmpty,
               !b.guests.contains(where: { $0.lowercased().folding(options: .diacriticInsensitive, locale: nil).contains(surname) }) { return nil }
            if b.guests.isEmpty && b.forwarded { return nil }
            guard let start = day.date(from: b.startDate) else { return nil }
            let end = day.date(from: b.endDate) ?? start
            return TravelBooking(kind: TravelBooking.Kind(rawValue: b.kind) ?? .other, name: b.name, city: b.city, address: b.address,
                                 start: start, end: max(end, start), bookingReference: b.bookingReference,
                                 provider: b.provider.isEmpty ? mail.from : b.provider, cancelled: b.status == "cancelled")
        }
        .sorted { $0.start > $1.start }
    }
}

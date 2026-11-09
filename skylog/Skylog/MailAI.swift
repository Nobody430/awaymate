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
    }
    private struct Response: Codable { let flights: [Extracted] }

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
    - forwarded: true, wenn die Mail weitergeleitet wurde (z.B. „WG:“, „Fwd:“, „Weitergeleitete Nachricht“) oder an jemand anderen gerichtet ist
    Erfinde nichts. Wenn eine Mail keine echte Buchung enthält, liefere für sie nichts.
    """

    static let schema: [String: Any] = {
        let flight: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["flightNumber", "date", "from", "to", "departureTime", "arrivalTime", "arrivalDayOffset", "bookingReference", "status", "mailIndex", "passengers", "forwarded"],
            "properties": [
                "flightNumber": ["type": "string"], "date": ["type": "string"], "from": ["type": "string"], "to": ["type": "string"],
                "departureTime": ["type": "string"], "arrivalTime": ["type": "string"], "arrivalDayOffset": ["type": "integer"],
                "bookingReference": ["type": "string"], "status": ["type": "string", "enum": ["booked", "changed", "cancelled"]],
                "mailIndex": ["type": "integer"],
                "passengers": ["type": "array", "items": ["type": "string"]],
                "forwarded": ["type": "boolean"],
            ],
        ]
        return ["type": "object", "additionalProperties": false, "required": ["flights"],
                "properties": ["flights": ["type": "array", "items": flight]]]
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

    static let maxCharsPerMail = 3500
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

    private static func request(_ batch: [(Int, OutlookMail.MailItem)]) async throws -> [(Extracted, OutlookMail.MailItem)] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let body = batch.map { index, m in
            "### Mail \(index)\nVon: \(m.from)\nDatum: \(f.string(from: m.received))\nBetreff: \(m.subject)\n\n\(m.text.prefix(maxCharsPerMail))"
        }.joined(separator: "\n\n")
        let text = try await AIClient.send(system: fullSystem, user: body, schema: schema, effort: "low", maxTokens: 8000)
        let flights = try JSONDecoder().decode(Response.self, from: Data(text.utf8)).flights
        let byIndex = Dictionary(uniqueKeysWithValues: batch.map { ($0.0, $0.1) })
        return flights.compactMap { e in byIndex[e.mailIndex].map { (e, $0) } }
    }

    /// Runs the extraction over all mails (3 requests in parallel) and reconciles changes/cancellations.
    static func extract(_ mails: [OutlookMail.MailItem], progress: @escaping @MainActor (String) -> Void) async throws -> [FlightCandidate] {
        let indexed = Array(mails.enumerated()).map { ($0.offset + 1, $0.element) }
        let batches = stride(from: 0, to: indexed.count, by: mailsPerRequest).map { Array(indexed[$0..<min($0 + mailsPerRequest, indexed.count)]) }
        var found: [(Extracted, OutlookMail.MailItem)] = []
        var done = 0
        var lastError: Error?

        for chunk in stride(from: 0, to: batches.count, by: 3).map({ Array(batches[$0..<min($0 + 3, batches.count)]) }) {
            await withTaskGroup(of: Result<[(Extracted, OutlookMail.MailItem)], Error>.self) { group in
                for b in chunk { group.addTask { do { return .success(try await request(b)) } catch { return .failure(error) } } }
                for await r in group {
                    switch r {
                    case .success(let list): found += list
                    case .failure(let e): lastError = e
                    }
                    done += 1
                    await progress("KI liest Mails … \(min(done * mailsPerRequest, mails.count))/\(mails.count) · \(found.count) Flugabschnitte")
                }
            }
        }
        if found.isEmpty, let lastError { throw lastError }

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
        return latest.values.compactMap { item -> FlightCandidate? in
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
            c.cancelled = e.status == "cancelled"
            return c
        }
        .sorted { $0.date > $1.date }
    }
}

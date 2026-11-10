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
        let variants = nameVariants(passengerName)
        guard variants.contains(where: { !$0.isEmpty }) else { return !e.forwarded }
        if e.passengers.isEmpty { return !e.forwarded }
        let titles: Set<String> = ["mr", "mrs", "ms", "miss", "mstr", "herr", "frau", "dr", "prof", "sr", "sra", "m", "mme"]
        return e.passengers.contains { p in
            let tokens = tokens(p)
            return variants.contains { parts in
                // surname as a whole word ("Meier" must not match "Obermeier"), or glued ticket style "MUSTERRAFFAELMR"
                guard let surname = parts.last else { return false }
                let glued = tokens.count == 1 && tokens[0].hasPrefix(surname) && tokens[0].count > surname.count
                guard tokens.contains(surname) || glued else { return false }
                // if the ticket shows a given name, it must be ours (first name or initial) – keeps family members out
                let firsts = parts.dropLast()
                let others = glued ? [String(tokens[0].dropFirst(surname.count))] : tokens.filter { $0 != surname && !titles.contains($0) }
                guard !firsts.isEmpty, !others.isEmpty else { return true }
                return others.contains { o in firsts.contains { f in o.hasPrefix(f) || f.hasPrefix(o) } }
            }
        }
    }

    private static func fold(_ s: String) -> String { s.lowercased().folding(options: .diacriticInsensitive, locale: nil) }

    private static func tokens(_ s: String) -> [String] {
        fold(s).split { !$0.isLetter }.map(String.init).filter { !$0.isEmpty }
    }

    /// "Müller" appears on tickets as MULLER or MUELLER – accept both.
    static func nameVariants(_ name: String) -> [[String]] {
        let translit = name.lowercased().replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        let a = tokens(name).filter { $0.count >= 2 }, b = tokens(translit).filter { $0.count >= 2 }
        return a == b ? [a] : [a, b]
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
            // A cancellation after the newest confirmation wins, even for a leg that confirmation contains
            result += group.filter { $0.0.mailType == "cancellation" && $0.1.received > newestFull.received && currentKeys.contains(flightKey($0.0)) }
            for item in group where !currentKeys.contains(flightKey(item.0)) {
                switch item.0.mailType {
                case "boardingpass", "checkin":
                    result.append(item)                        // proof of travel
                case "reminder", "other":
                    if item.1.received > newestFull.received { result.append(item) }
                case "cancellation":
                    result.append(item)                        // handled as cancelled below
                default:
                    // Older leg: outdated only if the newest mail contains a replacement for it. A partial mail
                    // (schedule change for one leg, seat purchase) must not delete the rest of the trip.
                    if !current.contains(where: { replaces($0.0, item.0) }) { result.append(item) }
                }
            }
        }
        return result
    }

    /// `new` is the re-booked version of `old`: same route, or same origin/destination within 2 days.
    private static func replaces(_ new: Extracted, _ old: Extracted) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        let days = f.date(from: new.date).flatMap { n in f.date(from: old.date).map { abs(n.timeIntervalSince($0)) / 86400 } } ?? 99
        let nf = new.from.uppercased(), nt = new.to.uppercased(), of = old.from.uppercased(), ot = old.to.uppercased()
        if nf == of && nt == ot { return days <= 3 }
        return (nf == of || nt == ot) && days <= 2
    }

    /// Real flight numbers only ("LX 92", "U2 1234") – not years, prices or order numbers.
    static let flightNumberPattern = "\\b(?:[A-Z]{2}|[A-Z]\\d|\\d[A-Z])\\s?\\d{2,4}\\b"

    static let maxCharsPerMail = 9000

    /// Text sent to the AI: the start of the mail plus the passages around every flight number (long mails are not just cut off).
    static func relevantText(_ m: OutlookMail.MailItem) -> String {
        let text = m.text
        guard text.count > maxCharsPerMail else { return text }
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: flightNumberPattern)
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
        let nameParts = Set(nameVariants(passengerName).flatMap { $0 }.filter { $0.count >= 3 })
        return mails.filter { m in
            let full = m.subject + " " + m.text
            let t = (m.subject + " " + m.text.prefix(6000)).lowercased()
            guard keywords.contains(where: { t.contains($0) }) else { return false }
            // With a name set, the mail must mention at least part of it (anywhere, umlauts folded)
            if !nameParts.isEmpty {
                let folded = fold(full)
                if !nameParts.contains(where: { folded.contains($0) }) { return false }
            }
            let stay = ["hotel", "booking.com", "airbnb", "unterkunft", "übernachtung", "check-in:", "anreise", "mietwagen", "car rental",
                        "sixt", "hertz", "europcar", "avis", "enterprise", "zugticket", "sbb", "trainline", "deutsche bahn", "flixbus"]
            if stay.contains(where: { t.contains($0) }) { return true }
            return full.range(of: flightNumberPattern, options: .regularExpression) != nil
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
        let text = try await AIClient.send(system: fullSystem, user: body, schema: schema, effort: "low", maxTokens: 16000)
        let response = try JSONDecoder().decode(Response.self, from: Data(text.utf8))
        let byIndex = Dictionary(uniqueKeysWithValues: batch.map { ($0.0, $0.1) })
        return (response.flights.compactMap { e in byIndex[e.mailIndex].map { (e, $0) } },
                response.bookings.compactMap { b in byIndex[b.mailIndex].map { (b, $0) } })
    }

    struct ExtractResult {
        var flights: [FlightCandidate]
        var bookings: [TravelBooking]
        /// Mails the AI could not read (after retries)
        var failedMails = 0
        var failure: String?
    }

    /// One batch; if it fails (bad JSON, too long), the mails are tried one by one so a single odd mail doesn't lose six.
    private static func requestResilient(_ batch: [(Int, OutlookMail.MailItem)]) async
        -> (flights: [(Extracted, OutlookMail.MailItem)], bookings: [(ExtractedBooking, OutlookMail.MailItem)], failed: Int, error: Error?) {
        do {
            let r = try await request(batch)
            return (r.0, r.1, 0, nil)
        } catch {
            guard batch.count > 1, !(error is AIClient.Failure && (error as? AIClient.Failure)?.fatal == true) else {
                return ([], [], batch.count, error)
            }
            var flights: [(Extracted, OutlookMail.MailItem)] = [], bookings: [(ExtractedBooking, OutlookMail.MailItem)] = []
            var failed = 0
            var last: Error? = nil
            for one in batch {
                do {
                    let r = try await request([one])
                    flights += r.0
                    bookings += r.1
                } catch {
                    failed += 1
                    last = error
                }
            }
            return (flights, bookings, failed, last)
        }
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
        var failedMails = 0

        for chunk in stride(from: 0, to: batches.count, by: 3).map({ Array(batches[$0..<min($0 + 3, batches.count)]) }) {
            await withTaskGroup(of: (flights: [(Extracted, OutlookMail.MailItem)], bookings: [(ExtractedBooking, OutlookMail.MailItem)], failed: Int, error: Error?).self) { group in
                for b in chunk { group.addTask { await requestResilient(b) } }
                for await r in group {
                    found += r.flights
                    foundBookings += r.bookings
                    failedMails += r.failed
                    if let e = r.error { lastError = e }
                    done += 1
                    await progress("KI liest Mails … \(min(done * mailsPerRequest, mails.count))/\(mails.count) · \(found.count) Flugabschnitte")
                }
            }
        }
        if found.isEmpty && foundBookings.isEmpty, let lastError { throw lastError }

        // Only the owner's flights take part in reconciliation (someone else's newer mail must not replace ours)
        found = reconcileBookings(found.filter { belongsToOwner($0.0) })

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

        return ExtractResult(flights: flights, bookings: convertBookings(foundBookings),
                             failedMails: failedMails, failure: failedMails > 0 ? lastError?.localizedDescription : nil)
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

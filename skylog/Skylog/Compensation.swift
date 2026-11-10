import Foundation

/// Rough check of passenger compensation under EU Regulation 261/2004 (also applies in Switzerland).
enum Compensation {
    /// EU + EEA + Switzerland
    static let coveredCountries: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU",
        "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO", "CH",
    ]

    /// Airlines licensed in the EU/EEA/CH (IATA codes) – relevant for flights *into* Europe.
    static let europeanCarriers: Set<String> = [
        "LX", "WK", "2L", "GM", "DS", "LH", "OS", "SN", "EW", "4U", "EN", "DE", "X3", "U2", "EC", "FR", "RK", "W6",
        "W4", "W9", "VY", "IB", "I2", "UX", "V7", "AF", "KL", "HV", "TO", "EI", "AZ", "TP", "SK", "AY", "DY", "D8",
        "LO", "OK", "A3", "OA", "BT", "FB", "RO", "LG", "XR", "OU", "JP", "SM", "NT", "BJ", "TB", "OR", "6B", "HF",
        "FI", "OG", "WF", "DX", "N0", "H4", "YW", "PM", "NI", "S4", "HG", "3O",
    ]

    struct Result {
        enum Status { case eligible, possible, notEligible, unknown }
        let status: Status
        let amountEUR: Int
        let headline: String
        let details: [String]
    }

    static func arrivalDelayMinutes(_ f: Flight) -> Int? {
        // only real arrival times count – an estimate is not a claim yet
        guard let scheduled = f.arrival.scheduled,
              let actual = f.arrival.runway ?? (f.normalizedStatus == .arrived ? f.arrival.revised : nil) else { return nil }
        return Int(actual.timeIntervalSince(scheduled) / 60)
    }

    static func amount(distance km: Double, intraEurope: Bool, delayMinutes: Int?) -> Int {
        if km <= 1500 { return 250 }
        if intraEurope || km <= 3500 { return 400 }
        // > 3500 km outside Europe: may be halved when arriving 3–4 h late
        if let d = delayMinutes, d < 240 { return 300 }
        return 600
    }

    static func check(_ f: Flight) -> Result {
        let dep = f.departure.countryCode?.uppercased() ?? ""
        let arr = f.arrival.countryCode?.uppercased() ?? ""
        let carrier = (f.airlineIata ?? String(f.number.prefix(2))).uppercased()
        let fromEurope = coveredCountries.contains(dep)
        let intoEuropeWithEUCarrier = coveredCountries.contains(arr) && europeanCarriers.contains(carrier)
        let intraEurope = coveredCountries.contains(dep) && coveredCountries.contains(arr)

        guard !dep.isEmpty, !arr.isEmpty else {
            return Result(status: .unknown, amountEUR: 0, headline: String(localized: "Nicht prüfbar"), details: [String(localized: "Länder der Flughäfen unbekannt – Flug aktualisieren.")])
        }
        guard fromEurope || intoEuropeWithEUCarrier else {
            var details = [String(localized: "Die EU-Fluggastrechte gelten für Abflüge aus EU/EWR/Schweiz und für Flüge dorthin mit einer europäischen Airline.")]
            if dep == "GB" || arr == "GB" { details.append(String(localized: "Für Grossbritannien gelten ähnliche Regeln (UK261) – prüfe diese separat.")) }
            return Result(status: .notEligible, amountEUR: 0, headline: String(localized: "Nicht abgedeckt"), details: details)
        }

        let km = f.computedDistanceKm ?? 0
        let delay = arrivalDelayMinutes(f)
        let money = amount(distance: km, intraEurope: intraEurope, delayMinutes: delay)
        let caveat = String(localized: "Kein Anspruch bei aussergewöhnlichen Umständen (z.B. Unwetter, Fluglotsenstreik, Sicherheitsrisiko). Streiks des eigenen Airline-Personals zählen in der Regel nicht dazu.")

        switch f.normalizedStatus {
        case .canceled:
            return Result(status: .possible, amountEUR: money, headline: String(localized: "Annullierung: bis zu \(money) €"),
                          details: [String(localized: "Anspruch, wenn die Annullierung weniger als 14 Tage vor Abflug mitgeteilt wurde und die Ersatzbeförderung zu spät ankam."),
                                    String(localized: "Zusätzlich: Recht auf Erstattung des Tickets oder Ersatzflug sowie Verpflegung/Hotel."), caveat])
        case .diverted:
            return Result(status: .possible, amountEUR: money, headline: String(localized: "Umleitung: evtl. bis zu \(money) €"),
                          details: [String(localized: "Massgeblich ist die Verspätung am ursprünglichen Ziel."), caveat])
        default:
            break
        }

        guard let delay else {
            return Result(status: .unknown, amountEUR: money, headline: String(localized: "Ankunftszeit unbekannt"),
                          details: [String(localized: "Sobald die tatsächliche Ankunftszeit bekannt ist, wird erneut geprüft.")])
        }
        if delay >= 180 {
            return Result(status: .eligible, amountEUR: money,
                          headline: String(localized: "Anspruch wahrscheinlich: \(money) € pro Person"),
                          details: [String(localized: "Ankunft \(Fmt.duration(delay)) zu spät (ab 3 Stunden besteht Anspruch)."),
                                    String(localized: "Distanz \(Fmt.km(km)) → \(money) €."), caveat,
                                    String(localized: "Frist: in der Schweiz und Deutschland meist bis 3 Jahre, je nach Land unterschiedlich.")])
        }
        return Result(status: .notEligible, amountEUR: 0,
                      headline: delay > 0 ? String(localized: "Verspätung \(Fmt.duration(delay)) – unter 3 h") : String(localized: "Pünktlich"),
                      details: [String(localized: "Entschädigung gibt es erst ab 3 Stunden Verspätung bei Ankunft.")])
    }

    // MARK: Claim letter

    struct Claimant: Codable {
        var name = ""
        var address = ""
        var email = ""
        var iban = ""
        var bookingCode = ""
        var passengers = 1

        static var saved: Claimant {
            get { UserDefaults.standard.data(forKey: "claimant").flatMap { try? JSONDecoder().decode(Claimant.self, from: $0) } ?? Claimant() }
            set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "claimant") }
        }
    }

    static func letter(_ f: Flight, _ c: Claimant, result: Result, english: Bool) -> String {
        let date = Fmt.day(f.departure.scheduled ?? f.sortDate, f.departure.tz)
        let delay = arrivalDelayMinutes(f).map(Fmt.duration) ?? "–"
        let total = result.amountEUR * max(c.passengers, 1)
        let route = "\(f.departure.displayCity) (\(f.departure.code)) – \(f.arrival.displayCity) (\(f.arrival.code))"
        let cancelled = f.normalizedStatus == .canceled
        if english {
            return """
            \(c.name)
            \(c.address)
            \(c.email)

            To: \(f.airlineName ?? "the airline") – Customer Relations / Claims

            Subject: Compensation claim under Regulation (EC) No 261/2004 – flight \(f.number) on \(date), booking \(c.bookingCode)

            Dear Sir or Madam,

            I was booked on flight \(f.number) from \(route) on \(date) (booking reference \(c.bookingCode), \(c.passengers) passenger(s)). \
            \(cancelled ? "The flight was cancelled." : "The flight arrived at the final destination \(delay) late.")

            Under Articles 5, 6 and 7 of Regulation (EC) No 261/2004 and the case law of the Court of Justice of the EU (C-402/07 Sturgeon, C-581/10 Nelson), \
            I am entitled to compensation of EUR \(result.amountEUR) per passenger, i.e. EUR \(total) in total.

            Please transfer the amount within 14 days to:
            Account holder: \(c.name)
            IBAN: \(c.iban)

            Should you consider that extraordinary circumstances applied, please provide detailed evidence.

            Kind regards,
            \(c.name)
            """
        }
        return """
        \(c.name)
        \(c.address)
        \(c.email)

        An: \(f.airlineName ?? "die Fluggesellschaft") – Kundendienst / Reklamationen

        Betreff: Ausgleichsanspruch gemäss Verordnung (EG) Nr. 261/2004 – Flug \(f.number) vom \(date), Buchung \(c.bookingCode)

        Sehr geehrte Damen und Herren

        Ich war für den Flug \(f.number) von \(route) am \(date) gebucht (Buchungscode \(c.bookingCode), \(c.passengers) Person(en)). \
        \(cancelled ? "Der Flug wurde annulliert." : "Der Flug erreichte das Endziel mit einer Verspätung von \(delay).")

        Gemäss Art. 5, 6 und 7 der Verordnung (EG) Nr. 261/2004 sowie der Rechtsprechung des EuGH (C-402/07 Sturgeon, C-581/10 Nelson) \
        steht mir eine Ausgleichszahlung von EUR \(result.amountEUR) pro Person zu, insgesamt EUR \(total).

        Bitte überweisen Sie den Betrag innert 14 Tagen auf folgendes Konto:
        Kontoinhaber: \(c.name)
        IBAN: \(c.iban)

        Sollten Sie sich auf aussergewöhnliche Umstände berufen, bitte ich um einen detaillierten Nachweis.

        Freundliche Grüsse
        \(c.name)
        """
    }
}

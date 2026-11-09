import Foundation
import PDFKit

struct FlightCandidate: Identifiable, Hashable {
    var id: String { number + "|" + Fmt.apiDate.string(from: date) }
    let number: String
    let date: Date
    let source: String
    let airports: [String]
    /// Filled by the AI extraction
    var departureTime: String? = nil
    var arrivalTime: String? = nil
    var arrivalDayOffset: Int = 0
    var bookingReference: String? = nil
    var aiVerified = false
    var cancelled = false
}

/// Finds flight numbers + dates in free text (booking confirmations, boarding passes, itineraries).
enum FlightTextParser {
    static let airlines: Set<String> = [
        "LX", "WK", "2L", "GM", "DS", "LH", "OS", "SN", "EW", "4U", "EN", "DE", "X3", "U2", "FR", "RK", "W6", "W4", "W9",
        "VY", "IB", "I2", "UX", "V7", "AF", "KL", "HV", "TO", "BA", "VS", "EI", "LS", "BY", "AZ", "TP", "SK", "AY", "DY",
        "D8", "LO", "OK", "A3", "OA", "TK", "PC", "XQ", "EK", "QR", "EY", "SV", "MS", "RJ", "LY", "GF", "WY", "KU", "FZ",
        "G9", "ET", "KQ", "SA", "AT", "UA", "AA", "DL", "AC", "WS", "B6", "AS", "WN", "NK", "F9", "AM", "LA", "AV", "CM",
        "G3", "AD", "CX", "SQ", "TR", "MH", "AK", "TG", "VN", "GA", "PR", "5J", "CI", "BR", "JL", "NH", "KE", "OZ", "CA",
        "MU", "CZ", "HU", "QF", "VA", "NZ", "JQ", "AI", "6E", "BT", "OU", "JU", "FB", "RO", "PS", "KM", "TU", "AH", "3O",
        "MK", "HM", "XR", "XC", "SM", "TB", "OR", "6B", "BJ", "WF", "LG", "FI", "OG", "VL", "EB", "HF", "QS", "Y4", "TS",
        "UL", "PK", "SU", "AR", "JA", "H2", "FO", "JJ", "4M", "XL", "VB", "WM", "Z8", "OB", "5Z", "SY", "WN", "G4", "MX", "S7", "HY", "KC", "J2", "A9", "ZF", "4Y", "DX", "N0", "H4", "8Q", "XY", "J9", "OV", "IZ", "NO",
    ]

    static let keywords = ["flug", "flight", "vol ", "flt", "abflug", "departure", "boarding", "carrier"]

    static let notAirports: Set<String> = [
        "THE", "AND", "FOR", "EUR", "CHF", "USD", "GBP", "GMT", "UTC", "CET", "CEST", "PNR", "MON", "TUE", "WED", "THU",
        "FRI", "SAT", "SUN", "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC", "VON",
        "UND", "DER", "DIE", "DAS", "NUR", "BEI", "MIT", "ZUM", "ZUR", "PDF", "APP", "WEB", "FAQ", "TAX", "VAT", "ETA",
        "ETD", "STD", "STA", "ATD", "ATA", "NEW", "ALL", "NOT", "YOU", "ARE", "OUR", "ADT", "CHD", "INF", "MRS", "MR",
        "OKT", "DEZ", "MAI", "MÄR", "HTML", "WWW", "COM", "SEQ", "PAX", "BAG", "GATE", "FLT", "VIA", "NON", "REF", "TKT",
        "QR", "ECO", "BUS", "FIR", "OPS", "INFO", "NET", "ORG", "API", "SMS", "IBAN",
    ]

    private static let monthPattern = "(jan|feb|f[eé]v|m[aä]r|apr|avr|ma[iy]|jun|jul|aug|ao[uû]|sep|o[ck]t|nov|d[eé][cz])"

    private static func month(_ s: String) -> Int? {
        let p = String(s.lowercased().prefix(3))
        let map: [String: Int] = [
            "jan": 1, "feb": 2, "fév": 2, "fev": 2, "mar": 3, "mär": 3, "apr": 4, "avr": 4, "mai": 5, "may": 5,
            "jun": 6, "jul": 7, "aug": 8, "aoû": 8, "aou": 8, "sep": 9, "okt": 10, "oct": 10, "nov": 11,
            "dez": 12, "dec": 12, "déc": 12,
        ]
        return map[p]
    }

    private static let monthNames = [
        "january", "januar", "janvier", "february", "februar", "février", "fevrier", "march", "märz", "maerz", "mars",
        "april", "avril", "may", "mai", "june", "juni", "july", "juli", "august", "août", "aout", "september", "septembre",
        "october", "oktober", "octobre", "november", "novembre", "december", "dezember", "décembre", "decembre",
    ]

    private static func isMonthWord(_ word: String) -> Bool {
        let w = word.lowercased()
        return w.count >= 3 && monthNames.contains { $0.hasPrefix(w) }
    }

    static func parse(_ raw: String, source: String, reference: Date = Date()) -> [FlightCandidate] {
        let text = raw.replacingOccurrences(of: "\u{00A0}", with: " ")
        let ns = text as NSString
        let lower = text.lowercased() as NSString
        let dates = findDates(text, reference: reference)
        guard !dates.isEmpty else { return [] }

        let flightRegex = try! NSRegularExpression(pattern: "(?<![A-Za-z0-9])([A-Z][A-Z0-9]|[0-9][A-Z])[ -]?(\\d{1,4})(?![0-9])")
        var result: [String: FlightCandidate] = [:]

        for m in flightRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let code = ns.substring(with: m.range(at: 1))
            let digits = ns.substring(with: m.range(at: 2))
            let contextStart = max(0, m.range.location - 60)
            let context = lower.substring(with: NSRange(location: contextStart, length: m.range.location - contextStart))
            let known = airlines.contains(code)
            guard known || keywords.contains(where: { context.contains($0) }) else { continue }

            let nearest = dates.min { abs($0.location - m.range.location) < abs($1.location - m.range.location) }
            guard let date = nearest, abs(date.location - m.range.location) < 700 else { continue }

            let number = code + String(Int(digits) ?? 0)
            let candidate = FlightCandidate(number: number, date: date.date, source: source,
                                            airports: airports(near: m.range.location, in: ns))
            if result[candidate.id] == nil { result[candidate.id] = candidate }
        }
        return result.values.sorted { $0.date < $1.date }
    }

    private static func airports(near location: Int, in ns: NSString) -> [String] {
        let start = max(0, location - 200)
        let length = min(ns.length - start, 450)
        let snippet = ns.substring(with: NSRange(location: start, length: length))
        let regex = try! NSRegularExpression(pattern: "(?<![A-Za-z])([A-Z]{3})(?![A-Za-z])")
        let sns = snippet as NSString
        var codes: [String] = []
        for m in regex.matches(in: snippet, range: NSRange(location: 0, length: sns.length)) {
            let c = sns.substring(with: m.range(at: 1))
            if !notAirports.contains(c) && !codes.contains(c) { codes.append(c) }
            if codes.count == 2 { break }
        }
        return codes
    }

    private struct FoundDate { let date: Date; let location: Int }

    private static func findDates(_ text: String, reference: Date) -> [FoundDate] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var found: [FoundDate] = []
        let cal = Calendar.current

        func make(_ d: Int, _ m: Int, _ y: Int?, at loc: Int) {
            guard (1...31).contains(d), (1...12).contains(m) else { return }
            var year = y ?? cal.component(.year, from: reference)
            if year < 100 { year += 2000 }
            guard (2000...2100).contains(year) else { return }
            guard var date = cal.date(from: DateComponents(year: year, month: m, day: d, hour: 12)) else { return }
            if y == nil, date < reference.addingTimeInterval(-60 * 86400),
               let next = cal.date(byAdding: .year, value: 1, to: date) { date = next }
            found.append(FoundDate(date: date, location: loc))
        }

        func each(_ pattern: String, _ handler: (NSTextCheckingResult) -> Void) {
            let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            regex.matches(in: text, range: full).forEach(handler)
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }

        // 12.11.2026, 12/11/26
        each("(?<!\\d)(\\d{1,2})[./](\\d{1,2})[./](\\d{4}|\\d{2})(?!\\d)") { m in
            make(Int(group(m, 1)!)!, Int(group(m, 2)!)!, Int(group(m, 3)!), at: m.range.location)
        }
        // 2026-11-12
        each("(?<!\\d)(\\d{4})-(\\d{2})-(\\d{2})(?!\\d)") { m in
            make(Int(group(m, 3)!)!, Int(group(m, 2)!)!, Int(group(m, 1)!), at: m.range.location)
        }
        // 12. November 2026, 12 Nov 26, 12NOV
        each("(?<![\\d.])(\\d{1,2})\\.?\\s?(\(monthPattern)[a-zäéû]*)\\.?,?\\s?(\\d{4}|\\d{2})?(?![\\d:])") { m in
            guard let word = group(m, 2), isMonthWord(word), let mo = month(word) else { return }
            make(Int(group(m, 1)!)!, mo, group(m, 4).flatMap { Int($0) }, at: m.range.location)
        }
        // November 12, 2026
        each("(\(monthPattern)[a-zäéû]*)\\.?\\s(\\d{1,2}),?\\s(\\d{4})") { m in
            guard let word = group(m, 1), isMonthWord(word), let mo = month(word) else { return }
            make(Int(group(m, 3)!)!, mo, Int(group(m, 4)!), at: m.range.location)
        }
        return found
    }
}

/// Extracts readable text from PDFs, .eml and HTML files.
enum DocumentText {
    static func extract(from url: URL) -> String? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return PDFDocument(url: url)?.string }
        guard let data = try? Data(contentsOf: url) else { return nil }
        var text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        if ext == "eml" || text.contains("Content-Transfer-Encoding") { text = decodeMIME(text) }
        return stripHTML(text)
    }

    static func decodeMIME(_ raw: String) -> String {
        var out = decodeQuotedPrintable(raw)
        let regex = try! NSRegularExpression(
            pattern: "Content-Transfer-Encoding:\\s*base64[^\\n]*\\n(?:[^\\n]*\\S[^\\n]*\\n)*?\\s*\\n([A-Za-z0-9+/=\\r\\n]+)",
            options: [.caseInsensitive])
        let ns = raw as NSString
        for m in regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)) {
            let blob = ns.substring(with: m.range(at: 1)).components(separatedBy: .whitespacesAndNewlines).joined()
            if let data = Data(base64Encoded: blob),
               let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                out += "\n" + s
            }
        }
        return out
    }

    static func decodeQuotedPrintable(_ s: String) -> String {
        let joined = s.replacingOccurrences(of: "=\r\n", with: "").replacingOccurrences(of: "=\n", with: "")
        var bytes: [UInt8] = []
        let chars = Array(joined.utf8)
        var i = 0
        while i < chars.count {
            if chars[i] == UInt8(ascii: "="), i + 2 < chars.count,
               let v = UInt8(String(bytes: chars[(i + 1)...(i + 2)], encoding: .ascii) ?? "", radix: 16) {
                bytes.append(v)
                i += 3
            } else {
                bytes.append(chars[i])
                i += 1
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func stripHTML(_ s: String) -> String {
        guard s.range(of: "<[a-zA-Z/][^>]*>", options: .regularExpression) != nil else { return s }
        var t = s.replacingOccurrences(of: "(?is)<(style|script)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</tr>|</div>|</h\\d>|</li>", with: "\n", options: .regularExpression)
        t = t.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'",
                        "&ndash;": "–", "&mdash;": "—", "&rarr;": "→", "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü",
                        "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü", "&szlig;": "ß"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        return t.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    }
}

import Foundation
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let card = Color(white: 0.12)
}

extension FlightStatus {
    var color: Color {
        switch self {
        case .scheduled, .checkIn, .unknown: .green
        case .delayed: .orange
        case .boarding, .gateClosed, .taxiing: .yellow
        case .departed, .enRoute, .approaching: Theme.accent
        case .arrived: .teal
        case .canceled, .diverted: .red
        }
    }
}

enum Fmt {
    static let apiDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let parsers: [DateFormatter] = [
        "yyyy-MM-dd HH:mmXXX", "yyyy-MM-dd HH:mmX", "yyyy-MM-dd HH:mm:ssXXX", "yyyy-MM-dd HH:mm:ssX",
        "yyyy-MM-dd'T'HH:mm:ssXXX", "yyyy-MM-dd'T'HH:mm:ss.SSSXXX", "yyyy-MM-dd'T'HH:mmXXX",
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        for f in parsers {
            if let d = f.date(from: string) { return d }
        }
        return nil
    }

    static func time(_ date: Date?, _ tz: TimeZone) -> String {
        guard let date else { return "–" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_CH")
        f.timeZone = tz
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    static func day(_ date: Date?, _ tz: TimeZone = .current) -> String {
        guard let date else { return "–" }
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate("EEEdMMMyyyy")
        return f.string(from: date)
    }

    static func tzAbbrev(_ tz: TimeZone, at date: Date?) -> String {
        tz.abbreviation(for: date ?? Date()) ?? tz.identifier
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func countdown(_ interval: TimeInterval) -> String {
        let total = Int(max(interval, 0) / 60)
        let d = total / 1440, h = (total % 1440) / 60, m = total % 60
        if d > 0 { return String(localized: "\(d)T \(h)h") }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func delay(_ minutes: Int?) -> String? {
        guard let minutes, abs(minutes) >= 5 else { return nil }
        return minutes > 0 ? "+\(Fmt.duration(minutes))" : "−\(Fmt.duration(-minutes))"
    }

    static func delayColor(_ minutes: Int?) -> Color {
        guard let minutes else { return .secondary }
        // one scale everywhere (app, widgets, status page): from 5 min orange, from 15 min red
        if minutes >= 15 { return .red }
        if minutes >= 5 { return .orange }
        return .green
    }

    static func km(_ km: Double) -> String {
        km.formatted(.number.precision(.fractionLength(0))) + " km"
    }

    static func summary(_ f: Flight) -> String {
        let now = Date()
        switch f.normalizedStatus {
        case .canceled: return String(localized: "Annulliert")
        case .diverted: return String(localized: "Umgeleitet")
        default: break
        }
        if f.isPast { return day(f.sortDate, f.departure.tz) }
        if f.isInAir, let a = f.arrival.best { return String(localized: "Landung in \(countdown(a.timeIntervalSince(now)))") }
        if f.normalizedStatus == .arrived { return String(localized: "Gelandet") }
        if let d = f.departure.best {
            let diff = d.timeIntervalSince(now)
            if diff > 3 * 86400 { return day(d, f.departure.tz) }
            return diff > 0 ? String(localized: "Abflug in \(countdown(diff))") : String(localized: "Abflug fällig")
        }
        return f.date
    }

    static func shareText(_ f: Flight) -> String {
        var s = "✈️ \(f.number) \(f.departure.code) → \(f.arrival.code)\n"
        s += "\(f.normalizedStatus.label)\n"
        s += String(localized: "Abflug: \(time(f.departure.best, f.departure.tz)) (\(f.departure.displayCity))")
        if let g = f.departure.gate { s += String(localized: ", Gate \(g)") }
        s += "\n" + String(localized: "Ankunft: \(time(f.arrival.best, f.arrival.tz)) (\(f.arrival.displayCity))")
        if let b = f.arrival.baggageBelt { s += String(localized: ", Gepäckband \(b)") }
        return s
    }
}

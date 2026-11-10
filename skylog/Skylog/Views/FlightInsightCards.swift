import SwiftUI

// MARK: - Detailed timetable (gate / runway times)

struct TimetableCard: View {
    let flight: Flight

    var body: some View {
        if let t = flight.timetable {
            let dtz = flight.departure.tz, atz = flight.arrival.tz
            VStack(alignment: .leading, spacing: 10) {
                Label("Zeiten im Detail", systemImage: "clock.badge.checkmark").font(.headline)
                header
                Text("ABFLUG").font(.caption2).foregroundStyle(.secondary)
                timeRow("Gate verlassen", t.outScheduled, t.outActual ?? t.outEstimated, actual: t.outActual != nil, tz: dtz)
                durationRow("Rollen", span(t.outScheduled, t.offScheduled), span(t.outActual ?? t.outEstimated, t.offActual ?? t.offEstimated))
                timeRow("Start", t.offScheduled, t.offActual ?? t.offEstimated, actual: t.offActual != nil, tz: dtz)
                Divider()
                Text("ANKUNFT").font(.caption2).foregroundStyle(.secondary)
                timeRow("Landung", t.onScheduled, t.onActual ?? t.onEstimated, actual: t.onActual != nil, tz: atz)
                durationRow("Rollen", span(t.onScheduled, t.inScheduled), span(t.onActual ?? t.onEstimated, t.inActual ?? t.inEstimated))
                timeRow("Am Gate", t.inScheduled, t.inActual ?? t.inEstimated, actual: t.inActual != nil, tz: atz)
                Divider()
                durationRow("Flugzeit", span(t.offScheduled, t.onScheduled), span(t.offActual ?? t.offEstimated, t.onActual ?? t.onEstimated))
                durationRow("Gesamt", span(t.outScheduled, t.inScheduled), span(t.outActual ?? t.outEstimated, t.inActual ?? t.inEstimated))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var header: some View {
        HStack {
            Spacer()
            Text("Geplant").frame(width: 70, alignment: .trailing)
            Text("Aktuell").frame(width: 80, alignment: .trailing)
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func span(_ a: Date?, _ b: Date?) -> Int? {
        guard let a, let b, b >= a else { return nil }
        return Int((b.timeIntervalSince(a) / 60).rounded())
    }

    private func color(_ late: Int?) -> Color {
        guard let late else { return .primary }
        return late >= 15 ? .red : late >= 5 ? .orange : .green
    }

    private func timeRow(_ title: String, _ scheduled: Date?, _ current: Date?, actual: Bool, tz: TimeZone) -> some View {
        let late = scheduled.flatMap { s in current.map { Int(($0.timeIntervalSince(s) / 60).rounded()) } }
        return HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.subheadline)
                if current != nil { Text(actual ? "tatsächlich" : "erwartet").font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(Fmt.time(scheduled, tz)).frame(width: 70, alignment: .trailing).foregroundStyle(.secondary)
            Text(Fmt.time(current, tz)).frame(width: 80, alignment: .trailing).fontWeight(.semibold).foregroundStyle(color(late))
        }
        .font(.subheadline.monospacedDigit())
    }

    private func durationRow(_ title: String, _ scheduled: Int?, _ current: Int?) -> some View {
        let late = scheduled.flatMap { s in current.map { $0 - s } }
        return HStack {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(scheduled.map(Fmt.duration) ?? "–").frame(width: 70, alignment: .trailing).foregroundStyle(.secondary)
            Text(current.map(Fmt.duration) ?? "–").frame(width: 80, alignment: .trailing).foregroundStyle(color(late))
        }
        .font(.subheadline.monospacedDigit())
    }
}

// MARK: - Where is my plane?

struct PlaneHistoryCard: View {
    let flight: Flight

    var body: some View {
        if let legs = flight.planeLegs, !legs.isEmpty, !flight.isPast {
            VStack(alignment: .leading, spacing: 10) {
                Label("Wo ist mein Flugzeug?", systemImage: "airplane.circle").font(.headline)
                if let model = flight.aircraftModel ?? flight.aircraftReg {
                    Text([model, flight.aircraftModel == nil ? nil : flight.aircraftReg].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let i = flight.inbound {
                    let delay = i.expectedDelay(ourDeparture: flight.departure.best)
                    Label(i.isCanceled ? "Zubringer annulliert" : delay >= 15 ? "Wird knapp: ca. \(delay) Min. Verspätung möglich" : "Alles gut – genug Zeit für deinen Abflug",
                          systemImage: i.isCanceled || delay >= 15 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(i.isCanceled ? .red : delay >= 15 ? .orange : .green)
                }
                row(title: "Dein Flug · \(flight.departure.code) → \(flight.arrival.code)",
                    detail: "Abflug \(Fmt.time(flight.departure.best, flight.departure.tz))",
                    delay: flight.departure.delayMinutes, icon: "circle")
                ForEach(Array(legs.prefix(4).enumerated()), id: \.offset) { _, leg in
                    row(title: "\(leg.fromCode) → \(leg.toCode ?? "?") · \(leg.number)",
                        detail: leg.landed ? "Gelandet \(Fmt.time(leg.arrival, flight.departure.tz))"
                            : leg.departed ? "In der Luft · Landung \(Fmt.time(leg.arrival, flight.departure.tz))"
                            : "Geplant · Landung \(Fmt.time(leg.arrival, flight.departure.tz))",
                        delay: leg.arrivalDelay, icon: leg.landed ? "checkmark.circle" : leg.departed ? "airplane" : "clock")
                }
                Text("Zeiten in der Ortszeit von \(flight.departure.code).").font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func row(title: String, detail: String, delay: Int?, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let d = delay {
                Text(d >= 5 ? "\(Fmt.duration(d)) später" : d <= -5 ? "\(Fmt.duration(-d)) früher" : "Pünktlich")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(d >= 15 ? .red : d >= 5 ? .orange : .green)
            }
        }
    }
}

// MARK: - My history on this route

struct RouteHistoryCard: View {
    let flight: Flight
    @Environment(FlightStore.self) private var store

    var body: some View {
        let same = store.flights.filter {
            $0.id != flight.id && $0.isPast && $0.normalizedStatus != .canceled
                && $0.departure.code == flight.departure.code && $0.arrival.code == flight.arrival.code
        }
        let reverse = store.flights.filter {
            $0.id != flight.id && $0.isPast && $0.normalizedStatus != .canceled
                && $0.departure.code == flight.arrival.code && $0.arrival.code == flight.departure.code
        }
        if flight.departure.code != "???" && flight.arrival.code != "???" {
            VStack(alignment: .leading, spacing: 8) {
                Label("Meine Flüge auf dieser Strecke", systemImage: "arrow.left.arrow.right").font(.headline)
                Text("\(flight.departure.code) → \(flight.arrival.code)").font(.caption).foregroundStyle(.secondary)
                if same.isEmpty && reverse.isEmpty {
                    Text("Du bist diese Strecke noch nie geflogen.").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        InfoTile(title: "Flüge", value: "\(same.count)" + (reverse.isEmpty ? "" : " (+\(reverse.count) zurück)"), icon: "airplane")
                        InfoTile(title: "Distanz", value: Fmt.km((same + reverse).compactMap(\.computedDistanceKm).reduce(0, +)), icon: "ruler")
                        InfoTile(title: "Flugzeit", value: Fmt.duration((same + reverse).compactMap(\.durationMinutes).reduce(0, +)), icon: "clock")
                    }
                    if let last = (same + reverse).max(by: { $0.sortDate < $1.sortDate }) {
                        Text("Zuletzt: \(last.number) am \(Fmt.day(last.sortDate, last.departure.tz))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Updates log

struct UpdatesCard: View {
    let flight: Flight
    @State private var expanded = false

    var body: some View {
        if let updates = flight.updates, !updates.isEmpty {
            let list = Array(updates.reversed())
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Änderungen", systemImage: "list.bullet.rectangle").font(.headline)
                    Spacer()
                    Text("\(list.count)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(expanded ? list : Array(list.prefix(3))) { u in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(u.text).font(.subheadline)
                            Text(u.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                if list.count > 3 {
                    Button(expanded ? "Weniger anzeigen" : "Alle \(list.count) anzeigen") { expanded.toggle() }.font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Airline

enum Alliance {
    static let star: Set<String> = ["LX", "LH", "OS", "SN", "UA", "AC", "TK", "SQ", "NH", "TG", "TP", "SK", "LO", "A3", "OU", "ET", "SA", "MS", "AI", "CA", "ZH", "BR", "OZ", "NZ", "AV", "CM", "EN", "CL", "WK"]
    static let oneworld: Set<String> = ["BA", "AA", "QR", "CX", "JL", "QF", "IB", "AY", "MH", "RJ", "AT", "UL", "AS", "WY", "FJ"]
    static let skyteam: Set<String> = ["AF", "KL", "DL", "AZ", "KE", "MU", "AM", "AR", "UX", "CI", "GA", "KQ", "ME", "SV", "RO", "VN", "VS", "MF"]

    static func name(_ iata: String?) -> String? {
        guard let c = iata?.uppercased() else { return nil }
        if star.contains(c) { return "Star Alliance" }
        if oneworld.contains(c) { return "Oneworld" }
        if skyteam.contains(c) { return "SkyTeam" }
        return nil
    }
}

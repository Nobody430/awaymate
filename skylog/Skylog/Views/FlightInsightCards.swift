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
                timeRow(String(localized: "Gate verlassen"), t.outScheduled, t.outActual ?? t.outEstimated, actual: t.outActual != nil, tz: dtz)
                durationRow(String(localized: "Rollen"), span(t.outScheduled, t.offScheduled), span(t.outActual ?? t.outEstimated, t.offActual ?? t.offEstimated))
                timeRow(String(localized: "Start"), t.offScheduled, t.offActual ?? t.offEstimated, actual: t.offActual != nil, tz: dtz)
                Divider()
                Text("ANKUNFT").font(.caption2).foregroundStyle(.secondary)
                timeRow(String(localized: "Landung"), t.onScheduled, t.onActual ?? t.onEstimated, actual: t.onActual != nil, tz: atz)
                durationRow(String(localized: "Rollen"), span(t.onScheduled, t.inScheduled), span(t.onActual ?? t.onEstimated, t.inActual ?? t.inEstimated))
                timeRow(String(localized: "Am Gate"), t.inScheduled, t.inActual ?? t.inEstimated, actual: t.inActual != nil, tz: atz)
                Divider()
                durationRow(String(localized: "Flugzeit"), span(t.offScheduled, t.onScheduled), span(t.offActual ?? t.offEstimated, t.onActual ?? t.onEstimated))
                durationRow(String(localized: "Gesamt"), span(t.outScheduled, t.inScheduled), span(t.outActual ?? t.outEstimated, t.inActual ?? t.inEstimated))
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
                if current != nil { Text(actual ? String(localized: "tatsächlich") : String(localized: "erwartet")).font(.caption2).foregroundStyle(.secondary) }
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
                    Label(i.isCanceled ? String(localized: "Zubringer annulliert") : delay >= 15 ? String(localized: "Wird knapp: ca. \(delay) Min. Verspätung möglich") : String(localized: "Alles gut – genug Zeit für deinen Abflug"),
                          systemImage: i.isCanceled || delay >= 15 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(i.isCanceled ? .red : delay >= 15 ? .orange : .green)
                }
                row(title: String(localized: "Dein Flug · \(flight.departure.code) → \(flight.arrival.code)"),
                    detail: String(localized: "Abflug \(Fmt.time(flight.departure.best, flight.departure.tz))"),
                    delay: flight.departure.delayMinutes, icon: "circle")
                ForEach(Array(legs.prefix(4).enumerated()), id: \.offset) { _, leg in
                    row(title: "\(leg.fromCode) → \(leg.toCode ?? "?") · \(leg.number)",
                        detail: leg.landed ? String(localized: "Gelandet \(Fmt.time(leg.arrival, flight.departure.tz))")
                            : leg.departed ? String(localized: "In der Luft · Landung \(Fmt.time(leg.arrival, flight.departure.tz))")
                            : String(localized: "Geplant · Landung \(Fmt.time(leg.arrival, flight.departure.tz))"),
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
                Text(d >= 5 ? String(localized: "\(Fmt.duration(d)) später") : d <= -5 ? String(localized: "\(Fmt.duration(-d)) früher") : String(localized: "Pünktlich"))
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
                        InfoTile(title: String(localized: "Flüge"), value: "\(same.count)" + (reverse.isEmpty ? "" : String(localized: " (+\(reverse.count) zurück)")), icon: "airplane")
                        InfoTile(title: String(localized: "Distanz"), value: Fmt.km((same + reverse).compactMap(\.computedDistanceKm).reduce(0, +)), icon: "ruler")
                        InfoTile(title: String(localized: "Flugzeit"), value: Fmt.duration((same + reverse).compactMap(\.durationMinutes).reduce(0, +)), icon: "clock")
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
                    Button(expanded ? String(localized: "Weniger anzeigen") : String(localized: "Alle \(list.count) anzeigen")) { expanded.toggle() }.font(.caption)
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

// MARK: - Conditions at the departure airport

/// Weather at departure time (free) and the airport's current general delay (FlightAware, last 3 h before departure).
struct DepartureConditionsCard: View {
    let flight: Flight
    @State private var weather: Weather.Forecast?
    @State private var delay: FlightAware.AirportDelay?
    @State private var delayChecked = false

    private var dep: Date? { flight.departure.best }
    private var relevant: Bool {
        guard let dep, !flight.isPast, flight.departure.runway == nil, flight.normalizedStatus != .canceled else { return false }
        return dep.timeIntervalSinceNow < 3 * 86400 && dep.timeIntervalSinceNow > -3 * 3600
    }

    var body: some View {
        VStack(spacing: 0) {
            if relevant, weather != nil || delayChecked {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Lage in \(flight.departure.displayCity)", systemImage: "airplane.departure").font(.headline)
                    if let w = weather {
                        HStack(spacing: 10) {
                            Image(systemName: w.symbol).font(.title3).frame(width: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Wetter beim Abflug").font(.caption).foregroundStyle(.secondary)
                                Text("\(Int(w.temperature.rounded()))°" + (w.precipitationChance.map { String(localized: " · \($0)% Regen") } ?? "") + (w.isRough ? String(localized: " · kann Verspätungen bringen") : ""))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                    }
                    if delayChecked {
                        HStack(spacing: 10) {
                            Image(systemName: delay == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.title3).frame(width: 28)
                                .foregroundStyle(delay == nil ? .green : delay?.severe == true ? .red : .orange)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Betrieb am Flughafen").font(.caption).foregroundStyle(.secondary)
                                if let d = delay {
                                    Text(d.severe ? String(localized: "Grössere Verspätungen gemeldet") : String(localized: "Leichte Verspätungen gemeldet")).font(.subheadline.weight(.medium))
                                    if !d.reasons.isEmpty {
                                        Text(d.reasons.prefix(2).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Keine allgemeinen Verspätungen gemeldet").font(.subheadline.weight(.medium))
                                }
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .task(id: "\(flight.id)-\(Int((dep?.timeIntervalSince1970 ?? 0) / 900))") { await load() }
    }

    private func load() async {
        guard relevant, let dep else { return }
        if weather == nil, let lat = flight.departure.lat, let lon = flight.departure.lon {
            weather = try? await Weather.forecast(lat: lat, lon: lon, at: max(dep, Date()))
        }
        // paid query: only close to departure
        if FlightAware.hasKey, FlightProvider.current != .aerodatabox, dep.timeIntervalSinceNow < 3 * 3600,
           let code = flight.departure.icao ?? flight.departure.iata {
            delay = await FlightAware.airportDelay(code)
            delayChecked = true
        }
    }
}

// MARK: - Connection

/// Shows the connecting flight and how much time is left to change planes.
struct ConnectionCard: View {
    let flight: Flight
    @Environment(FlightStore.self) private var store

    var body: some View {
        if !flight.isPast, flight.normalizedStatus != .canceled, let next = store.connection(after: flight),
           let layover = FlightStore.layoverMinutes(flight, next) {
            let planned = flight.arrival.scheduled.flatMap { s in next.departure.scheduled.map { Int($0.timeIntervalSince(s) / 60) } }
            let color: Color = layover < 45 ? .red : layover < 75 ? .orange : .green
            VStack(alignment: .leading, spacing: 8) {
                Label("Anschlussflug", systemImage: "arrow.triangle.branch").font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(next.number) · \(next.departure.code) → \(next.arrival.code)").font(.subheadline.weight(.semibold))
                        Text(String(localized: "Abflug \(Fmt.time(next.departure.best, next.departure.tz))")
                             + (next.departure.gate.map { String(localized: " · Gate \($0)") } ?? "")
                             + (next.departure.terminal.map { String(localized: " · Terminal \($0)") } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(layover < 0 ? String(localized: "verpasst?") : Fmt.duration(layover)).font(.title3.bold()).foregroundStyle(color)
                        Text("zum Umsteigen").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let planned, layover <= planned - 10 {
                    Text(String(localized: "Geplant waren \(Fmt.duration(planned)). ") + (layover < 45 ? String(localized: "Das wird sehr knapp – früh bei der Crew melden.") : String(localized: "Zügig umsteigen.")))
                        .font(.caption).foregroundStyle(color)
                }
                if let a = flight.arrival.terminal, let b = next.departure.terminal, a != b {
                    Text("Terminalwechsel: Ankunft Terminal \(a), Abflug Terminal \(b).").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Boarding pass on the travel day

/// From 24 h before departure: one tap to the stored boarding pass / documents.
struct BoardingPassButton: View {
    let flight: Flight
    @State private var files: [URL] = []
    @State private var preview: URL?

    var body: some View {
        VStack(spacing: 0) {
            if let dep = flight.departure.best, !flight.isPast, flight.arrival.runway == nil,
               dep.timeIntervalSinceNow < 24 * 3600, let first = files.first {
                Button { preview = first } label: {
                    HStack {
                        Image(systemName: "qrcode").font(.title2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Bordkarte öffnen").font(.headline)
                            Text(files.count == 1 ? first.lastPathComponent : String(localized: "\(files.count) Dokumente")).font(.caption).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .quickLookPreview($preview, in: files)
        .onAppear { files = FlightDocs.list(flight.id).sorted { score($0) > score($1) } }
    }

    /// Boarding passes first
    private func score(_ u: URL) -> Int {
        let n = u.lastPathComponent.lowercased()
        return (n.contains("board") || n.contains("bord") || n.hasSuffix("pkpass") ? 2 : 0) + (n.hasSuffix("pdf") ? 1 : 0)
    }
}

/// Sheet for a file shared to Awaymate: attach it to one of the upcoming flights.
struct AttachDocumentView: View {
    let url: URL
    /// Called when the user wants the document read as a booking instead of filing it with a flight
    var onImport: (() -> Void)? = nil
    @Environment(FlightStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let onImport, url.pathExtension.lowercased() == "pdf" {
                    Section {
                        Button {
                            dismiss()
                            onImport()
                        } label: { Label("Flug oder Buchung daraus erkennen", systemImage: "sparkles") }
                    } footer: {
                        Text("Für Buchungsbestätigungen von Hotels, Mietwagen oder Flügen.")
                    }
                }
                Section {
                    ForEach(store.upcoming.prefix(12)) { f in
                        Button {
                            FlightDocs.add(url, to: f.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(f.number) · \(f.departure.code) → \(f.arrival.code)").font(.headline)
                                Text(Fmt.day(f.departure.best ?? f.sortDate, f.departure.tz)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if store.upcoming.isEmpty { Text("Keine anstehenden Flüge.").foregroundStyle(.secondary) }
                } header: {
                    Text("„\(url.lastPathComponent)“ ablegen bei")
                } footer: {
                    Text("Am Reisetag erscheint das Dokument zuoberst im Flug als „Bordkarte öffnen“.")
                }
            }
            .navigationTitle("Dokument ablegen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
        }
    }
}

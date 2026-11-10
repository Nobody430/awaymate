import SwiftUI

// MARK: - Year in review (shareable picture)

struct YearReviewCard: View {
    let stats: FlightStats
    let title: String
    @State private var image: UIImage?
    @State private var shared: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rückblick").font(.caption).foregroundStyle(.secondary)
            ReviewPoster(stats: stats, title: title)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Button {
                let renderer = ImageRenderer(content: ReviewPoster(stats: stats, title: title).frame(width: 360))
                renderer.scale = 3
                guard let img = renderer.uiImage, let data = img.pngData() else { return }
                let url = FileManager.default.temporaryDirectory.appending(path: "Skylog-Rueckblick.png")
                if (try? data.write(to: url)) != nil { shared = SharedFile(url: url) }
            } label: {
                Label("Als Bild teilen", systemImage: "square.and.arrow.up")
            }
            .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sheet(item: $shared) { file in
            ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
        }
    }
}

struct ReviewPoster: View {
    let stats: FlightStats
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Image(systemName: "airplane").font(.title2)
            }
            HStack(alignment: .top) {
                figure("\(stats.count)", "Flüge")
                figure(Fmt.km(stats.distance), "geflogen")
                figure(Fmt.duration(stats.minutes), "in der Luft")
            }
            HStack(alignment: .top) {
                figure("\(stats.countries.count)", "Länder")
                figure("\(stats.airports.count)", "Flughäfen")
                figure(String(format: "%.1f×", stats.distance / 40_075), "um die Erde")
            }
            if let l = stats.longest, let km = l.computedDistanceKm {
                Text("Längster Flug: \(l.departure.displayCity) → \(l.arrival.displayCity) · \(Fmt.km(km))").font(.footnote)
            }
            if let top = stats.top({ [$0.airlineName] }, limit: 1).first {
                Text("Meistens mit \(top.0) (\(top.1)×)").font(.footnote)
            }
            Text("Skylog").font(.caption2).opacity(0.7)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [Color(red: 0.10, green: 0.20, blue: 0.48), Color(red: 0.36, green: 0.62, blue: 1.0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    private func figure(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).opacity(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Punctuality per airline

struct PunctualityCard: View {
    let flights: [Flight]

    private struct Row: Identifiable {
        let id: String
        let count: Int
        let onTime: Int
        let avgDelay: Int
    }

    /// Only flights with a known scheduled and actual/last-known arrival
    private var rows: [Row] {
        var groups: [String: [Int]] = [:]
        for f in flights where f.isPast {
            guard let name = f.airlineName ?? f.airlineIata, let s = f.arrival.scheduled,
                  let a = f.arrival.runway ?? f.arrival.revised else { continue }
            groups[name, default: []].append(Int(a.timeIntervalSince(s) / 60))
        }
        return groups.map { name, delays in
            Row(id: name, count: delays.count, onTime: delays.filter { $0 < 15 }.count * 100 / delays.count,
                avgDelay: delays.reduce(0, +) / delays.count)
        }
        .sorted { $0.count == $1.count ? $0.id < $1.id : $0.count > $1.count }
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pünktlichkeit deiner Flüge").font(.caption).foregroundStyle(.secondary)
                ForEach(rows.prefix(6)) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.id).lineLimit(1)
                            Text("\(r.count) Flüge · im Schnitt \(r.avgDelay >= 0 ? "+" : "−")\(abs(r.avgDelay)) Min.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(r.onTime)%").font(.headline.monospacedDigit())
                            .foregroundStyle(r.onTime >= 80 ? .green : r.onTime >= 60 ? .orange : .red)
                    }
                }
                Text("Anteil der Flüge mit weniger als 15 Min. Verspätung bei der Ankunft. Nur Flüge mit bekannten Ist-Zeiten.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

// MARK: - Aircraft collection

struct AircraftCollectionCard: View {
    let flights: [Flight]
    @State private var expanded = false

    var body: some View {
        let types = Dictionary(grouping: flights.filter { !($0.aircraftModel ?? "").isEmpty }) { $0.aircraftModel! }
            .map { (model: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.model < $1.model : $0.count > $1.count }
        let regs = Dictionary(grouping: flights.filter { !($0.aircraftReg ?? "").isEmpty }) { $0.aircraftReg!.uppercased() }
            .map { (reg: $0.key, count: $0.value.count, model: $0.value.first?.aircraftModel) }
            .sorted { $0.count == $1.count ? $0.reg < $1.reg : $0.count > $1.count }
        if !types.isEmpty || !regs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Flugzeug-Sammlung").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(types.count) Typen · \(regs.count) Flugzeuge").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(types.prefix(expanded ? 40 : 4), id: \.model) { t in
                    HStack {
                        Label(t.model, systemImage: "airplane").lineLimit(1)
                        Spacer()
                        Text("\(t.count)×").foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                if expanded {
                    let repeats = regs.filter { $0.count > 1 }
                    if !repeats.isEmpty {
                        Text("Mehrmals im selben Flugzeug").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                        ForEach(repeats.prefix(15), id: \.reg) { r in
                            HStack {
                                Text(r.reg).font(.subheadline.monospaced())
                                if let m = r.model { Text(m).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                Spacer()
                                Text("\(r.count)×").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if types.count > 4 || regs.contains(where: { $0.count > 1 }) {
                    Button(expanded ? "Weniger anzeigen" : "Alle anzeigen") { expanded.toggle() }.font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

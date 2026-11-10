import SwiftUI
import Charts

struct FlightStats {
    let flights: [Flight]

    var count: Int { flights.count }
    var distance: Double { flights.compactMap(\.computedDistanceKm).reduce(0, +) }
    /// Flights without times are estimated from the distance (≈ 800 km/h + 30 min)
    var minutes: Int {
        flights.reduce(0) { sum, f in
            sum + (f.durationMinutes ?? f.computedDistanceKm.map { Int($0 / 800 * 60) + 30 } ?? 0)
        }
    }
    var airports: Set<String> { Set(flights.flatMap { [$0.departure.code, $0.arrival.code] }.filter { $0 != "???" }) }
    var countries: Set<String> { Set(flights.flatMap { [$0.departure.countryCode, $0.arrival.countryCode] }.compactMap { $0?.uppercased() }) }
    var longest: Flight? { flights.max { ($0.computedDistanceKm ?? 0) < ($1.computedDistanceKm ?? 0) } }

    func top(_ key: (Flight) -> [String?], limit: Int = 5) -> [(String, Int)] {
        var counts: [String: Int] = [:]
        for f in flights { for k in key(f).compactMap({ $0 }) where !k.isEmpty { counts[k, default: 0] += 1 } }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(limit).map { ($0.key, $0.value) }
    }

    var monthly: [(month: Date, count: Int)] {
        let cal = Calendar.current
        var counts: [Date: Int] = [:]
        for f in flights {
            if let m = cal.date(from: cal.dateComponents([.year, .month], from: f.sortDate)) { counts[m, default: 0] += 1 }
        }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
}

struct StatsView: View {
    @Environment(FlightStore.self) private var store
    @State private var year: Int? = nil
    @State private var includeUpcoming = false

    private var years: [Int] {
        Set(store.flights.map { Calendar.current.component(.year, from: $0.sortDate) }).sorted(by: >)
    }

    private var stats: FlightStats {
        var base = (includeUpcoming ? store.flights : store.past).filter { $0.normalizedStatus != .canceled }
        if let year { base = base.filter { Calendar.current.component(.year, from: $0.sortDate) == year } }
        return FlightStats(flights: base)
    }

    var body: some View {
        NavigationStack {
            let s = stats
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Picker("Jahr", selection: $year) {
                            Text("Gesamt").tag(Int?.none)
                            ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Toggle("inkl. geplante", isOn: $includeUpcoming).fixedSize()
                    }
                    .font(.subheadline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        InfoTile(title: String(localized: "Flüge"), value: "\(s.count)", icon: "airplane")
                        InfoTile(title: String(localized: "Distanz"), value: Fmt.km(s.distance), icon: "point.topleft.down.to.point.bottomright.curvepath")
                        InfoTile(title: String(localized: "In der Luft"), value: Fmt.duration(s.minutes), icon: "clock")
                        InfoTile(title: String(localized: "Um die Erde"), value: String(format: "%.2f×", s.distance / 40_075), icon: "globe.europe.africa")
                        InfoTile(title: String(localized: "Flughäfen"), value: "\(s.airports.count)", icon: "building.2")
                        InfoTile(title: String(localized: "Länder"), value: "\(s.countries.count)", icon: "flag")
                    }

                    if !s.flights.isEmpty {
                        PlacesCard(flights: s.flights)
                    }

                    if let l = s.longest, let km = l.computedDistanceKm {
                        card(String(localized: "Längster Flug")) {
                            HStack {
                                Text("\(l.departure.code) → \(l.arrival.code)").font(.title3.bold())
                                Spacer()
                                Text(Fmt.km(km)).foregroundStyle(.secondary)
                            }
                        }
                    }

                    if s.monthly.count > 1 {
                        card(String(localized: "Flüge pro Monat")) {
                            Chart(s.monthly, id: \.month) { item in
                                BarMark(x: .value("Monat", item.month, unit: .month), y: .value("Flüge", item.count))
                                    .foregroundStyle(Theme.accent)
                            }
                            .frame(height: 160)
                        }
                    }

                    if s.count > 0 {
                        YearReviewCard(stats: s, title: year.map { String(localized: "Mein Flugjahr \(String($0))") } ?? String(localized: "Meine Flüge"))
                        PunctualityCard(flights: s.flights)
                        AircraftCollectionCard(flights: s.flights)
                    }

                    topList(String(localized: "Airlines"), s.top { [$0.airlineName] })
                    topList(String(localized: "Flughäfen"), s.top { [$0.departure.iata ?? $0.departure.icao, $0.arrival.iata ?? $0.arrival.icao] })
                    topList(String(localized: "Strecken"), s.top { $0.departure.code == "???" || $0.arrival.code == "???" ? [] : ["\($0.departure.code) → \($0.arrival.code)"] })
                    topList(String(localized: "Flugzeugtypen"), s.top { [$0.aircraftModel] })

                    if s.count == 0 {
                        ContentUnavailableView("Noch keine Statistik", systemImage: "chart.bar",
                                               description: Text("Sobald du Flüge hinzugefügt hast, erscheinen hier deine Zahlen."))
                    }
                }
                .padding()
            }
            .navigationTitle("Statistik")
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func topList(_ title: String, _ items: [(String, Int)]) -> some View {
        if !items.isEmpty {
            let maxCount = Double(items.first?.1 ?? 1)
            card(title) {
                ForEach(items, id: \.0) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(item.0).lineLimit(1)
                            Spacer()
                            Text("\(item.1)").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.subheadline)
                        GeometryReader { geo in
                            Capsule().fill(Theme.accent.opacity(0.7))
                                .frame(width: geo.size.width * Double(item.1) / maxCount, height: 4)
                        }
                        .frame(height: 4)
                    }
                }
            }
        }
    }
}

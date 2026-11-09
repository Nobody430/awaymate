import SwiftUI
import MapKit

enum Countries {
    static func name(_ code: String) -> String {
        Locale(identifier: "de_CH").localizedString(forRegionCode: code) ?? code
    }

    static func flag(_ code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }

    struct Visit: Identifiable {
        var id: String { code }
        let code: String
        let flights: [Flight]
        var cities: [String] {
            var seen: [String] = []
            for f in flights {
                for e in [f.departure, f.arrival] where e.countryCode?.uppercased() == code {
                    let c = e.displayCity
                    if !seen.contains(c) { seen.append(c) }
                }
            }
            return seen
        }
        /// Arrivals into the country (= visits), departures alone count as well when no arrival is known
        var arrivals: Int { flights.filter { $0.arrival.countryCode?.uppercased() == code }.count }
    }

    /// All countries touched by the flights (departure or arrival), most visited first.
    static func visits(_ flights: [Flight]) -> [Visit] {
        var map: [String: [Flight]] = [:]
        for f in flights {
            for code in Set([f.departure.countryCode, f.arrival.countryCode].compactMap { $0?.uppercased() }) {
                map[code, default: []].append(f)
            }
        }
        return map.map { Visit(code: $0.key, flights: $0.value.sorted { $0.sortDate < $1.sortDate }) }
            .sorted { $0.arrivals == $1.arrivals ? name($0.code) < name($1.code) : $0.arrivals > $1.arrivals }
    }
}

/// "Where you've been": map of airports + tappable country list.
struct PlacesCard: View {
    let flights: [Flight]

    var body: some View {
        let visits = Countries.visits(flights)
        VStack(alignment: .leading, spacing: 10) {
            Text("Wo du warst").font(.caption).foregroundStyle(.secondary)
            PlacesMap(flights: flights).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 12))
            ForEach(visits) { v in
                NavigationLink {
                    CountryDetailView(visit: v)
                } label: {
                    HStack {
                        Text(Countries.flag(v.code)).font(.title2)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Countries.name(v.code)).foregroundStyle(.primary)
                            Text(v.cities.prefix(4).joined(separator: ", ") + (v.cities.count > 4 ? " …" : ""))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text("\(v.flights.count)×").font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
                if v.id != visits.last?.id { Divider() }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PlacesMap: View {
    let flights: [Flight]
    var highlightCountry: String? = nil

    private var airports: [AirportPoint] {
        var seen: [String: CLLocationCoordinate2D] = [:]
        for f in flights {
            for e in [f.departure, f.arrival] {
                guard let c = e.coordinate else { continue }
                if let h = highlightCountry, e.countryCode?.uppercased() != h { continue }
                seen[e.code] = c
            }
        }
        return seen.map { AirportPoint(id: $0.key, coordinate: $0.value) }
    }

    var body: some View {
        Map {
            ForEach(flights) { f in
                if let a = f.departure.coordinate, let b = f.arrival.coordinate {
                    MapPolyline(MKGeodesicPolyline(coordinates: [a, b], count: 2))
                        .stroke(Theme.accent.opacity(0.6), lineWidth: 1.5)
                }
            }
            ForEach(airports) { ap in
                Annotation(ap.id, coordinate: ap.coordinate) { AirportDot(color: .yellow) }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

struct CountryDetailView: View {
    let visit: Countries.Visit

    var body: some View {
        List {
            Section {
                PlacesMap(flights: visit.flights, highlightCountry: visit.code)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            }
            Section("Orte") {
                ForEach(visit.cities, id: \.self) { city in
                    let count = visit.flights.filter { $0.arrival.displayCity == city || $0.departure.displayCity == city }.count
                    LabeledContent(city, value: "\(count) Flüge")
                }
            }
            Section("Flüge (\(visit.flights.count))") {
                ForEach(visit.flights.reversed()) { f in
                    NavigationLink {
                        FlightDetailView(flightID: f.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(f.number) · \(f.departure.code) → \(f.arrival.code)").font(.subheadline.weight(.semibold))
                            Text("\(f.departure.displayCity) → \(f.arrival.displayCity) · \(Fmt.day(f.sortDate, f.departure.tz))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(Countries.flag(visit.code)) \(Countries.name(visit.code))")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI
import MapKit

// MARK: - Aircraft & seat

struct AircraftSeatCard: View {
    let flight: Flight
    @State private var details: AircraftDetails?
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        let model = details?.typeName ?? details?.model ?? flight.aircraftModel
        VStack(alignment: .leading, spacing: 10) {
            Label("Flugzeug & Sitz", systemImage: "airplane.circle").font(.headline)

            if let d = details {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    InfoTile(title: String(localized: "Typ"), value: d.typeName ?? d.model ?? flight.aircraftModel, icon: "airplane")
                    InfoTile(title: String(localized: "Alter"), value: d.ageText, icon: "calendar")
                    InfoTile(title: String(localized: "Sitze"), value: d.numSeats.map { "\($0)" }, icon: "carseat.right")
                    InfoTile(title: String(localized: "Triebwerke"), value: [d.numEngines.map { "\($0)×" }, d.engineType].compactMap { $0 }.joined(separator: " "), icon: "fanblades")
                }
                if let ff = d.firstFlightDate ?? d.deliveryDate {
                    Text("Erstflug/Auslieferung: \(String(ff.prefix(10))) · Seriennr. \(d.serial ?? "–")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if let reg = flight.aircraftReg {
                Button {
                    Task { await load(reg) }
                } label: {
                    HStack {
                        Label("Alter & Details von \(reg) laden", systemImage: "info.circle")
                        if loading { Spacer(); ProgressView() }
                    }
                }
                .buttonStyle(.bordered)
                Text("Kostet 1 Abfrage aus deinem Gratis-Kontingent.").font(.caption2).foregroundStyle(.secondary)
            } else {
                if !flight.isPast {
                    Text("Kennzeichen noch nicht bekannt – meist 1–2 Tage vor Abflug.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }

            if !flight.seat.isEmpty, let desc = SeatInfo.describe(seat: flight.seat, model: model) {
                Divider()
                Label("Sitz \(flight.seat.uppercased()): \(desc)", systemImage: "carseat.left").font(.subheadline)
            }
            if let sun = SunSide.analyse(flight) {
                Label(sun.summary, systemImage: "sun.max").font(.subheadline)
                // only when one side clearly gets more sun (not on night flights)
                if let side = SeatInfo.side(of: flight.seat, model: model),
                   max(sun.leftMinutes, sun.rightMinutes) > 2 * min(sun.leftMinutes, sun.rightMinutes),
                   max(sun.leftMinutes, sun.rightMinutes) >= 20 {
                    let sunny = sun.leftMinutes > sun.rightMinutes ? "links" : "rechts"
                    Text(side == sunny ? String(localized: "Dein Platz ist auf der Sonnenseite – Sonnenbrille einpacken 😎") : String(localized: "Dein Platz ist auf der Schattenseite 👍"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let url = URL(string: "https://www.google.com/search?q=" + "seat map \(flight.airlineName ?? "") \(model ?? "")".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
                Link(destination: url) { Label("Sitzplan dieses Flugzeugtyps suchen", systemImage: "rectangle.grid.3x2") }
                    .font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { if let reg = flight.aircraftReg { details = AircraftService.cached(reg) } }
    }

    private func load(_ reg: String) async {
        loading = true
        defer { loading = false }
        do { details = try await AircraftService.load(reg); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

// MARK: - Share with family & friends

struct FamilyCard: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Familie & Freunde informieren", systemImage: "person.2.wave.2").font(.headline)
            if !flight.isPast {
                Text("Diese Links funktionieren im Browser – niemand braucht dafür eine App:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(FamilyShare.trackingLinks(flight), id: \.0) { name, url in
                    HStack {
                        Link(destination: url) { Label("Live auf \(name)", systemImage: "dot.radiowaves.left.and.right") }
                        Spacer()
                        ShareLink(item: url, message: Text("Mein Flug \(flight.number) live:")) { Image(systemName: "square.and.arrow.up") }
                    }
                    .font(.subheadline)
                }
            }
            let message = FamilyShare.statusMessage(flight)
            HStack {
                if let wa = URL(string: "whatsapp://send?text=" + (message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) {
                    Link(destination: wa) {
                        Label("Status per WhatsApp", systemImage: "message.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                ShareLink(item: message) {
                    Label("Andere", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            Text(message).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Airport

struct AirportPOI: Identifiable {
    let id = UUID()
    let item: MKMapItem
    let group: String
}

struct AirportCard: View {
    let endpoint: FlightEndpoint
    let title: String
    @State private var pois: [AirportPOI] = []
    @State private var loaded = false
    @State private var expanded = false

    /// Official pages with live security waiting times / terminal maps.
    static let officialLinks: [String: [(String, String)]] = [
        "ZRH": [(String(localized: "Wartezeiten & Infos"), "https://www.flughafen-zuerich.ch/de/passagiere/abflug"), (String(localized: "Terminal-Pläne"), "https://www.flughafen-zuerich.ch/de/passagiere/flughafen-entdecken/flughafen-karte")],
        "GVA": [(String(localized: "Wartezeiten & Infos"), "https://www.gva.ch/de/Site/Passagiere"), (String(localized: "Terminal-Plan"), "https://www.gva.ch/de/Site/Passagiere/Am-Flughafen/Karten")],
        "BSL": [(String(localized: "Infos"), "https://www.euroairport.com/de/")],
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(title): \(endpoint.name ?? endpoint.code)", systemImage: "building.2").font(.headline).lineLimit(1)
                Spacer()
                Button(expanded ? String(localized: "Weniger") : String(localized: "Mehr")) { expanded.toggle() }.font(.caption)
            }
            HStack {
                if let c = endpoint.coordinate {
                    Button {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
                        item.name = endpoint.name ?? endpoint.code
                        item.openInMaps(launchOptions: [MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))])
                    } label: { Label("Innenplan (Karten)", systemImage: "map") }
                        .buttonStyle(.bordered)
                }
                ForEach(Self.officialLinks[endpoint.code] ?? [], id: \.0) { name, link in
                    if let u = URL(string: link) {
                        Link(destination: u) { Text(name) }.buttonStyle(.bordered)
                    }
                }
            }
            .font(.caption)

            if expanded {
                if !loaded { ProgressView().task { await loadPOIs() } }
                ForEach(["Lounges", "Essen & Kaffee", "Apotheke", "Geld & Wechsel", "Shopping"], id: \.self) { group in
                    let items = pois.filter { $0.group == group }
                    if !items.isEmpty {
                        Text(LocalizedStringKey(group)).font(.subheadline.weight(.semibold)).padding(.top, 4)
                        ForEach(items.prefix(6)) { p in
                            Button {
                                p.item.openInMaps()
                            } label: {
                                HStack {
                                    Text(p.item.name ?? "–").lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                                }
                                .font(.caption)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
                if loaded && pois.isEmpty {
                    Text("Keine Einträge in Apple Maps gefunden.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Daten aus Apple Maps – Lage im Terminal (landside/airside) bitte vor Ort prüfen.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func loadPOIs() async {
        guard let c = endpoint.coordinate else { loaded = true; return }
        let region = MKCoordinateRegion(center: c, latitudinalMeters: 2500, longitudinalMeters: 2500)
        let queries: [(String, String)] = [
            ("Lounges", "Lounge"), ("Essen & Kaffee", "Restaurant"), ("Essen & Kaffee", "Café"),
            ("Apotheke", "Apotheke"), ("Geld & Wechsel", "Geldautomat"), ("Geld & Wechsel", "Geldwechsel"), ("Shopping", "Duty Free"),
        ]
        var result: [AirportPOI] = []
        var seen = Set<String>()
        for (group, q) in queries {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            request.region = region
            if let response = try? await MKLocalSearch(request: request).start() {
                for item in response.mapItems where item.placemark.location.map({ $0.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 2500 }) ?? false {
                    let key = (item.name ?? "") + group
                    if seen.insert(key).inserted { result.append(AirportPOI(item: item, group: group)) }
                }
            }
        }
        pois = result
        loaded = true
    }
}

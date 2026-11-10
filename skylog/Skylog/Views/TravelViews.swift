import SwiftUI
import QuickLook
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Compensation

struct CompensationCard: View {
    let flight: Flight
    @State private var showClaim = false

    var body: some View {
        let r = Compensation.check(flight)
        if r.status != .notEligible || flight.normalizedStatus == .delayed {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: r.status == .eligible ? "eurosign.circle.fill" : "questionmark.circle")
                        .foregroundStyle(r.status == .eligible ? .green : .orange)
                    Text(r.headline).font(.headline)
                }
                ForEach(r.details, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                if r.status == .eligible || r.status == .possible {
                    Button { showClaim = true } label: {
                        Label("Antrag erstellen", systemImage: "doc.text").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .sheet(isPresented: $showClaim) { ClaimView(flight: flight, result: r) }
        }
    }
}

struct ClaimView: View {
    @Environment(\.dismiss) private var dismiss
    let flight: Flight
    let result: Compensation.Result
    @State private var claimant = Compensation.Claimant.saved
    @State private var english = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Deine Angaben") {
                    TextField("Name", text: $claimant.name)
                    TextField("Adresse", text: $claimant.address, axis: .vertical)
                    TextField("E-Mail", text: $claimant.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    TextField("IBAN", text: $claimant.iban).textInputAutocapitalization(.characters)
                    TextField("Buchungscode", text: $claimant.bookingCode).textInputAutocapitalization(.characters)
                    Stepper("Personen: \(claimant.passengers)", value: $claimant.passengers, in: 1...9)
                }
                Section {
                    Picker("Sprache", selection: $english) {
                        Text("Deutsch").tag(false)
                        Text("English").tag(true)
                    }
                    .pickerStyle(.segmented)
                    Text(Compensation.letter(flight, claimant, result: result, english: english))
                        .font(.footnote)
                        .textSelection(.enabled)
                } header: {
                    Text("Antrag – Gesamt \(result.amountEUR * claimant.passengers) €")
                } footer: {
                    Text("Am besten über das Online-Formular der Airline einreichen (Text hineinkopieren). Kein Rechtsrat – bei Ablehnung helfen Schlichtungsstellen oder Fluggastportale.")
                }
                Section {
                    ShareLink(item: Compensation.letter(flight, claimant, result: result, english: english)) {
                        Label("Teilen / per Mail senden", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = Compensation.letter(flight, claimant, result: result, english: english)
                    } label: { Label("Text kopieren", systemImage: "doc.on.doc") }
                    if let url = URL(string: "https://www.google.com/search?q=\((flight.airlineName ?? flight.number).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")+Entsch%C3%A4digung+Formular+EU261") {
                        Link(destination: url) { Label("Formular der Airline suchen", systemImage: "safari") }
                    }
                }
            }
            .navigationTitle("Entschädigung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .onChange(of: claimant.name) { _, _ in Compensation.Claimant.saved = claimant }
            .onDisappear { Compensation.Claimant.saved = claimant }
        }
    }
}

// MARK: - Public transport

struct TransitCard: View {
    let flight: Flight
    @AppStorage("homeStation") private var home = ""
    @State private var draft = ""
    @AppStorage(AirportBuffer.key) private var bufferSetting = 0
    private var buffer: Int { AirportBuffer.minutes(for: flight) }
    @State private var toAirport: [Transit.Connection] = []
    @State private var fromAirport: [Transit.Connection] = []
    @State private var loading = false
    @State private var error: String?

    @AppStorage("homeAirport") private var homeAirport = ""
    // Only for trips from/to home (abroad the hotel card shows the way)
    private var depStation: String? {
        homeAirport.isEmpty || homeAirport == flight.departure.code ? Transit.airportStations[flight.departure.code] : nil
    }
    private var arrStation: String? {
        homeAirport.isEmpty || homeAirport == flight.arrival.code ? Transit.airportStations[flight.arrival.code] : nil
    }

    var body: some View {
        let showDep = depStation != nil && !flight.isPast && flight.departure.best != nil
        let showArr = arrStation != nil && (flight.arrival.best.map { $0 > Date().addingTimeInterval(-6 * 3600) } ?? false)
        if (showDep || showArr) && flight.normalizedStatus != .canceled {
            VStack(alignment: .leading, spacing: 10) {
                Label("Zug & Bus", systemImage: "tram.fill").font(.headline)
                if home.isEmpty {
                    HStack {
                        TextField("Deine Heimat-Haltestelle (z.B. Frauenfeld)", text: $draft)
                            .textFieldStyle(.roundedBorder)
                            .submitLabel(.done)
                            .onSubmit { saveHome() }
                        Button("OK") { saveHome() }
                            .buttonStyle(.borderedProminent)
                            .disabled(draft.trimmingCharacters(in: .whitespaces).count < 2)
                    }
                } else {
                    if let depStation, !flight.isPast, let dep = flight.departure.best {
                        Text("Hin: \(home) → \(depStation), Ankunft spätestens \(Fmt.time(dep.addingTimeInterval(-Double(buffer) * 60), flight.departure.tz)) (\(buffer) Min vor Abflug)")
                            .font(.caption).foregroundStyle(.secondary)
                        connections(toAirport, tz: flight.departure.tz)
                    }
                    if let arrStation, let arr = flight.arrival.best, arr > Date().addingTimeInterval(-6 * 3600) {
                        Text("Zurück: \(arrStation) → \(home), ab \(Fmt.time(arr.addingTimeInterval(30 * 60), flight.arrival.tz))")
                            .font(.caption).foregroundStyle(.secondary)
                        connections(fromAirport, tz: flight.arrival.tz)
                    }
                    HStack {
                        Button("Haltestelle ändern") { draft = home; home = "" }.font(.caption)
                        Spacer()
                        Picker("Puffer", selection: $bufferSetting) {
                            ForEach(AirportBuffer.choices, id: \.self) { Text(AirportBuffer.label($0)).tag($0) }
                        }
                        .font(.caption).fixedSize()
                    }
                }
                if loading { ProgressView() }
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .task(id: "\(home)-\(buffer)-\(flight.departure.best?.timeIntervalSince1970 ?? 0)") { await load() }
        }
    }

    @ViewBuilder
    private func connections(_ list: [Transit.Connection], tz: TimeZone) -> some View {
        if list.isEmpty && !loading && error == nil {
            Text("Keine Verbindungen gefunden.").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(list) { c in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Fmt.time(c.departure, tz)) → \(Fmt.time(c.arrival, tz))")
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                    Text(c.products.joined(separator: " · ") + (c.transfers > 0 ? " · \(c.transfers)× umsteigen" : " · direkt"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let p = c.platform, !p.isEmpty { Text("Gl. \(p)").font(.caption.weight(.medium)) }
            }
        }
    }

    private func saveHome() {
        let v = draft.trimmingCharacters(in: .whitespaces)
        guard v.count >= 2 else { return }
        home = v
    }

    private func load() async {
        guard !home.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            if let depStation, !flight.isPast, let dep = flight.departure.best {
                toAirport = try await Transit.connections(from: home, to: depStation, at: dep.addingTimeInterval(-Double(buffer) * 60), arriveBy: true)
            }
            if let arrStation, let arr = flight.arrival.best, arr > Date().addingTimeInterval(-6 * 3600) {
                fromAirport = try await Transit.connections(from: arrStation, to: home, at: arr.addingTimeInterval(30 * 60), arriveBy: false)
            }
        } catch {
            self.error = "Verbindungen nicht verfügbar."
        }
    }
}

// MARK: - Documents

struct DocumentsCard: View {
    let flightID: UUID
    @State private var files: [URL] = []
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var preview: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Dokumente", systemImage: "doc.on.doc").font(.headline)
                Spacer()
                Menu {
                    Button { importing = true } label: { Label("Datei (PDF, Wallet-Pass, …)", systemImage: "doc") }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Foto / Screenshot", systemImage: "photo") }
                } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            if files.isEmpty {
                Text("Boardingpass, Buchungsbestätigung, Hotel … hier ablegen – auch offline verfügbar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(files, id: \.self) { url in
                Button { preview = url } label: {
                    Label(url.lastPathComponent, systemImage: url.pathExtension.lowercased() == "pdf" ? "doc.richtext" : "photo")
                        .lineLimit(1)
                }
                .contextMenu {
                    ShareLink(item: url)
                    Button("Löschen", role: .destructive) { FlightDocs.delete(url); reload() }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .quickLookPreview($preview, in: files)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image, .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { urls.forEach { FlightDocs.add($0, to: flightID) } }
            reload()
        }
        .onChange(of: photo) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) { FlightDocs.addImage(data, to: flightID) }
                photo = nil
                reload()
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() { files = FlightDocs.list(flightID) }
}

// MARK: - Trips

struct TripsView: View {
    @Environment(FlightStore.self) private var flights
    @State private var trips = TripStore.shared
    @State private var editing: Trip?
    @State private var toDelete: [UUID] = []

    var body: some View {
        NavigationStack {
            List {
                let suggestions = trips.suggestions(from: flights)
                if !suggestions.isEmpty {
                    Section("Vorschläge aus deinen Flügen") {
                        ForEach(suggestions) { t in
                            Button {
                                trips.upsert(t)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(t.name).font(.headline)
                                        Text("\(t.start.formatted(date: .abbreviated, time: .omitted)) – \(t.end.formatted(date: .abbreviated, time: .omitted))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle")
                                }
                            }
                        }
                    }
                }
                Section("Reisen") {
                    if trips.trips.isEmpty { Text("Noch keine Reisen.").foregroundStyle(.secondary) }
                    ForEach(trips.trips) { t in
                        NavigationLink { TripDetailView(tripID: t.id) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.name).font(.headline)
                                Text("\(t.start.formatted(date: .abbreviated, time: .omitted)) – \(t.end.formatted(date: .abbreviated, time: .omitted)) · \(trips.flights(for: t, in: flights).count) Flüge · Packliste \(t.packing.filter(\.done).count)/\(t.packing.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { toDelete = $0.map { trips.trips[$0].id } }
                }
            }
            .navigationTitle("Reisen")
            .toolbar {
                Button { editing = Trip(name: "", start: Date(), end: Date().addingTimeInterval(7 * 86400)) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
            }
            .sheet(item: $editing) { t in TripEditor(trip: t) }
            .confirmationDialog("Reise wirklich löschen?", isPresented: Binding(get: { !toDelete.isEmpty }, set: { if !$0 { toDelete = [] } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { trips.delete(toDelete); toDelete = [] }
            } message: {
                Text("Reiseplan und Packliste gehen verloren. Die Flüge bleiben erhalten.")
            }
        }
    }
}

struct TripEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var trip: Trip

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (z.B. Buenos Aires)", text: $trip.name)
                DatePicker("Von", selection: $trip.start, displayedComponents: .date)
                DatePicker("Bis", selection: $trip.end, in: trip.start..., displayedComponents: .date)
                TextField("Notizen (Hotel, Adresse, …)", text: $trip.notes, axis: .vertical)
            }
            .navigationTitle("Reise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { TripStore.shared.upsert(trip); dismiss() }.disabled(trip.name.isEmpty)
                }
            }
        }
    }
}

struct TripDetailView: View {
    @Environment(FlightStore.self) private var flights
    @State private var store = TripStore.shared
    let tripID: UUID
    @State private var newItem = ""
    @State private var editing = false
    @State private var planning = false
    @State private var bookingStore = BookingStore.shared
    @State private var packingBusy = false
    @State private var packingMessage: String?

    var body: some View {
        if let trip = store.trips.first(where: { $0.id == tripID }) {
            List {
                if !trip.notes.isEmpty { Section { Text(trip.notes) } }
                Section("Reiseplan") {
                    if trip.plan != nil {
                        NavigationLink { TripPlanView(tripID: trip.id) } label: {
                            Label("Tag-für-Tag-Plan ansehen", systemImage: "map")
                        }
                    }
                    Button { planning = true } label: {
                        Label(trip.plan == nil ? "Reise mit KI planen" : "Plan neu erstellen", systemImage: "sparkles")
                    }
                }
                Section("Flüge") {
                    let list = store.flights(for: trip, in: flights)
                    if list.isEmpty { Text("Keine Flüge in diesem Zeitraum.").foregroundStyle(.secondary) }
                    ForEach(list) { f in
                        NavigationLink { FlightDetailView(flightID: f.id) } label: { FlightCard(flight: f) }
                            .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                            .listRowBackground(Color.clear)
                    }
                }
                let stays = bookingStore.bookings(for: trip)
                if !stays.isEmpty {
                    Section("Unterkünfte & Buchungen") {
                        ForEach(stays) { BookingRow(booking: $0) }
                            .onDelete { idx in bookingStore.delete(idx.map { stays[$0].id }) }
                    }
                }
                Section("Packliste \(trip.packing.filter(\.done).count)/\(trip.packing.count)") {
                    ForEach(trip.packing) { item in
                        Button {
                            var t = trip
                            if let i = t.packing.firstIndex(where: { $0.id == item.id }) { t.packing[i].done.toggle() }
                            store.upsert(t)
                        } label: {
                            Label(item.name, systemImage: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? .secondary : .primary)
                        }
                    }
                    .onDelete { idx in
                        var t = trip
                        t.packing.remove(atOffsets: idx)
                        store.upsert(t)
                    }
                    HStack {
                        TextField("Hinzufügen …", text: $newItem).onSubmit(addItem)
                        Button("Hinzufügen", action: addItem).disabled(newItem.isEmpty)
                    }
                    Button("Alle zurücksetzen") {
                        var t = trip
                        for i in t.packing.indices { t.packing[i].done = false }
                        store.upsert(t)
                    }
                    Button {
                        Task { await personalPacking(trip) }
                    } label: {
                        HStack {
                            Label("Persönliche Packliste mit KI", systemImage: "sparkles")
                            if packingBusy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(packingBusy || !AIClient.hasKey)
                    if ObsidianVault.isConnected {
                        Button {
                            do {
                                let path = try ObsidianVault.write(name: "\(trip.name) – Packliste", markdown: PackingAI.markdown(trip: trip))
                                packingMessage = "In Obsidian gespeichert: \(path)"
                            } catch { packingMessage = error.localizedDescription }
                        } label: { Label("Packliste in Obsidian speichern", systemImage: "square.and.arrow.down") }
                    }
                    if let packingMessage { Text(packingMessage).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(trip.name)
            .navigationDestination(for: UUID.self) { FlightDetailView(flightID: $0) }
            .toolbar { Button("Bearbeiten") { editing = true } }
            .sheet(isPresented: $editing) { TripEditor(trip: trip) }
            .sheet(isPresented: $planning) { TripPlannerView(trip: trip) }
        }
    }

    private func personalPacking(_ trip: Trip) async {
        packingBusy = true
        defer { packingBusy = false }
        do {
            let items = try await PackingAI.generate(trip: trip, flights: store.flights(for: trip, in: flights),
                                                     bookings: bookingStore.bookings(for: trip))
            guard var t = store.trips.first(where: { $0.id == tripID }) else { return }
            let existing = Set(t.packing.map { $0.name.lowercased() })
            let new = items.filter { !existing.contains($0.name.lowercased()) }
            t.packing += new.map { PackItem(name: $0.name) }
            store.upsert(t)
            packingMessage = "\(new.count) persönliche Punkte hinzugefügt" + (PersonalProfile.text.isEmpty ? " (Tipp: Profil/Obsidian in den Einstellungen ergänzen)." : ".")
        } catch {
            packingMessage = error.localizedDescription
        }
    }

    private func addItem() {
        guard !newItem.isEmpty, var t = store.trips.first(where: { $0.id == tripID }) else { return }
        t.packing.append(PackItem(name: newItem))
        store.upsert(t)
        newItem = ""
    }
}

import SwiftUI

struct TripPlannerView: View {
    @Environment(FlightStore.self) private var flights
    @Environment(\.dismiss) private var dismiss
    let trip: Trip
    @State private var destination = ""
    @State private var interests: Set<String> = ["Kultur", "Essen"]
    @State private var pace = "ausgewogen"
    @State private var budget = "mittel"
    @State private var notes = ""
    @State private var working = false
    @State private var error: String?

    private let allInterests = ["Kultur", "Essen", "Natur", "Strand", "Nachtleben", "Shopping", "Abenteuer", "Entspannung", "Fotografie", "Sport"]

    var body: some View {
        NavigationStack {
            Form {
                if !AIClient.hasKey {
                    Section { Text("Für die Reiseplanung brauchst du einen KI-Key (Einstellungen → KI-Erkennung).").foregroundStyle(.orange) }
                }
                Section("Ziel") {
                    TextField("z.B. Buenos Aires & Salta", text: $destination)
                    LabeledContent("Zeitraum", value: "\(trip.start.formatted(date: .abbreviated, time: .omitted)) – \(trip.end.formatted(date: .abbreviated, time: .omitted))")
                }
                Section("Interessen") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(allInterests, id: \.self) { i in
                            Button {
                                if interests.contains(i) { interests.remove(i) } else { interests.insert(i) }
                            } label: {
                                Text(i).font(.subheadline)
                                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                                    .background(interests.contains(i) ? Theme.accent : Theme.card, in: Capsule())
                                    .foregroundStyle(interests.contains(i) ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section {
                    Picker("Tempo", selection: $pace) {
                        Text("Entspannt").tag("entspannt")
                        Text("Ausgewogen").tag("ausgewogen")
                        Text("Vollgepackt").tag("vollgepackt")
                    }
                    Picker("Budget", selection: $budget) {
                        Text("Günstig").tag("günstig")
                        Text("Mittel").tag("mittel")
                        Text("Gehoben").tag("gehoben")
                    }
                    TextField("Wünsche (z.B. „ein Tag Weinregion“, „kein Museum“)", text: $notes, axis: .vertical)
                }
                Section {
                    Button {
                        Task { await generate() }
                    } label: {
                        HStack { Label("Plan erstellen", systemImage: "sparkles"); if working { Spacer(); ProgressView() } }
                    }
                    .disabled(working || !AIClient.hasKey || destination.isEmpty)
                } footer: {
                    if working { Text("Die KI plant deine Reise … das dauert meist 30–60 Sekunden.") }
                    if let error { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Reise planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .onAppear { if destination.isEmpty { destination = trip.name } }
        }
    }

    private func generate() async {
        working = true
        error = nil
        defer { working = false }
        do {
            let plan = try await TripPlanner.plan(
                trip: trip, flights: TripStore.shared.flights(for: trip, in: flights),
                bookings: BookingStore.shared.bookings(for: trip),
                prefs: .init(destination: destination, interests: Array(interests).sorted(), pace: pace, budget: budget, notes: notes))
            var t = TripStore.shared.trips.first { $0.id == trip.id } ?? trip
            t.plan = plan
            TripStore.shared.upsert(t)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct TripPlanView: View {
    @State private var store = TripStore.shared
    @State private var replanning = false
    let tripID: UUID

    var body: some View {
        if let trip = store.trips.first(where: { $0.id == tripID }), let plan = trip.plan, !plan.isUsable {
            ContentUnavailableView {
                Label("Plan ist leer", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Die KI hat beim letzten Mal keinen Inhalt geliefert.")
            } actions: {
                Button("Neu erstellen") { replanning = true }.buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $replanning) { TripPlannerView(trip: trip) }
        } else if let trip = store.trips.first(where: { $0.id == tripID }), let plan = trip.plan {
            List {
                if !plan.summary.isEmpty { Section { Text(plan.summary) } }
                ForEach(plan.days, id: \.self) { day in
                    Section {
                        ForEach(day.items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: icon(item.kind)).frame(width: 24).foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(item.title).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(item.time).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(item.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("\(dayLabel(day.date)) · \(day.title)")
                    }
                }
                if !plan.tips.isEmpty {
                    Section("Tipps") {
                        ForEach(plan.tips, id: \.self) { Label($0, systemImage: "lightbulb").font(.subheadline) }
                    }
                }
                if !plan.budget.isEmpty { Section("Budget") { Text(plan.budget) } }
                if !plan.packing.isEmpty { Section {
                    ForEach(plan.packing, id: \.self) { Text($0) }
                    Button("Zur Packliste hinzufügen") {
                        var t = trip
                        let existing = Set(t.packing.map { $0.name.lowercased() })
                        t.packing += plan.packing.filter { !existing.contains($0.lowercased()) }.map { PackItem(name: $0) }
                        store.upsert(t)
                    }
                } header: { Text("Packliste-Vorschläge") } }
                Section {
                    Button { replanning = true } label: { Label("Plan neu erstellen", systemImage: "arrow.clockwise") }
                }
                Section {
                    Text("KI-Vorschlag – Öffnungszeiten, Preise und Sicherheitslage vor Ort prüfen.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reiseplan")
            .sheet(isPresented: $replanning) { TripPlannerView(trip: trip) }
            .toolbar {
                if ObsidianVault.isConnected {
                    Button {
                        _ = try? ObsidianVault.write(name: "\(trip.name) – Reiseplan", markdown: PackingAI.planMarkdown(trip: trip, plan: plan))
                    } label: { Image(systemName: "square.and.arrow.down") }
                }
                ShareLink(item: shareText(trip.name, plan)) { Image(systemName: "square.and.arrow.up") }
            }
        }
    }

    private func icon(_ kind: String) -> String {
        ["sight": "building.columns", "food": "fork.knife", "activity": "figure.hiking", "transport": "tram",
         "relax": "sun.max", "nightlife": "music.note", "shopping": "bag"][kind] ?? "mappin"
    }

    private func dayLabel(_ iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        return d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private func shareText(_ name: String, _ plan: TripPlan) -> String {
        var s = "🗺️ \(name)\n\n\(plan.summary)\n"
        for d in plan.days {
            s += "\n\(dayLabel(d.date)) – \(d.title)\n"
            for i in d.items { s += "• \(i.time) \(i.title)\n" }
        }
        return s
    }
}

struct BookingRow: View {
    let booking: TravelBooking
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: booking.kind.icon).frame(width: 30, height: 30).background(Theme.card, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(booking.name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private var detail: String {
        var parts = [booking.city]
        if booking.kind == .hotel || booking.kind == .car {
            parts.append("\(booking.start.formatted(.dateTime.day().month(.abbreviated))) – \(booking.end.formatted(.dateTime.day().month(.abbreviated)))")
            if booking.kind == .hotel && booking.nights > 0 { parts.append("\(booking.nights) Nächte") }
        } else {
            parts.append(booking.start.formatted(.dateTime.day().month(.abbreviated)))
        }
        if !booking.bookingReference.isEmpty { parts.append("Code \(booking.bookingReference)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

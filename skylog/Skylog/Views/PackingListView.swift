import SwiftUI

/// The packing list of a trip on its own page.
struct PackingListView: View {
    let tripID: UUID
    @Environment(FlightStore.self) private var flights
    @State private var store = TripStore.shared
    @State private var bookingStore = BookingStore.shared
    @State private var newItem = ""
    @State private var busy = false
    @State private var message: String?
    @State private var confirmReset = false

    private func change(_ edit: (inout Trip) -> Void) {
        guard var t = store.trips.first(where: { $0.id == tripID }) else { return }
        edit(&t)
        store.upsert(t)
    }

    var body: some View {
        if let trip = store.trips.first(where: { $0.id == tripID }) {
            let done = trip.packing.filter(\.done).count
            List {
                Section {
                    ForEach(trip.packing) { item in
                        Button {
                            change { t in
                                if let i = t.packing.firstIndex(where: { $0.id == item.id }) { t.packing[i].done.toggle() }
                            }
                        } label: {
                            Label(item.name, systemImage: item.done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.done ? .secondary : .primary)
                        }
                    }
                    .onDelete { idx in change { $0.packing.remove(atOffsets: idx) } }
                    HStack {
                        TextField("Hinzufügen …", text: $newItem).onSubmit(addItem)
                        Button("Hinzufügen", action: addItem).disabled(newItem.isEmpty)
                    }
                } header: {
                    Text("\(done)/\(trip.packing.count) eingepackt") + Text(verbatim: " · ") + Text("Reise: \(trip.days) Tage")
                } footer: {
                    Text("Zum Löschen eines Punkts nach links wischen.")
                }
                Section {
                    Button {
                        Task { await personalPacking(trip) }
                    } label: {
                        HStack {
                            Label("Persönliche Packliste mit KI", systemImage: "sparkles")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(busy || !AIClient.hasKey)
                    if ObsidianVault.isConnected {
                        Button {
                            do {
                                let path = try ObsidianVault.write(name: "\(trip.name) – Packliste", markdown: PackingAI.markdown(trip: trip))
                                message = String(localized: "In Obsidian gespeichert: \(path)")
                            } catch { message = error.localizedDescription }
                        } label: { Label("Packliste in Obsidian speichern", systemImage: "square.and.arrow.down") }
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                Section {
                    Button("Alle Häkchen entfernen") {
                        change { t in for i in t.packing.indices { t.packing[i].done = false } }
                    }
                    .disabled(done == 0)
                    Button("Standardliste wiederherstellen", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("„Standardliste wiederherstellen“ löscht alle eigenen und von der KI ergänzten Punkte.")
                }
            }
            .navigationTitle("Packliste")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Packliste auf die Standardliste zurücksetzen?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Zurücksetzen", role: .destructive) { change { $0.packing = Trip.defaultPacking() } }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }

    private func personalPacking(_ trip: Trip) async {
        busy = true
        defer { busy = false }
        do {
            let items = try await PackingAI.generate(trip: trip, flights: store.flights(for: trip, in: flights),
                                                     bookings: bookingStore.bookings(for: trip))
            var added = 0
            change { t in
                let existing = Set(t.packing.map { $0.name.lowercased() })
                let new = items.filter { !existing.contains($0.name.lowercased()) }
                t.packing += new.map { PackItem(name: $0.name) }
                added = new.count
            }
            message = String(localized: "\(added) persönliche Punkte hinzugefügt") + (PersonalProfile.text.isEmpty ? String(localized: " (Tipp: Profil/Obsidian in den Einstellungen ergänzen).") : ".")
        } catch {
            message = error.localizedDescription
        }
    }

    private func addItem() {
        guard !newItem.isEmpty else { return }
        change { $0.packing.append(PackItem(name: newItem)) }
        newItem = ""
    }
}

import SwiftUI

struct FlightListView: View {
    @Environment(FlightStore.self) private var store
    @State private var showAdd = false
    @State private var showImport = false
    @State private var sharedPDF: SharedFile?
    @State private var segment = 0

    var body: some View {
        NavigationStack {
            let items = segment == 0 ? store.upcoming : store.past
            List {
                Picker("Ansicht", selection: $segment) {
                    Text("Anstehend").tag(0)
                    Text("Vergangen").tag(1)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                if !store.pending.isEmpty {
                    Section {
                        ForEach(store.pending) { f in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(f.number) · \(f.departure.code) → \(f.arrival.code)").font(.headline)
                                Text("\(f.departure.displayCity) → \(f.arrival.displayCity) · \(Fmt.day(f.sortDate, f.departure.tz))")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button("Hinzufügen") { store.acceptPending(f.id) }
                                        .buttonStyle(.borderedProminent)
                                    Button("Ignorieren", role: .destructive) { store.ignorePending(f.id) }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Label("Neu in deinen Mails gefunden", systemImage: "envelope.badge")
                    }
                }

                if items.isEmpty {
                    ContentUnavailableView {
                        Label(segment == 0 ? "Keine anstehenden Flüge" : "Noch keine Flüge", systemImage: "airplane.departure")
                    } description: {
                        Text("Tippe auf + und gib deine Flugnummer ein.")
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }

                ForEach(items) { flight in
                    NavigationLink(value: flight.id) {
                        FlightCard(flight: flight)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .onDelete { offsets in
                    store.delete(offsets.map { items[$0].id })
                }

                if let error = store.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Flüge")
            .navigationDestination(for: UUID.self) { id in
                FlightDetailView(flightID: id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack {
                        if !items.isEmpty {
                            Button {
                                Task { if let url = await FlightPDF.make(items) { sharedPDF = SharedFile(url: url) } }
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                        if store.isRefreshing { ProgressView() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showAdd = true } label: { Label("Flug hinzufügen", systemImage: "airplane") }
                        Button { showImport = true } label: { Label("Aus E-Mails importieren", systemImage: "envelope") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .refreshable { await store.refreshActive(force: true) }
            .sheet(isPresented: $showAdd) { AddFlightView() }
            .sheet(isPresented: $showImport) { ImportView() }
            .sheet(item: $sharedPDF) { file in
                ShareSheet(items: [file.url]).presentationDetents([.medium, .large])
            }
        }
    }
}

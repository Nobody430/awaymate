import SwiftUI

struct AddFlightView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var number = ""
    @State private var date = Date()
    @State private var results: [Flight] = []
    @State private var loading = false
    @State private var error: String?

    private var canSearch: Bool {
        number.trimmingCharacters(in: .whitespaces).count >= 3 && !loading
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Flugnummer, z.B. LX1612", text: $number)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.weight(.semibold))
                        .onSubmit { Task { await search() } }
                    DatePicker("Abflugdatum", selection: $date, displayedComponents: .date)
                } footer: {
                    Text("Funktioniert auch für vergangene Flüge – so baust du deine Flughistorie auf.")
                }

                Section {
                    NavigationLink {
                        ManualFlightView(onSaved: { dismiss() })
                    } label: {
                        Label("Ohne Suche manuell eintragen", systemImage: "square.and.pencil")
                    }
                } footer: {
                    Text("Für alte Flüge oder wenn das API-Kontingent leer ist – braucht keine Abfrage.")
                }

                Section {
                    Button {
                        Task { await search() }
                    } label: {
                        HStack {
                            Text("Flug suchen")
                            Spacer()
                            if loading { ProgressView() }
                        }
                    }
                    .disabled(!canSearch)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if !results.isEmpty {
                    Section("Gefunden – zum Hinzufügen antippen") {
                        ForEach(results) { flight in
                            Button {
                                store.add(flight)
                                dismiss()
                            } label: {
                                FlightCard(flight: flight)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle("Flug hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }

    private func search() async {
        guard canSearch else { return }
        loading = true
        error = nil
        results = []
        defer { loading = false }
        do {
            results = try await FlightData.search(number: number, date: date)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

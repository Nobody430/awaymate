import SwiftUI
import UniformTypeIdentifiers

/// "About me" + Obsidian vault connection and note selection.
struct ProfileSettingsView: View {
    @AppStorage("aboutMe") private var aboutMe = ""
    @State private var connected = ObsidianVault.isConnected
    @State private var picking = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $aboutMe).frame(minHeight: 160).font(.footnote)
            } header: {
                Text("Über mich / KI-Erinnerungen")
            } footer: {
                Text("Hier z.B. die Erinnerungen aus ChatGPT (Einstellungen → Personalisierung → Erinnerungen verwalten) oder Claude einfügen: Gewohnheiten, Gesundheit, Hobbys, Geräte … Wird nur für Packliste und Reiseplanung an die KI geschickt.")
            }

            Section {
                if connected {
                    LabeledContent("Vault", value: ObsidianVault.vaultName)
                    NavigationLink { ObsidianNotePicker() } label: {
                        LabeledContent("Notizen für die KI", value: String(localized: "\(ObsidianVault.selectedNotes.count) ausgewählt"))
                    }
                    Button("Vault trennen", role: .destructive) {
                        ObsidianVault.disconnect()
                        connected = false
                    }
                } else {
                    Button { picking = true } label: { Label("Obsidian-Vault verbinden", systemImage: "folder.badge.plus") }
                }
                if let error { Text(error).foregroundStyle(.orange).font(.caption) }
            } header: {
                Text("Obsidian")
            } footer: {
                Text("Wähle den Ordner deines Vaults (in der Dateien-App unter iCloud Drive → Obsidian oder Auf meinem iPhone → Obsidian). Nur die ausgewählten Notizen werden genutzt. Packlisten und Reisepläne kannst du zurück in den Vault speichern (Ordner „Skylog“).")
            }
        }
        .navigationTitle("Persönliches Profil")
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                do { try ObsidianVault.connect(url); connected = true; error = nil }
                catch { self.error = error.localizedDescription }
            case .failure(let e):
                error = e.localizedDescription
            }
        }
    }
}

struct ObsidianNotePicker: View {
    @State private var notes: [String] = []
    @State private var selected = Set(ObsidianVault.selectedNotes)
    @State private var search = ""
    @State private var error: String?

    private var filtered: [String] {
        search.isEmpty ? notes : notes.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.orange) }
            if !selected.isEmpty {
                Section("Ausgewählt (\(selected.count))") {
                    ForEach(selected.sorted(), id: \.self) { path in
                        Button { selected.remove(path) } label: {
                            Label(path, systemImage: "checkmark.circle.fill").foregroundStyle(.primary)
                        }
                    }
                }
            }
            Section("Alle Notizen") {
                ForEach(filtered.prefix(300), id: \.self) { path in
                    Button {
                        if selected.contains(path) { selected.remove(path) } else { selected.insert(path) }
                    } label: {
                        Label(path, systemImage: selected.contains(path) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Notiz suchen (z.B. Über mich)")
        .navigationTitle("Notizen auswählen")
        .task {
            do { notes = try ObsidianVault.allNotes() } catch { self.error = error.localizedDescription }
        }
        .onChange(of: selected) { _, s in ObsidianVault.selectedNotes = Array(s).sorted() }
    }
}

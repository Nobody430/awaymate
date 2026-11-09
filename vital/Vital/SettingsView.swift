import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(TrainingStore.self) private var training
    @Environment(WeightStore.self) private var weight
    @AppStorage("lockEnabled") private var lockEnabled = false
    @Environment(PrepStore.self) private var prep
    @AppStorage("healthSync") private var healthSync = true
    @AppStorage("anthropicKey") private var anthropicKey = ""
    @AppStorage("openaiKey") private var openaiKey = ""
    @AppStorage("openaiModel") private var openaiModel = "gpt-5-mini"
    @AppStorage("aiProvider") private var aiProvider = AIClient.Provider.claudeBest.rawValue
    @State private var message: String?
    @State private var importKind: ImportKind?
    @State private var showImporter = false

    enum ImportKind { case training, weight, prep }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Mit Face ID sperren", isOn: $lockEnabled)
                } header: {
                    Text("Privatsphäre")
                } footer: {
                    Text("Alle Daten bleiben auf deinem iPhone (verschlüsselt gespeichert).")
                }

                Section {
                    Toggle("Mit Apple Health verbinden", isOn: $healthSync)
                    Button("Health-Zugriff erlauben") {
                        Task {
                            do {
                                try await Health.shared.requestAuthorization()
                                message = "Zugriff angefragt."
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Gewicht wird gelesen und geschrieben, Krafttrainings werden als Workout gespeichert.")
                }

                Section("Training") {
                    NavigationLink("Übungen verwalten") { ExerciseLibraryView() }
                    NavigationLink("Pläne verwalten") { TemplatesView() }
                    LabeledContent("Trainings gespeichert", value: "\(training.workouts.count)")
                }

                Section {
                    Picker("KI", selection: $aiProvider) {
                        ForEach(AIClient.Provider.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if aiProvider == AIClient.Provider.openai.rawValue {
                        SecureField("OpenAI-API-Key (sk-…)", text: $openaiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Modell", text: $openaiModel)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        NavigationLink { KeyGuideView(guide: .openai) } label: {
                            Label("So bekommst du den OpenAI-Key", systemImage: "questionmark.circle")
                        }
                    } else {
                        SecureField("Claude-API-Key (sk-ant-…)", text: $anthropicKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        NavigationLink { KeyGuideView(guide: .claude) } label: {
                            Label("So bekommst du den Key", systemImage: "questionmark.circle")
                        }
                    }
                } header: {
                    Text("KI-Coach")
                } footer: {
                    Text("Für KI-Trainingspläne und Übersetzungen. Abrechnung nach Nutzung direkt bei Anthropic.")
                }

                Section {
                    Button { importKind = .training; showImporter = true } label: { Label("Trainings importieren (CSV)", systemImage: "dumbbell") }
                    Button { importKind = .weight; showImporter = true } label: { Label("Gewicht importieren (CSV)", systemImage: "scalemass") }
                    Button { importKind = .prep; showImporter = true } label: { Label("PrEP-Einnahmen importieren", systemImage: "pills") }
                    LabeledContent("Gewichtseinträge", value: "\(weight.entries.count)")
                } header: {
                    Text("Daten aus anderen Apps")
                } footer: {
                    Text("Exportiere deine Daten in der alten App als CSV (z.B. Alpha Progression, Strong, Hevy, Happy Scale) und wähle die Datei hier aus. Spalten werden automatisch erkannt.")
                }
            }
            .navigationTitle("Einstellungen")
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
                guard case .success(let url) = result, let kind = importKind else { return }
                do {
                    let n: Int
                    switch kind {
                    case .training: n = try DataImport.importWorkouts(from: url, into: training)
                    case .weight: n = try DataImport.importWeights(from: url, into: weight)
                    case .prep: n = try DataImport.importDoses(from: url, into: prep)
                    }
                    message = "\(n) Einträge importiert."
                } catch {
                    message = error.localizedDescription
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

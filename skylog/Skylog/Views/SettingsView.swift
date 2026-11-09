import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(FlightStore.self) private var store
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("provider") private var provider = FlightProvider.aerodatabox.rawValue
    @AppStorage("flightawareKey") private var flightawareKey = ""
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("notifyChanges") private var notifyChanges = true
    @AppStorage("reminders") private var reminders = true
    @AppStorage("liveActivities") private var liveActivities = true
    @AppStorage("outlookClientID") private var outlookClientID = ""
    @AppStorage("anthropicKey") private var anthropicKey = ""
    @AppStorage("openaiKey") private var openaiKey = ""
    @AppStorage("openaiModel") private var openaiModel = "gpt-5-mini"
    @AppStorage("aiProvider") private var aiProvider = AIClient.Provider.claudeFast.rawValue
    @AppStorage("passengerName") private var passengerName = ""
    @AppStorage("mailWatch") private var mailWatch = true
    @AppStorage("mailAutoAdd") private var mailAutoAdd = false

    @State private var importing = false
    @State private var confirmWipe = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Datenquelle", selection: $provider) {
                        ForEach(FlightProvider.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if provider == FlightProvider.flightaware.rawValue {
                        SecureField("FlightAware API-Key", text: $flightawareKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Link(destination: URL(string: "https://www.flightaware.com/aeroapi/portal/")!) {
                            Label("Key holen (AeroAPI → Personal)", systemImage: "key")
                        }
                    } else {
                        SecureField("RapidAPI-Key einfügen", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Link(destination: URL(string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox")!) {
                            Label("Gratis-Key holen (AeroDataBox)", systemImage: "key")
                        }
                    }
                    NavigationLink {
                        KeyGuideView(guide: provider == FlightProvider.flightaware.rawValue ? .flightaware : .aerodatabox)
                    } label: {
                        Label("So bekommst du den Key", systemImage: "questionmark.circle")
                    }
                    LabeledContent("Abfragen diesen Monat", value: "\(Usage.thisMonth)")
                } header: {
                    Text("Flugdaten")
                } footer: {
                    if provider == FlightProvider.flightaware.rawValue {
                        Text("FlightAware AeroAPI, Stufe „Personal“: monatliches Gratis-Guthaben, danach Abrechnung pro Abfrage (Preis je nach Abfrage). Sehr zuverlässige Zeiten, Gates und Gepäckbänder. Jeder Flughafen wird nur einmal abgefragt und dann gespeichert. Tipp: In FlightAware ein monatliches Ausgabenlimit setzen.")
                    } else {
                        Text("AeroDataBox über RapidAPI: Plan „Basic“ ist gratis (begrenzte Abfragen), grössere Pläne kosten monatlich. Live-Positionen kommen gratis von OpenSky. Flugzeug-Details (Alter) nutzen immer AeroDataBox, falls ein Key hinterlegt ist.")
                    }
                }

                Section {
                    TextField("Dein Name wie auf dem Ticket (z.B. Raffael Muster)", text: $passengerName)
                        .textContentType(.name)
                } header: {
                    Text("Reisender")
                } footer: {
                    Text("Beim Mail-Import werden nur Buchungen übernommen, auf denen dieser Name steht.")
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
                    Text("KI-Erkennung")
                } footer: {
                    if aiProvider == AIClient.Provider.openai.rawValue {
                        Text("Wichtig: Ein ChatGPT-Abo (Plus/Pro) gilt nicht für die API. Es braucht API-Guthaben auf platform.openai.com → Billing.")
                    } else {
                        Text("Haiku kostet für einen kompletten Postfach-Import meist nur Rappen. Opus ist genauer, aber etwa 40× teurer.")
                    }
                }

                Section {
                    Toggle("Neue Mails automatisch prüfen", isOn: $mailWatch)
                    if mailWatch {
                        Toggle("Gefundene Flüge ohne Nachfrage hinzufügen", isOn: $mailAutoAdd)
                    }
                    TextField("Outlook-Client-ID (Azure)", text: $outlookClientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                    NavigationLink {
                        KeyGuideView(guide: .outlook)
                    } label: {
                        Label("So richtest du Outlook ein", systemImage: "questionmark.circle")
                    }
                } header: {
                    Text("E-Mail-Import")
                } footer: {
                    Text("Einmalig: App registrieren → Kontotyp „Beliebiges Verzeichnis + persönliche Microsoft-Konten“ → Plattform „iOS/macOS“ mit Bundle-ID com.nobody430.skylog → Anwendungs-ID (Client-ID) hier einfügen. Details im README.")
                }

                Section {
                    Toggle("Automatisch aktualisieren", isOn: $autoRefresh)
                    Toggle("Mitteilung bei Gate-/Zeitänderung", isOn: $notifyChanges)
                    Toggle("Live-Aktivität automatisch (4 h vor Abflug)", isOn: $liveActivities)
                    Toggle("Erinnerungen (Check-in, Boarding, Landung)", isOn: $reminders)
                        .onChange(of: reminders) { _, _ in
                            store.flights.forEach { Notifier.scheduleReminders(for: $0) }
                        }
                } header: {
                    Text("Automatik")
                } footer: {
                    Text("Sparsam: ab 24 h vor Abflug alle 4 h, ab 4 h vor Abflug bis zur Landung alle 20 Min., nach der Landung einmal (Gepäckband). Ca. 20 Abfragen pro Flug. Im Hintergrund entscheidet iOS, wie oft die App laufen darf.")
                }

                Section("Daten") {
                    if let url = store.exportURL() {
                        ShareLink(item: url) { Label("Flüge exportieren (JSON)", systemImage: "square.and.arrow.up") }
                    }
                    Button { importing = true } label: {
                        Label("Flüge importieren", systemImage: "square.and.arrow.down")
                    }
                    let dupes = store.duplicates.count
                    if dupes > 0 {
                        Button(role: .destructive) {
                            let n = store.removeDuplicates()
                            message = "\(n) doppelte Flüge entfernt."
                        } label: {
                            Label("Duplikate entfernen (\(dupes))", systemImage: "square.on.square.dashed")
                        }
                    }
                    let junk = store.incomplete.count
                    if junk > 0 {
                        Button(role: .destructive) {
                            let n = store.removeIncomplete()
                            message = "\(n) unvollständige Flüge entfernt."
                        } label: {
                            Label("Aufräumen: \(junk) unvollständige Flüge löschen", systemImage: "wand.and.stars")
                        }
                    }
                    Button(role: .destructive) { confirmWipe = true } label: {
                        Label("Alle Flüge löschen", systemImage: "trash")
                    }
                }

                Section {
                    LabeledContent("Gespeicherte Flüge", value: "\(store.flights.count)")
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("Skylog – eigener Flug-Tracker. Daten: AeroDataBox, OpenSky Network.")
                }
            }
            .navigationTitle("Einstellungen")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        let n = try store.importFlights(from: url)
                        message = "\(n) Flüge importiert."
                    } catch {
                        message = "Import fehlgeschlagen: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    message = error.localizedDescription
                }
            }
            .confirmationDialog("Wirklich alle Flüge löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Alle löschen", role: .destructive) { store.deleteAll() }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

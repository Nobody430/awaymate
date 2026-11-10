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
    @AppStorage("pushServerURL") private var pushServerURL = ""
    @AppStorage("travelMode") private var travelMode = true
    @AppStorage("pushServerToken") private var pushServerToken = ""
    @State private var pushStatus: String?
    @AppStorage("mailAutoAdd") private var mailAutoAdd = false
    @AppStorage("homeStation") private var homeStation = ""
    @AppStorage("homeAirport") private var homeAirport = ""
    @AppStorage(AirportBuffer.key) private var airportBuffer = 0

    @State private var importing = false
    @State private var confirmWipe = false
    @State private var message: String?
    @State private var exportFile: URL?
    @State private var confirmDupes = false
    @State private var confirmJunk = false
    @State private var dupes = 0
    @State private var junk = 0

    private func recount() {
        dupes = store.duplicates.count
        junk = store.incomplete.count
        exportFile = nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Datenquelle", selection: $provider) {
                        ForEach(FlightProvider.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    if provider != FlightProvider.aerodatabox.rawValue {
                        SecureField("FlightAware API-Key", text: $flightawareKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        NavigationLink { KeyGuideView(guide: .flightaware) } label: {
                            Label("So bekommst du den FlightAware-Key", systemImage: "questionmark.circle")
                        }
                    }
                    if provider != FlightProvider.flightaware.rawValue {
                        SecureField("RapidAPI-Key (AeroDataBox)", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        NavigationLink { KeyGuideView(guide: .aerodatabox) } label: {
                            Label("So bekommst du den AeroDataBox-Key", systemImage: "questionmark.circle")
                        }
                    }
                    LabeledContent("Abfragen diesen Monat", value: "\(Usage.thisMonth)")
                } header: {
                    Text("Flugdaten")
                } footer: {
                    if provider == FlightProvider.both.rawValue {
                        Text("Kombiniert: Kurzfristige Flüge (±2 Tage) und Live-Status über FlightAware, Flüge weiter in der Zukunft über AeroDataBox. Fällt eine Quelle aus, springt die andere ein. Kurz vor Abflug bzw. nach der Landung ergänzt AeroDataBox fehlendes Gate, Terminal, Check-in-Schalter oder Gepäckband.")
                    } else if provider == FlightProvider.flightaware.rawValue {
                        Text("FlightAware AeroAPI, Stufe „Personal“: monatliches Gratis-Guthaben, danach Abrechnung pro Abfrage (Preis je nach Abfrage). Sehr zuverlässige Zeiten, Gates und Gepäckbänder. Jeder Flughafen wird nur einmal abgefragt und dann gespeichert. Tipp: In FlightAware ein monatliches Ausgabenlimit setzen.")
                    } else {
                        Text("AeroDataBox über RapidAPI: Plan „Basic“ ist gratis (begrenzte Abfragen), grössere Pläne kosten monatlich. Live-Positionen kommen gratis von OpenSky. Flugzeug-Details (Alter) nutzen immer AeroDataBox, falls ein Key hinterlegt ist.")
                    }
                }

                Section {
                    TextField("Dein Name wie auf dem Ticket (z.B. Raffael Muster)", text: $passengerName)
                        .textContentType(.name)
                    NavigationLink { ProfileSettingsView() } label: {
                        Label("Persönliches Profil & Obsidian", systemImage: "person.text.rectangle")
                    }
                } header: {
                    Text("Reisender")
                } footer: {
                    Text("Beim Mail-Import werden nur Buchungen übernommen, auf denen dieser Name steht.")
                }

                Section {
                    TextField("Heimat-Bahnhof / Haltestelle (z.B. Frauenfeld)", text: $homeStation)
                    HStack {
                        TextField("Heimat-Flughafen (Code, z.B. ZRH)", text: $homeAirport)
                            .textInputAutocapitalization(.characters).autocorrectionDisabled()
                            .onChange(of: homeAirport) { _, v in
                                let c = String(v.uppercased().filter(\.isLetter).prefix(3))
                                if c != v { homeAirport = c }
                            }
                        if homeAirport.count == 3, let info = AirportLookup.bundledInfo(homeAirport) {
                            Text(info.city ?? info.name ?? "").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Am Flughafen sein", selection: $airportBuffer) {
                        ForEach(AirportBuffer.choices, id: \.self) { Text(AirportBuffer.label($0)).tag($0) }
                    }
                } header: {
                    Text("Zuhause")
                } footer: {
                    Text("Für Zugverbindungen zum/vom Flughafen und als Vorschlag beim manuellen Eintragen. Unterwegs erkennt Skylog gebuchte Hotels und zeigt den Weg Flughafen ↔ Hotel.")
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
                    if mailWatch, let e = MailWatcher.lastError {
                        Text("Letzte Mail-Prüfung fehlgeschlagen – \(e)").font(.caption).foregroundStyle(.orange)
                    }
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
                    TextField("Server-Adresse (z.B. skylog-push-n430.fly.dev)", text: $pushServerURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Server-Token", text: $pushServerToken)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Verbindung testen") {
                        Task { pushStatus = await PushClient.test() }
                    }
                    .disabled(pushServerURL.isEmpty || pushServerToken.isEmpty)
                    if let s = pushStatus ?? PushClient.lastStatus { Text(s).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    Text("Echtzeit-Pushs (eigener Server)")
                } footer: {
                    Text("Mit deinem Skylog-Server kommen Gate-Wechsel, Verspätungen, Boarding (ca.), Gate verlassen, Start, Landung und Gepäckband sofort – und die Live-Aktivität aktualisiert sich in Echtzeit.")
                }

                Section {
                    Toggle("Automatisch aktualisieren", isOn: $autoRefresh)
                    Toggle("Reisemodus (im Hintergrund aktualisieren)", isOn: $travelMode)
                        .onChange(of: travelMode) { _, _ in TravelMode.shared.evaluate(store) }
                    Toggle("Mitteilung bei Gate-/Zeitänderung", isOn: $notifyChanges)
                    Toggle("Live-Aktivität automatisch (4 h vor Abflug)", isOn: $liveActivities)
                    Toggle("Erinnerungen (Check-in, Boarding, Landung)", isOn: $reminders)
                        .onChange(of: reminders) { _, _ in
                            store.flights.forEach { Notifier.scheduleReminders(for: $0) }
                        }
                } header: {
                    Text("Automatik")
                } footer: {
                    Text("24–4 h vor Abflug alle 2 h, danach alle 15 Min., ab 75 Min. vor Abflug bis zum Start alle 5 Min. (auch über die geplante Zeit hinaus, damit Verspätungen sofort auftauchen). In der Luft alle 15 Min., kurz vor Landung alle 5 Min., danach bis zum Gepäckband. Ca. 40 Abfragen pro Flug. Mit Reisemodus läuft das auch im Hintergrund.")
                }

                Section("Daten") {
                    // the file is written on tap, not on every redraw of the settings
                    if let exportFile {
                        ShareLink(item: exportFile) { Label("Export teilen …", systemImage: "square.and.arrow.up") }
                    } else {
                        Button { exportFile = store.exportURL() } label: {
                            Label("Flüge exportieren (JSON)", systemImage: "square.and.arrow.up")
                        }
                    }
                    Button { importing = true } label: {
                        Label("Flüge importieren", systemImage: "square.and.arrow.down")
                    }
                    if dupes > 0 {
                        Button(role: .destructive) { confirmDupes = true } label: {
                            Label("Duplikate entfernen (\(dupes))", systemImage: "square.on.square.dashed")
                        }
                    }
                    if junk > 0 {
                        Button(role: .destructive) { confirmJunk = true } label: {
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
                    Text("Skylog – eigener Flug-Tracker. Daten: FlightAware, AeroDataBox, OpenSky Network, adsb.lol, airplanes.live.")
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
                Button("Alle löschen", role: .destructive) { store.deleteAll(); recount() }
            }
            .confirmationDialog("\(dupes) doppelte Flüge entfernen?", isPresented: $confirmDupes, titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    message = "\(store.removeDuplicates()) doppelte Flüge entfernt."
                    recount()
                }
            } message: {
                Text("Von jedem doppelten Flug bleibt der Eintrag mit den besten Daten.")
            }
            .confirmationDialog("\(junk) unvollständige Flüge löschen?", isPresented: $confirmJunk, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    message = "\(store.removeIncomplete()) unvollständige Flüge entfernt."
                    recount()
                }
            } message: {
                Text(store.incomplete.prefix(8).map { "\($0.number) \($0.departure.code)→\($0.arrival.code) \($0.date)" }.joined(separator: "\n"))
            }
            .onAppear { recount() }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

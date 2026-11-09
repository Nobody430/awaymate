import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportView: View {
    var initialFile: URL? = nil

    @Environment(FlightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("outlookClientID") private var clientID = ""

    @State private var candidates: [FlightCandidate] = []
    @State private var selected: Set<String> = []
    @State private var status: String?
    @State private var busy = false
    @State private var pasteText = ""
    @State private var picking = false
    @State private var connected = OutlookAuth.shared.isConnected
    @State private var pendingMails: [OutlookMail.MailItem] = []
    @State private var replaceExisting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if clientID.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Zuerst unter Einstellungen → E-Mail-Import die Outlook-Client-ID eintragen.")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await scanOutlook() }
                        } label: {
                            Label(connected ? "Postfach nach Flügen durchsuchen" : "Mit Outlook anmelden & durchsuchen",
                                  systemImage: "envelope.badge")
                        }
                        .disabled(busy)
                        if connected {
                            Button("Outlook abmelden", role: .destructive) {
                                OutlookAuth.shared.signOut()
                                connected = false
                            }
                        }
                    }
                } header: {
                    Text("Outlook / Hotmail / MSN")
                } footer: {
                    Text(AIClient.hasKey
                         ? "Mit KI-Erkennung: Claude liest die gefundenen Mails und übernimmt nur echte Buchungen (inkl. Umbuchungen und Stornos)."
                         : "Tipp: Mit einem Claude-Key (Einstellungen → KI-Erkennung) werden Flüge viel genauer erkannt.")
                }

                if !pendingMails.isEmpty {
                    Section {
                        Text("\(pendingMails.count) Reise-Mails gefunden.")
                        Toggle("Bisherige Flüge vorher löschen (sauberer Neuimport)", isOn: $replaceExisting)
                        Button {
                            Task { await runAI() }
                        } label: {
                            Label("KI-Analyse starten (ca. CHF \(String(format: "%.2f", max(0.05, MailAI.estimatedCost(pendingMails)))))", systemImage: "sparkles")
                                .fontWeight(.semibold)
                        }
                        .disabled(busy)
                    } footer: {
                        Text("Kosten werden direkt von deinem Claude-Guthaben abgebucht. Die Mail-Texte gehen dafür verschlüsselt an Anthropic.")
                    }
                }

                Section("Mail-Text einfügen") {
                    TextEditor(text: $pasteText)
                        .frame(minHeight: 110)
                        .font(.footnote)
                    HStack {
                        Button("Aus Zwischenablage") {
                            pasteText = UIPasteboard.general.string ?? ""
                            analyze(pasteText, source: "Eingefügter Text")
                        }
                        .buttonStyle(.borderless)
                        Spacer()
                        Button("Analysieren") { analyze(pasteText, source: "Eingefügter Text") }
                            .buttonStyle(.borderless)
                            .disabled(pasteText.isEmpty)
                    }
                }

                Section {
                    Button { picking = true } label: {
                        Label("PDF / E-Mail-Datei wählen", systemImage: "doc.text.magnifyingglass")
                    }
                } footer: {
                    Text("Tipp: In Outlook ein PDF-Ticket oder eine Bordkarte teilen → „Skylog“ wählen.")
                }

                if let status {
                    Section {
                        HStack {
                            if busy { ProgressView().padding(.trailing, 6) }
                            Text(status).font(.subheadline)
                        }
                    }
                }

                if !candidates.isEmpty {
                    Section("Gefundene Flüge (\(candidates.count))") {
                        ForEach(candidates) { c in
                            let exists = store.contains(number: c.number, date: c.date)
                            Toggle(isOn: Binding(
                                get: { selected.contains(c.id) },
                                set: { on in if on { selected.insert(c.id) } else { selected.remove(c.id) } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.number) · \(Fmt.day(c.date))").font(.headline)
                                    if !c.airports.isEmpty {
                                        Text(c.airports.joined(separator: " → ")).font(.subheadline)
                                    }
                                    Text(exists ? "Bereits gespeichert" : c.source)
                                        .font(.caption)
                                        .foregroundStyle(exists ? .orange : .secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        HStack {
                            Button("Alle") { selected = Set(candidates.map(\.id)) }.buttonStyle(.borderless)
                            Spacer()
                            Button("Keine") { selected = [] }.buttonStyle(.borderless)
                        }
                    }
                    Section {
                        Button {
                            Task { await importSelected() }
                        } label: {
                            Text("\(selected.count) Flüge importieren").frame(maxWidth: .infinity).fontWeight(.semibold)
                        }
                        .disabled(selected.isEmpty || busy)
                    } footer: {
                        Text("Pro Flug wird eine API-Abfrage benötigt. Flüge, die die API nicht kennt, werden mit den Angaben aus der Mail gespeichert.")
                    }
                }
            }
            .navigationTitle("Aus E-Mails importieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } }
            }
            .fileImporter(isPresented: $picking,
                          allowedContentTypes: [.pdf, .emailMessage, .plainText, .html, .text],
                          allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { urls.forEach(analyzeFile) }
            }
            .task {
                if let initialFile { analyzeFile(initialFile) }
            }
        }
    }

    // MARK: Actions

    private func merge(_ found: [FlightCandidate]) {
        for c in found where !c.cancelled && !candidates.contains(where: { $0.id == c.id }) {
            candidates.append(c)
            if !store.contains(number: c.number, date: c.date) && Self.isPlausible(c) { selected.insert(c.id) }
        }
        candidates.sort { $0.date > $1.date }
    }

    private func analyze(_ text: String, source: String) {
        let found = FlightTextParser.parse(text, source: source)
        merge(found)
        status = found.isEmpty ? "Keine Flüge erkannt." : "\(found.count) Flug/Flüge erkannt."
    }

    private func analyzeFile(_ url: URL) {
        guard let text = DocumentText.extract(from: url), !text.isEmpty else {
            status = "Datei konnte nicht gelesen werden: \(url.lastPathComponent)"
            return
        }
        analyze(text, source: url.lastPathComponent)
    }

    private func scanOutlook() async {
        busy = true
        // Keep the screen awake and ask iOS for extra time if the app goes to the background
        UIApplication.shared.isIdleTimerDisabled = true
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "MailScan")
        defer {
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        do {
            if !OutlookAuth.shared.isConnected {
                status = "Anmeldung …"
                try await OutlookAuth.shared.signIn()
                connected = true
            }
            if AIClient.hasKey {
                let mails = try await OutlookMail.fetchMails { message in status = message }
                pendingMails = MailAI.relevant(mails)
                status = "\(mails.count) Mails durchsucht, \(pendingMails.count) davon enthalten Flugdaten."
            } else {
                let found = try await OutlookMail.scan { message in status = message }
                merge(found)
            }
        } catch {
            status = error.localizedDescription
            connected = OutlookAuth.shared.isConnected
        }
    }

    private func runAI() async {
        busy = true
        UIApplication.shared.isIdleTimerDisabled = true
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "MailAI")
        defer {
            busy = false
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.endBackgroundTask(bgTask)
        }
        do {
            if replaceExisting { store.deleteAll() }
            let found = try await MailAI.extract(pendingMails) { message in status = message }
            pendingMails = []
            candidates = []
            selected = []
            merge(found)
            status = "\(found.count) Flüge erkannt – prüfen und importieren."
        } catch {
            status = error.localizedDescription
        }
    }

    private func importSelected() async {
        busy = true
        defer { busy = false }
        let todo = candidates.filter { selected.contains($0.id) }
        var ok = 0, fallback = 0, skipped = 0
        for (i, c) in todo.enumerated() {
            status = "Importiere \(i + 1)/\(todo.count): \(c.number) …"
            do {
                // Save the API quota: only flights around today get live data; everything else from the mail.
                let near = abs(c.date.timeIntervalSinceNow) < 3 * 86400
                guard near, FlightData.isConfigured else { throw APIError.notFound }
                let results = try await FlightData.search(number: c.number, date: c.date)
                let pick = results.first { c.airports.contains($0.departure.code) } ?? results[0]
                store.add(pick)
                ok += 1
            } catch {
                // Not confirmed by the flight data service: only keep plausible past flights with real airports
                if let manual = await Self.manualFlight(c) {
                    store.add(manual)
                    fallback += 1
                } else {
                    skipped += 1
                }
            }
            selected.remove(c.id)
        }
        status = "\(ok) Flüge mit Live-Daten"
            + (fallback > 0 ? ", \(fallback) aus den Mail-Angaben importiert" : "")
            + (skipped > 0 ? ", \(skipped) unplausible Treffer verworfen" : "") + "."
    }

    /// Known airline, two airport codes, in the past.
    static func isPlausible(_ c: FlightCandidate) -> Bool {
        if c.aiVerified { return c.airports.count == 2 }
        let code = String(c.number.prefix(2))
        return FlightTextParser.airlines.contains(code) && c.airports.count == 2
    }

    /// Flight built from the mail data (old flights the APIs no longer know, or future flights not yet in their range).
    static func manualFlight(_ c: FlightCandidate) async -> Flight? {
        guard isPlausible(c), c.aiVerified || c.date < Date().addingTimeInterval(-86400),
              let depCode = c.airports.first, let arrCode = c.airports.dropFirst().first, depCode != arrCode else { return nil }
        var dep = await AirportLookup.fill(FlightEndpoint(iata: depCode), code: depCode)
        var arr = await AirportLookup.fill(FlightEndpoint(iata: arrCode), code: arrCode)
        // Both airports must really exist
        guard dep.coordinate != nil, arr.coordinate != nil else { return nil }
        dep.scheduled = localDate(c.date, time: c.departureTime, tz: dep.tz, dayOffset: 0)
        arr.scheduled = localDate(c.date, time: c.arrivalTime, tz: arr.tz, dayOffset: c.arrivalDayOffset)
        let future = (dep.scheduled ?? c.date) > Date()
        var f = Flight(number: c.number, date: Fmt.apiDate.string(from: c.date), status: future ? "Expected" : "Arrived",
                       departure: dep, arrival: arr)
        if let ref = c.bookingReference { f.notes = "Buchungscode: \(ref)" }
        return f
    }

    private static func localDate(_ day: Date, time: String?, tz: TimeZone, dayOffset: Int) -> Date? {
        guard let time, time.count >= 4 else { return nil }
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let local = Calendar.current.dateComponents([.year, .month, .day], from: day)
        var comps = DateComponents(year: local.year, month: local.month, day: local.day, hour: parts[0], minute: parts[1])
        comps.timeZone = tz
        guard let d = cal.date(from: comps) else { return nil }
        return cal.date(byAdding: .day, value: dayOffset, to: d)
    }
}

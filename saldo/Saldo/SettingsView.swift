import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(FinanceStore.self) private var store
    @AppStorage("lockEnabled") private var lockEnabled = true
    @AppStorage("aboReminders") private var aboReminders = true
    @State private var krakenKey = Kraken.key
    @State private var krakenSecret = Kraken.secret
    @State private var importing = false
    @State private var importFile: ImportFile?
    @State private var confirmWipe = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink { ApplePayGuide() } label: { Label("Apple Pay automatisch erfassen", systemImage: "wave.3.right.circle") }
                    Button { importing = true } label: { Label("Kontoauszug importieren (camt.053 / CSV)", systemImage: "doc.badge.arrow.up") }
                    NavigationLink { KeyGuideView(guide: .bank) } label: { Label("So exportierst du den Kontoauszug", systemImage: "questionmark.circle") }
                } header: {
                    Text("Ausgaben erfassen")
                } footer: {
                    Text("TKB E-Banking: Konto → Kontoauszug/Export → Format camt.053 (XML) oder CSV herunterladen und hier auswählen oder direkt mit Saldo teilen. Doppelte Buchungen werden erkannt.")
                }

                Section {
                    SecureField("API-Key", text: $krakenKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Private Key", text: $krakenSecret).textInputAutocapitalization(.never).autocorrectionDisabled()
                    NavigationLink { KeyGuideView(guide: .kraken) } label: { Label("So bekommst du die Keys", systemImage: "questionmark.circle") }
                    Button("Speichern & testen") {
                        Keychain.set(krakenKey.trimmingCharacters(in: .whitespacesAndNewlines), for: "krakenKey")
                        Keychain.set(krakenSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: "krakenSecret")
                        Task {
                            await store.refreshCrypto()
                            message = store.lastError ?? "Kraken verbunden: \(store.holdings.filter { $0.source == "Kraken" }.count) Assets."
                        }
                    }
                } header: {
                    Text("Kraken")
                } footer: {
                    Text("Kraken → Einstellungen → API → neuen Key erstellen und NUR „Query Funds“ erlauben (kein Handel, keine Auszahlung). Keys werden im iPhone-Schlüsselbund gespeichert.")
                }

                Section {
                    Toggle("Abo-Erinnerung 2 Tage vor Abbuchung", isOn: $aboReminders)
                        .onChange(of: aboReminders) { _, _ in Task { await Reminders.scheduleSubscriptionReminders(store) } }
                } header: {
                    Text("Mitteilungen")
                } footer: {
                    Text("Budget-Warnungen bei 80 % und 100 % kommen automatisch, sobald ein Budget gesetzt ist.")
                }

                Section("Budgets pro Monat") {
                    ForEach(Category.allCases.filter(\.isSpending)) { c in
                        HStack {
                            Label(c.label, systemImage: c.icon)
                            Spacer()
                            TextField("–", value: Binding(get: { store.budgets[c] }, set: { store.setBudget($0, for: c) }),
                                      format: .number.precision(.fractionLength(0)))
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                        }
                    }
                }

                Section("Gelernte Kategorien") {
                    if store.rules.isEmpty {
                        Text("Wenn du bei einer Buchung die Kategorie änderst, merkt sich Saldo das hier.").foregroundStyle(.secondary).font(.footnote)
                    }
                    ForEach(store.rules) { r in
                        LabeledContent(r.keyword, value: r.category.label)
                    }
                    .onDelete { store.deleteRules($0.map { store.rules[$0].id }) }
                }

                Section("Sicherheit & Daten") {
                    Toggle("Mit Face ID sperren", isOn: $lockEnabled)
                    if let url = store.exportCSV() {
                        ShareLink(item: url) { Label("Buchungen exportieren (CSV)", systemImage: "square.and.arrow.up") }
                    }
                    Button("Alle Daten löschen", role: .destructive) { confirmWipe = true }
                }
            }
            .navigationTitle("Einstellungen")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.xml, .commaSeparatedText, .plainText, .text, .data]) { result in
                if case .success(let url) = result { importFile = ImportFile(url: url) }
            }
            .sheet(item: $importFile) { file in BankImportView(url: file.url) }
            .confirmationDialog("Wirklich alles löschen?", isPresented: $confirmWipe, titleVisibility: .visible) {
                Button("Alles löschen", role: .destructive) {
                    store.wipe()
                    Keychain.set(nil, for: "krakenKey")
                    Keychain.set(nil, for: "krakenSecret")
                    krakenKey = ""; krakenSecret = ""
                }
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }
}

struct ApplePayGuide: View {
    var body: some View {
        List {
            Section {
                Text("Mit einer Kurzbefehl-Automation landet jede Apple-Pay-Zahlung automatisch in Saldo – Betrag, Händler und Karte.")
            }
            Section("Einmalig einrichten") {
                step(1, "Öffne die App **Kurzbefehle** → Tab **Automation** → **+**.")
                step(2, "Wähle **Transaktion**. Wähle deine Karten aus und tippe auf **Weiter**.")
                step(3, "Wähle **Sofort ausführen** (und schalte „Bei Ausführung mitteilen“ nach Wunsch aus).")
                step(4, "Tippe **Neuer leerer Kurzbefehl** → **Aktion hinzufügen** → suche **Saldo** → **Zahlung in Saldo erfassen**.")
                step(5, "Tippe auf **Betrag** → **Kurzbefehleingabe** wählen und dann **Betrag**. Genauso **Händler** → Kurzbefehleingabe → **Händler**, und **Karte** → **Karte bzw. Name**.")
                step(6, "Fertig. Bezahl mal mit Apple Pay – die Zahlung erscheint sofort unter Ausgaben.")
            }
            Section {
                Text("Wenn du später auch den Kontoauszug importierst, erkennt Saldo die Apple-Pay-Zahlungen als Duplikate (gleicher Tag, gleicher Betrag) und zählt sie nicht doppelt.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Apple Pay")
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 28, height: 28).background(Theme.accent.opacity(0.25), in: Circle())
            Text(text)
        }
    }
}

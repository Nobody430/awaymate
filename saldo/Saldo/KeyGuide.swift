import SwiftUI

/// Step-by-step instructions shown inside the app.
struct KeyGuide {
    let title: String
    let intro: String
    let steps: [(text: String, link: URL?)]
    let note: String?

    static let kraken = KeyGuide(
        title: "Kraken verbinden",
        intro: "Saldo liest nur deine Kontostände. Der Key darf nichts handeln und nichts auszahlen.",
        steps: [
            ("Kraken im Browser öffnen und anmelden (am iPhone: „aA“ → „Desktop-Website anfordern“).", URL(string: "https://www.kraken.com/u/security/api")),
            ("Profil (oben rechts) → Settings → API → „Create API key“ bzw. „Generate New Key“.", nil),
            ("Name: Saldo. Bei den Berechtigungen NUR „Query Funds“ anhaken – alles andere aus lassen.", nil),
            ("„Generate key“ tippen. Es erscheinen „API Key“ und „Private Key“. Den Private Key siehst du nur einmal!", nil),
            ("In Saldo: Einstellungen → Kraken → beide Keys einfügen → „Speichern & testen“.", nil),
        ],
        note: "Die Keys werden im iPhone-Schlüsselbund gespeichert. Du kannst den Key bei Kraken jederzeit löschen.")

    static let bank = KeyGuide(
        title: "Kontoauszug aus dem E-Banking",
        intro: "Schweizer Banken bieten Auszüge im Format camt.053 (XML) oder CSV. Saldo liest beide und erkennt Duplikate.",
        steps: [
            ("Im E-Banking der Bank anmelden (am iPhone im Browser oder am PC).", nil),
            ("Konto wählen → „Kontoauszug“, „Bewegungen“ oder „Export“.", nil),
            ("Zeitraum wählen (z.B. letztes Jahr) und als „camt.053“/„ISO 20022 XML“ oder „CSV“ herunterladen.", nil),
            ("Die Datei mit Saldo teilen (Teilen → Saldo) oder in Saldo: Einstellungen → „Kontoauszug importieren“.", nil),
            ("Kontoname prüfen → „Importieren“. Der Kontostand wird automatisch aktualisiert.", nil),
        ],
        note: "Die genaue Menübezeichnung hängt von der Bank ab. Klappt der Import nicht, eine Beispieldatei (ohne echte Daten) zur Anpassung schicken.")
}

struct KeyGuideView: View {
    let guide: KeyGuide

    var body: some View {
        List {
            Section { Text(guide.intro) }
            Section("Schritte") {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)").font(.headline).frame(width: 28, height: 28)
                            .background(Theme.accent.opacity(0.25), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.text)
                            if let link = step.link {
                                Link(destination: link) { Label("Öffnen", systemImage: "arrow.up.right.square") }
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }
            }
            if let note = guide.note { Section { Text(note).font(.footnote).foregroundStyle(.secondary) } }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

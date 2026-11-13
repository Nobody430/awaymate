import SwiftUI

/// Step-by-step instructions for obtaining the API keys, shown inside the app.
struct KeyGuide: Identifiable {
    let id: String
    let title: String
    let icon: String
    let intro: String
    let steps: [(text: String, link: URL?)]
    let note: String?

    static let pushServer = KeyGuide(
        id: "push", title: String(localized: "Eigener Push-Server (gratis)"), icon: "bolt.horizontal.circle",
        intro: String(localized: "Für Bastler. Mit einem eigenen kleinen Server kommen Gate-Wechsel, Verspätungen, Start und Landung sofort – auch wenn das iPhone gesperrt ist – und die Live-Aktivität aktualisiert sich von selbst. Der Server läuft gratis bei Cloudflare und nutzt deine eigenen Flugdaten-Keys. Einmalig ca. 20 Minuten, am besten am Computer. Ohne Server funktioniert Awaymate ganz normal weiter."),
        steps: [
            (String(localized: "TEIL 1 – Projekt kopieren. Bei GitHub anmelden (oder Konto erstellen), das Awaymate-Projekt öffnen und oben rechts auf „Fork“ tippen. Damit hast du deine eigene Kopie."), URL(string: "https://github.com/Nobody430/awaymate")),
            (String(localized: "TEIL 2 – Cloudflare. Gratis-Konto erstellen (keine Kreditkarte nötig)."), URL(string: "https://dash.cloudflare.com/sign-up")),
            (String(localized: "Im Dashboard einmal „Workers & Pages“ öffnen (legt deine workers.dev-Adresse an). Rechts steht die „Account ID“ – kopieren."), URL(string: "https://dash.cloudflare.com/?to=/:account/workers-and-pages")),
            (String(localized: "Profil → „API Tokens“ → „Create Token“ → Vorlage „Edit Cloudflare Workers“ → „Continue to summary“ → „Create Token“. Den Token kopieren (wird nur einmal angezeigt)."), URL(string: "https://dash.cloudflare.com/profile/api-tokens")),
            (String(localized: "TEIL 3 – Secrets. In DEINER Kopie bei GitHub: Settings → Secrets and variables → Actions → „New repository secret“. (Geht nur im Browser, nicht in der GitHub-App.)"), nil),
            (String(localized: "Secret 1 – Name: CLOUDFLARE_API_TOKEN · Inhalt: der Token aus Teil 2."), nil),
            (String(localized: "Secret 2 – Name: CLOUDFLARE_ACCOUNT_ID · Inhalt: die Account ID aus Teil 2."), nil),
            (String(localized: "Secret 3 – Name: SERVER_TOKEN · Inhalt: ein langes, selbst erfundenes Passwort (mind. 24 Zeichen, nur Buchstaben und Zahlen). Du brauchst es gleich nochmal in Awaymate."), nil),
            (String(localized: "Secret 4 – Name: RELAY_URL · Inhalt: die Adresse des Awaymate-Relays. Sie steht in der Projektbeschreibung (README) unter „Relay“."), URL(string: "https://github.com/Nobody430/awaymate#relay")),
            (String(localized: "TEIL 4 – Server starten. In deiner Kopie auf „Actions“ (beim ersten Mal Workflows aktivieren) → links „Deploy push server“ → „Run workflow“. Nach 1–2 Minuten erscheint ein grüner Haken; in der Zusammenfassung steht die Adresse deines Servers (…workers.dev)."), nil),
            (String(localized: "TEIL 5 – Awaymate verbinden. Einstellungen → „Echtzeit-Pushs (eigener Server)“: die Adresse aus Teil 4 und das Passwort aus Secret 3 eintragen. „Verbindung testen“ – es sollte eine Test-Mitteilung kommen."), nil),
            (String(localized: "Laufende Live-Aktivitäten einmal beenden und neu starten, damit sie die Updates vom Server bekommen."), nil),
        ],
        note: String(localized: "Dein FlightAware-Key aus den Einstellungen wird verschlüsselt an DEINEN Server geschickt, damit er Gates und Verspätungen abfragen kann; ohne Key meldet er nur Start und Landung (gratis über ADS-B). Das Relay des Herausgebers reicht nur die fertige Mitteilung an Apple weiter – es sieht weder deine Keys noch deine Flugliste. Statt Cloudflare geht auch Docker (Fly.io, eigener Rechner): siehe README im Ordner „server“. Roter Haken? Meist ist ein Secret-Name falsch geschrieben.") + " " + String(localized: "Auch dein AeroDataBox-Key geht an deinen Server, damit er in der letzten Stunde vor Abflug den echten Boarding-Status abfragen kann."))

    static let aerodatabox = KeyGuide(
        id: "adb", title: String(localized: "AeroDataBox-Key (gratis)"), icon: "airplane.circle",
        intro: String(localized: "Flugdaten über RapidAPI. Der Basic-Plan ist gratis, hat aber nur wenige Abfragen pro Monat."),
        steps: [
            (String(localized: "AeroDataBox auf RapidAPI öffnen."), URL(string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox")),
            (String(localized: "Oben auf „Pricing“ (oder „Change plan“) tippen."), nil),
            (String(localized: "Beim Plan „Basic“ (0 $) auf „Subscribe“ tippen. Falls nötig mit Google, GitHub oder E-Mail registrieren."), nil),
            (String(localized: "Deine Apps auf RapidAPI öffnen."), URL(string: "https://rapidapi.com/developer/apps")),
            (String(localized: "„default-application“ → „Authorization“ → den „Application Key“ kopieren."), nil),
            (String(localized: "Zurück in Awaymate: Einstellungen → Flugdaten → „AeroDataBox“ wählen → Key einfügen."), nil),
            (String(localized: "Testen: In der Flugliste auf + tippen, Flugnummer eingeben (z.B. LX1612) und suchen."), nil),
        ],
        note: String(localized: "Alternativ steht derselbe Key auf jeder Endpoint-Seite im Feld „X-RapidAPI-Key“."))

    static let flightaware = KeyGuide(
        id: "fa", title: String(localized: "FlightAware-Key (5 $ Guthaben/Monat)"), icon: "dot.radiowaves.left.and.right",
        intro: String(localized: "Sehr zuverlässige Daten (Gates, Gepäckband, echte Zeiten). Monatliches Gratis-Guthaben, danach Abrechnung pro Abfrage."),
        steps: [
            (String(localized: "AeroAPI-Portal öffnen und anmelden bzw. ein FlightAware-Konto erstellen."), URL(string: "https://www.flightaware.com/aeroapi/portal/")),
            (String(localized: "Die Stufe „Personal“ wählen und die Bedingungen akzeptieren."), nil),
            (String(localized: "Unter „Billing“ ein monatliches Limit von 5 $ setzen, dann kann nie etwas anfallen."), nil),
            (String(localized: "Unter „API Keys“ auf „Create API Key“ tippen, Beschreibung „Awaymate“, und den Key kopieren."), nil),
            (String(localized: "Zurück in Awaymate: Einstellungen → Flugdaten → „FlightAware AeroAPI“ wählen → Key einfügen."), nil),
        ],
        note: String(localized: "Möglicherweise verlangt FlightAware eine Kreditkarte. Mit dem 5-$-Limit wird nichts abgebucht."))

    static let claude = KeyGuide(
        id: "claude", title: String(localized: "Claude-Key (KI-Erkennung)"), icon: "sparkles",
        intro: String(localized: "Damit Awaymate Flüge in deinen Mails zuverlässig erkennt. Du zahlst nur, was du nutzt – mit dem günstigen Modell (Haiku) kostet ein kompletter Postfach-Import meist nur Rappen. Du kannst denselben Key wie in Vital verwenden."),
        steps: [
            (String(localized: "Anthropic Console öffnen und ein Konto erstellen (E-Mail oder Google)."), URL(string: "https://console.anthropic.com/")),
            (String(localized: "Unter „Billing“ Guthaben aufladen, z.B. 5 $. Optional ein Ausgabenlimit setzen."), URL(string: "https://console.anthropic.com/settings/billing")),
            (String(localized: "Unter „API Keys“ → „Create Key“ → Name „Awaymate“ → Key kopieren (beginnt mit sk-ant-, wird nur einmal angezeigt)."), URL(string: "https://console.anthropic.com/settings/keys")),
            (String(localized: "Zurück in Awaymate: Einstellungen → KI-Erkennung → Key einfügen."), nil),
            (String(localized: "Dann: Flugliste → + → „Aus E-Mails importieren“ → Postfach durchsuchen → „KI-Analyse starten“."), nil),
        ],
        note: String(localized: "Für die Analyse werden die Texte der Reise-Mails an Anthropic geschickt; sie werden nicht zum Training verwendet."))

    static let openai = KeyGuide(
        id: "openai", title: String(localized: "OpenAI-Key"), icon: "key",
        intro: String(localized: "Achtung: Ein ChatGPT-Abo (Plus/Pro) gilt NICHT für die API. Die API wird separat über Guthaben abgerechnet."),
        steps: [
            (String(localized: "OpenAI-Plattform öffnen und mit deinem ChatGPT-/OpenAI-Konto anmelden."), URL(string: "https://platform.openai.com/")),
            (String(localized: "Unter „Billing“ prüfen, ob API-Guthaben vorhanden ist – sonst z.B. 5 $ aufladen."), URL(string: "https://platform.openai.com/settings/organization/billing/overview")),
            (String(localized: "Unter „API keys“ → „Create new secret key“ → Name „Awaymate“ → Key kopieren (beginnt mit sk-, wird nur einmal angezeigt)."), URL(string: "https://platform.openai.com/api-keys")),
            (String(localized: "Zurück in Awaymate: Einstellungen → KI-Erkennung → „OpenAI“ wählen → Key einfügen."), nil),
            (String(localized: "Modell: Standard ist „gpt-5-mini“ (günstig). Aktuelle Modellnamen unter platform.openai.com/docs/models."), URL(string: "https://platform.openai.com/docs/models")),
        ],
        note: String(localized: "Ein Postfach-Import mit einem Mini-Modell kostet meist nur Rappen."))

    static let outlook = KeyGuide(
        id: "ms", title: String(localized: "Outlook-Zugang (Postfach durchsuchen)"), icon: "envelope",
        intro: String(localized: "Damit Awaymate dein ganzes Outlook/Hotmail/MSN-Postfach nach Flügen durchsuchen darf (auch alte Flüge). Private Microsoft-Konten brauchen dafür einmalig ein kostenloses Azure-Konto. Ca. 10 Minuten."),
        steps: [
            (String(localized: "Kostenloses Azure-Konto mit deinem Outlook-Konto anlegen (Kreditkarte dient nur zur Identitätsprüfung, App-Registrierungen sind gratis)."), URL(string: "https://azure.microsoft.com/free/")),
            (String(localized: "Microsoft Entra öffnen → App-Registrierungen."), URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")),
            (String(localized: "„Neue Registrierung“ → Name: Awaymate."), nil),
            (String(localized: "Kontotyp: „Konten in einem beliebigen Organisationsverzeichnis und persönliche Microsoft-Konten“ → Registrieren."), nil),
            (String(localized: "Links „Authentifizierung“ → „Plattform hinzufügen“ → „iOS/macOS“ → Bundle-ID: com.nobody430.skylog → Konfigurieren."), nil),
            (String(localized: "Links „API-Berechtigungen“ → „Berechtigung hinzufügen“ → Microsoft Graph → Delegiert → „Mail.Read“ → Hinzufügen."), nil),
            (String(localized: "Links „Übersicht“ → „Anwendungs-ID (Client-ID)“ kopieren."), nil),
            (String(localized: "Zurück in Awaymate: Einstellungen → E-Mail-Import → Client-ID einfügen."), nil),
            (String(localized: "Flugliste → + → „Aus E-Mails importieren“ → „Mit Outlook anmelden & durchsuchen“. Awaymate geht das ganze Postfach durch."), nil),
        ],
        note: String(localized: "Ohne Azure: Mail in Outlook öffnen → „…“ → Drucken → Teilen → Awaymate. Oder Text kopieren → + → Aus E-Mails importieren → Aus Zwischenablage. Die Mails werden nur auf deinem iPhone ausgewertet."))
}

struct KeyGuideView: View {
    let guide: KeyGuide

    var body: some View {
        List {
            Section { Text(guide.intro) }
            Section("Schritte") {
                ForEach(Array(guide.steps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(i + 1)")
                            .font(.headline)
                            .frame(width: 28, height: 28)
                            .background(Theme.accent.opacity(0.25), in: Circle())
                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.text)
                            if let link = step.link {
                                Link(destination: link) {
                                    Label("Öffnen", systemImage: "arrow.up.right.square")
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if let note = guide.note {
                Section { Text(note).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

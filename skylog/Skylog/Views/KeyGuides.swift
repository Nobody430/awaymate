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
        id: "push", title: "Eigener Push-Server (Fly.io)", icon: "bolt.horizontal.circle",
        intro: "Mit dem Server kommen Gate-Wechsel, Verspätungen, Start und Landung sofort – auch wenn das iPhone gesperrt ist – und die Live-Aktivität aktualisiert sich von selbst. Einmalig ca. 20 Minuten, am besten am Computer. Kosten: ca. 2–3 $ pro Monat bei Fly.io (kein Gratis-Plan mehr für neue Konten). Die Schlüssel trägst du nur bei GitHub ein, nie in einem Chat.",
        steps: [
            ("TEIL 1 – Fly.io. Konto erstellen (E-Mail, Google oder GitHub). Neue Konten starten mit einer kurzen Testphase; damit der Server danach weiterläuft, unter „Billing“ eine Kreditkarte hinterlegen.", URL(string: "https://fly.io/app/sign-up")),
            ("Im Fly.io-Dashboard die Organisation „Personal“ wählen und links auf „Tokens“ tippen.", URL(string: "https://fly.io/dashboard/personal/tokens")),
            ("Name „skylog“ eingeben, auf „Create Organization Token“ tippen und den ganzen Text kopieren – inklusive „FlyV1 “ am Anfang. Er wird nur einmal angezeigt. Das ist später das Secret FLY_API_TOKEN.", nil),
            ("TEIL 2 – Apple. Im Apple-Developer-Konto „Keys“ öffnen und auf + tippen.", URL(string: "https://developer.apple.com/account/resources/authkeys/list")),
            ("Key Name „Skylog Push“. Haken bei „Apple Push Notifications service (APNs)“ setzen, daneben auf „Configure“: Umgebung „Sandbox & Production“ (falls nicht angeboten: „Production“), Art „Team Scoped (All Topics)“. Speichern → „Continue“ → „Confirm“ (bzw. „Register“).", nil),
            ("Auf „Download“ tippen: Die Datei AuthKey_XXXXXXXXXX.p8 lässt sich nur EINMAL laden – gut aufbewahren. Die 10 Zeichen „Key ID“ auf der Seite notieren (stehen auch im Dateinamen).", nil),
            ("TEIL 3 – GitHub. Dein Repository „ios-apps“ im Browser öffnen: Settings → Secrets and variables → Actions → „New repository secret“. (In der GitHub-Handy-App geht das nicht – github.com im Browser nutzen.)", URL(string: "https://github.com/Nobody430/ios-apps/settings/secrets/actions")),
            ("Secret 1 – Name: FLY_API_TOKEN · Inhalt: der Token aus Teil 1 (mit „FlyV1 “).", nil),
            ("Secret 2 – Name: FLY_APP_NAME · Inhalt: ein eigener, weltweit eindeutiger Name nur aus Kleinbuchstaben, Zahlen und Bindestrichen, z.B. skylog-push-n430. Daraus wird die Adresse skylog-push-n430.fly.dev.", nil),
            ("Secret 3 – Name: SERVER_TOKEN · Inhalt: ein langes, selbst erfundenes Passwort (mind. 24 Zeichen, nur Buchstaben und Zahlen). Du brauchst es gleich nochmal in Skylog.", nil),
            ("Secret 4 – Name: APNS_KEY_ID · Inhalt: die 10 Zeichen Key ID aus Teil 2.", nil),
            ("Secret 5 – Name: APNS_KEY_P8 · Inhalt: die .p8-Datei mit einem Texteditor öffnen und ALLES einfügen, von „-----BEGIN PRIVATE KEY-----“ bis „-----END PRIVATE KEY-----“.", nil),
            ("Optional Secret 6 – Name: FLIGHTAWARE_KEY · Inhalt: dein FlightAware-Key. Damit meldet der Server auch Gate-Wechsel und Verspätungen; ohne ihn nur Start und Landung.", nil),
            ("TEIL 4 – Server starten. Im Repository auf „Actions“ → links „Deploy push server“ → rechts „Run workflow“ → grüner Knopf „Run workflow“. Nach 2–3 Minuten sollte ein grüner Haken erscheinen.", URL(string: "https://github.com/Nobody430/ios-apps/actions/workflows/server.yml")),
            ("TEIL 5 – Skylog verbinden. Einstellungen → „Echtzeit-Pushs (eigener Server)“: als Adresse deinen-namen.fly.dev eintragen, als Server-Token das Passwort aus Secret 3. Dann „Verbindung testen“ – es sollte eine Test-Mitteilung kommen.", nil),
            ("Zum Schluss laufende Live-Aktivitäten einmal beenden und neu starten, damit sie die Updates vom Server bekommen.", nil),
        ],
        note: "Roter Haken bei „Deploy push server“? Meist ist ein Secret-Name falsch geschrieben, der App-Name schon vergeben (anderen wählen) oder bei Fly.io fehlt die Kreditkarte. Apple erlaubt nur zwei solche Schlüssel pro Umgebung – ist das Limit erreicht, einen bestehenden Push-Schlüssel wiederverwenden. Bei Fly.io kannst du unter „Billing“ jederzeit die Kosten sehen und den Server unter „Apps“ löschen.")

    static let aerodatabox = KeyGuide(
        id: "adb", title: "AeroDataBox-Key (gratis)", icon: "airplane.circle",
        intro: "Flugdaten über RapidAPI. Der Basic-Plan ist gratis, hat aber nur wenige Abfragen pro Monat.",
        steps: [
            ("AeroDataBox auf RapidAPI öffnen.", URL(string: "https://rapidapi.com/aedbx-aedbx/api/aerodatabox")),
            ("Oben auf „Pricing“ (oder „Change plan“) tippen.", nil),
            ("Beim Plan „Basic“ (0 $) auf „Subscribe“ tippen. Falls nötig mit Google, GitHub oder E-Mail registrieren.", nil),
            ("Deine Apps auf RapidAPI öffnen.", URL(string: "https://rapidapi.com/developer/apps")),
            ("„default-application“ → „Authorization“ → den „Application Key“ kopieren.", nil),
            ("Zurück in Skylog: Einstellungen → Flugdaten → „AeroDataBox“ wählen → Key einfügen.", nil),
            ("Testen: In der Flugliste auf + tippen, Flugnummer eingeben (z.B. LX1612) und suchen.", nil),
        ],
        note: "Alternativ steht derselbe Key auf jeder Endpoint-Seite im Feld „X-RapidAPI-Key“.")

    static let flightaware = KeyGuide(
        id: "fa", title: "FlightAware-Key (5 $ Guthaben/Monat)", icon: "dot.radiowaves.left.and.right",
        intro: "Sehr zuverlässige Daten (Gates, Gepäckband, echte Zeiten). Monatliches Gratis-Guthaben, danach Abrechnung pro Abfrage.",
        steps: [
            ("AeroAPI-Portal öffnen und anmelden bzw. ein FlightAware-Konto erstellen.", URL(string: "https://www.flightaware.com/aeroapi/portal/")),
            ("Die Stufe „Personal“ wählen und die Bedingungen akzeptieren.", nil),
            ("Unter „Billing“ ein monatliches Limit von 5 $ setzen, dann kann nie etwas anfallen.", nil),
            ("Unter „API Keys“ auf „Create API Key“ tippen, Beschreibung „Skylog“, und den Key kopieren.", nil),
            ("Zurück in Skylog: Einstellungen → Flugdaten → „FlightAware AeroAPI“ wählen → Key einfügen.", nil),
        ],
        note: "Möglicherweise verlangt FlightAware eine Kreditkarte. Mit dem 5-$-Limit wird nichts abgebucht.")

    static let claude = KeyGuide(
        id: "claude", title: "Claude-Key (KI-Erkennung)", icon: "sparkles",
        intro: "Damit Skylog Flüge in deinen Mails zuverlässig erkennt. Du zahlst nur, was du nutzt – mit dem günstigen Modell (Haiku) kostet ein kompletter Postfach-Import meist nur Rappen. Du kannst denselben Key wie in Vital verwenden.",
        steps: [
            ("Anthropic Console öffnen und ein Konto erstellen (E-Mail oder Google).", URL(string: "https://console.anthropic.com/")),
            ("Unter „Billing“ Guthaben aufladen, z.B. 5 $. Optional ein Ausgabenlimit setzen.", URL(string: "https://console.anthropic.com/settings/billing")),
            ("Unter „API Keys“ → „Create Key“ → Name „Skylog“ → Key kopieren (beginnt mit sk-ant-, wird nur einmal angezeigt).", URL(string: "https://console.anthropic.com/settings/keys")),
            ("Zurück in Skylog: Einstellungen → KI-Erkennung → Key einfügen.", nil),
            ("Dann: Flugliste → + → „Aus E-Mails importieren“ → Postfach durchsuchen → „KI-Analyse starten“.", nil),
        ],
        note: "Für die Analyse werden die Texte der Reise-Mails an Anthropic geschickt; sie werden nicht zum Training verwendet.")

    static let openai = KeyGuide(
        id: "openai", title: "OpenAI-Key", icon: "key",
        intro: "Achtung: Ein ChatGPT-Abo (Plus/Pro) gilt NICHT für die API. Die API wird separat über Guthaben abgerechnet.",
        steps: [
            ("OpenAI-Plattform öffnen und mit deinem ChatGPT-/OpenAI-Konto anmelden.", URL(string: "https://platform.openai.com/")),
            ("Unter „Billing“ prüfen, ob API-Guthaben vorhanden ist – sonst z.B. 5 $ aufladen.", URL(string: "https://platform.openai.com/settings/organization/billing/overview")),
            ("Unter „API keys“ → „Create new secret key“ → Name „Skylog“ → Key kopieren (beginnt mit sk-, wird nur einmal angezeigt).", URL(string: "https://platform.openai.com/api-keys")),
            ("Zurück in Skylog: Einstellungen → KI-Erkennung → „OpenAI“ wählen → Key einfügen.", nil),
            ("Modell: Standard ist „gpt-5-mini“ (günstig). Aktuelle Modellnamen unter platform.openai.com/docs/models.", URL(string: "https://platform.openai.com/docs/models")),
        ],
        note: "Ein Postfach-Import mit einem Mini-Modell kostet meist nur Rappen.")

    static let outlook = KeyGuide(
        id: "ms", title: "Outlook-Zugang (Postfach durchsuchen)", icon: "envelope",
        intro: "Damit Skylog dein ganzes Outlook/Hotmail/MSN-Postfach nach Flügen durchsuchen darf (auch alte Flüge). Private Microsoft-Konten brauchen dafür einmalig ein kostenloses Azure-Konto. Ca. 10 Minuten.",
        steps: [
            ("Kostenloses Azure-Konto mit deinem Outlook-Konto anlegen (Kreditkarte dient nur zur Identitätsprüfung, App-Registrierungen sind gratis).", URL(string: "https://azure.microsoft.com/free/")),
            ("Microsoft Entra öffnen → App-Registrierungen.", URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")),
            ("„Neue Registrierung“ → Name: Skylog.", nil),
            ("Kontotyp: „Konten in einem beliebigen Organisationsverzeichnis und persönliche Microsoft-Konten“ → Registrieren.", nil),
            ("Links „Authentifizierung“ → „Plattform hinzufügen“ → „iOS/macOS“ → Bundle-ID: com.nobody430.skylog → Konfigurieren.", nil),
            ("Links „API-Berechtigungen“ → „Berechtigung hinzufügen“ → Microsoft Graph → Delegiert → „Mail.Read“ → Hinzufügen.", nil),
            ("Links „Übersicht“ → „Anwendungs-ID (Client-ID)“ kopieren.", nil),
            ("Zurück in Skylog: Einstellungen → E-Mail-Import → Client-ID einfügen.", nil),
            ("Flugliste → + → „Aus E-Mails importieren“ → „Mit Outlook anmelden & durchsuchen“. Skylog geht das ganze Postfach durch.", nil),
        ],
        note: "Ohne Azure: Mail in Outlook öffnen → „…“ → Drucken → Teilen → Skylog. Oder Text kopieren → + → Aus E-Mails importieren → Aus Zwischenablage. Die Mails werden nur auf deinem iPhone ausgewertet.")
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

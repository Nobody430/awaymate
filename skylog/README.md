# Skylog ✈️

Flug- und Reise-App fürs iPhone (SwiftUI, iOS 17+). Ohne Abo und ohne zentralen Dienst: Jede und jeder nutzt die
eigenen API-Keys, die Daten bleiben auf dem Gerät. Wer will, betreibt zusätzlich einen eigenen kleinen Push-Server.

*English summary: Skylog is a self-hosted-friendly flight and trip tracker for iPhone. You bring your own API keys
(FlightAware and/or AeroDataBox, optionally Claude or OpenAI), everything is stored on the device, and an optional
free push server (Cloudflare Workers) delivers real-time notifications and Live Activity updates.
The app is available in German, English, French, Italian and Spanish.*

- [Funktionen](#funktionen)
- [Erste Schritte](#erste-schritte)
- [Keys und Dienste](#keys-und-dienste)
- [Eigener Push-Server](#eigener-push-server-optional)
- [Wie aktuell sind die Daten?](#wie-aktuell-sind-die-daten)
- [Datenschutz](#datenschutz)
- [Selbst bauen](#selbst-bauen)
- [Aufbau des Codes](#aufbau-des-codes)
- [Grenzen](#grenzen)

## Funktionen

**Flüge**
- Hinzufügen per Flugnummer und Datum, von Hand, aus E-Mails (Outlook-Postfach, eingefügter Text, PDF) oder
  aus dem iPhone-Kalender (Einträge mit Flugnummer).
- Status, Verspätung, geplante / erwartete / tatsächliche Zeiten – immer in der Ortszeit des Flughafens.
- Terminal, Gate, Check-in-Schalter, Gepäckband. Gates werden kurz vor Abflug gegen eine zweite Quelle geprüft;
  bei Widerspruch erscheint ein Hinweis.
- „Zeiten im Detail“: Gate verlassen, Rollen, Start, Landung, am Gate, Flugzeit.
- „Wo ist mein Flugzeug?“: der Zubringerflug und die Flüge davor, mit Einschätzung, ob die Zeit reicht.
- Anschlussflug-Karte mit Umsteigezeit und Warnung, wenn es knapp wird.
- Live-Position auf der Karte, voraussichtliche Ankunft aus Position und Geschwindigkeit. Unplausible Orte
  (weit neben der Route, oder der Platzhalter 0°/0°) werden nicht gezeichnet – dann steht das Flugzeug an der
  geschätzten Stelle, Höhe und Geschwindigkeit bleiben sichtbar.
- Eigener Status **„Rollt zum Start“** zwischen Verlassen des Gates und Abheben; „Gestartet“ erst nach dem Abheben.
- Änderungsprotokoll pro Flug (Gate, Zeiten, Status).

**Mitteilungen und Sperrbildschirm**
- Gate-Wechsel, neue Abflugzeit (auch schleichende Verspätungen), Zubringer gestartet / gelandet / zu spät,
  Start, Landung, Gepäckband, Annullierung.
- Erinnerungen: 3 h und 45 Min. vor Abflug, 20 Min. vor Landung, „weiter zum Hotel“, „bald zum Flughafen“.
- Live-Aktivität (Sperrbildschirm und Dynamic Island) mit Countdown, Gate, Verspätung pro Flughafen und Zubringer.
- Widgets: Home-Bildschirm (klein, mittel) und Sperrbildschirm (Zeile über der Uhr, Block darunter).

**Reisen**
- Reisen werden aus den Flügen vorgeschlagen; Hotels, Mietwagen, Züge aus Mails werden zugeordnet.
- Weg Flughafen ↔ Hotel mit ÖV- und Taxi-Zeit und „Losgehen spätestens …“.
- Reisetag-Plan (am Flughafen sein, Gepäckaufgabe, Boarding, Abflug, Landung, Gepäck) mit automatischem Puffer.
- Lage am Abflughafen: Wetter zur Abflugzeit; gemeldete Verspätungen am Flughafen (leicht / grösser, mit Grund).
- Zielinfos: Ortszeit, Zeitverschiebung, Wetter bei Ankunft, Wechselkurs, Steckdosen.
- Zug & Bus von und zur Heimat-Haltestelle (Schweiz).
- KI-Reiseplan Tag für Tag und persönliche Packliste (optional mit Notizen aus einem Obsidian-Vault).
- Dokumente pro Flug (Bordkarte, Buchung); am Reisetag als „Bordkarte öffnen“ zuoberst. PDFs, Bilder und
  Wallet-Pässe lassen sich aus anderen Apps an Skylog teilen.
- Kalender-Abgleich für Flüge und Hotels (einschaltbar).
- Umbuchungen aus neuen Mails: „ersetzt Flug … – ersetzen?“.

**Auswertung und Teilen**
- Statistik: Flüge, Distanz, Flugzeit, Flughäfen, Länder (antippbar), Airlines, Strecken, Flugzeugtypen, pro Jahr.
- Rückblick als Bild zum Teilen, Pünktlichkeit pro Airline, Flugzeug-Sammlung, „Meine Flüge auf dieser Strecke“.
- Entschädigung nach EU 261/2004: Einschätzung und Antragstext (Deutsch / Englisch).
- Familie & Freunde informieren: Live-Links und Statusnachricht; Flug oder Reiseplan als PDF.
- **Status-Link** (mit eigenem Push-Server): eine Seite im Browser, ohne App, in der Sprache des Empfängers –
  Zeiten mit Verspätung, Gate, Terminal, Gepäckband, Live-Karte mit Flugzeugposition sowie Höhe, Geschwindigkeit
  und Reststrecke während des Flugs. Der Link ist nicht erratbar und lässt sich wieder ungültig machen.
- **Abgleich zwischen eigenen Geräten** (mit eigenem Push-Server): Flüge, Reisen und Buchungen bleiben auf iPhone
  und iPad gleich. Dokumente und Keys werden nicht übertragen.
- Export und Import aller Flüge als JSON.
- **Diagnose-Protokoll** (Einstellungen → Daten): was die App zuletzt abgefragt und was die Quellen geantwortet
  haben, zum Teilen bei Problemen. Enthält keine Keys, Passwörter oder Mail-Inhalte.

**Sprachen:** Deutsch, Englisch, Französisch, Italienisch, Spanisch (folgt der Sprache des iPhones).

## Erste Schritte

1. App installieren (TestFlight-Einladung, oder [selbst bauen](#selbst-bauen)).
2. **Einstellungen → Flugdaten:** Datenquelle wählen und Key eintragen. Empfohlen: „Beide kombiniert“.
   Unter jedem Feld führt „So bekommst du den Key“ Schritt für Schritt durch die Anmeldung.
3. **Einstellungen → Zuhause:** Heimat-Flughafen und Heimat-Haltestelle.
4. **Einstellungen → Reisender:** Name wie auf dem Ticket (damit nur die eigenen Flüge aus Mails übernommen werden).
5. Flug hinzufügen: in der Flugliste auf **+**.
6. Optional: KI-Key für den Mail-Import, Outlook verbinden, Kalender einschalten, eigener Push-Server.

Alle Anleitungen stehen auch in der App, jeweils direkt beim betreffenden Feld.

## Keys und Dienste

| Wofür | Dienst | Kosten | Nötig? |
|---|---|---|---|
| Flugstatus, Zeiten, Zubringer | [FlightAware AeroAPI](https://www.flightaware.com/aeroapi/portal/) („Personal“) | monatliches Gratis-Guthaben, danach pro Abfrage | eine der beiden Quellen |
| Flugstatus, Gates, Flüge weit in der Zukunft | [AeroDataBox](https://rapidapi.com/aedbx-aedbx/api/aerodatabox) über RapidAPI | Gratis-Plan mit wenigen Abfragen | eine der beiden Quellen |
| Live-Position, Start, Landung | adsb.lol, airplanes.live, OpenSky | gratis, kein Key | automatisch |
| Mail-Erkennung, Reiseplan, Packliste | Claude (Anthropic) oder OpenAI | pro Nutzung, meist Rappen | optional |
| Postfach durchsuchen | Microsoft-Konto (eigene App-Registrierung) | gratis | optional |
| Wetter, Wechselkurs, ÖV | Open-Meteo, Coinbase, transport.opendata.ch | gratis, kein Key | automatisch |

**„Beide kombiniert“** nutzt FlightAware für die nächsten zwei Tage und den Live-Status, AeroDataBox für Flüge
weiter in der Zukunft und für Gate, Terminal, Check-in und Gepäckband. Fällt eine Quelle aus, springt die andere ein.

**Outlook einrichten** (einmalig, ca. 5 Min.): [entra.microsoft.com](https://entra.microsoft.com) →
App-Registrierungen → Neue Registrierung → Kontotyp „persönliche Microsoft-Konten“ → Plattform „iOS/macOS“ mit
Bundle-ID `com.nobody430.skylog` → Berechtigungen `Mail.Read`, `User.Read` → Client-ID in Skylog eintragen.
Die ausführliche Fassung steht in der App.

## Eigener Push-Server (optional)

Ohne Server aktualisiert sich Skylog, wenn die App offen ist oder iOS sie im Hintergrund laufen lässt
(„Reisemodus“). Mit einem eigenen Server kommen Mitteilungen sofort – auch bei gesperrtem iPhone – und die
Live-Aktivität aktualisiert sich von selbst.

- Läuft **gratis bei Cloudflare Workers** (oder als Docker-Container überall).
- Schreibt Mitteilungen in der Sprache des iPhones (Deutsch, Englisch, Französisch, Italienisch, Spanisch).
- Live-Daten der Status-Seite: zuerst die Gratis-Netze (nach Rufzeichen und Transponder-Kennung), dazu die
  Position, die die App selbst gerade sieht; findet sich nichts, fragt der Server für geteilte Flüge höchstens alle
  5 Min. die Position bei FlightAware ab (kostet pro Abfrage etwas vom eigenen Guthaben).
- Liefert zusätzlich die **Status-Seite** für Familie & Freunde (`/s/<zufälliger Code>`) und speichert das
  Dokument für den **Abgleich zwischen den eigenen Geräten** (`/data`, nur mit dem Server-Passwort).
- Nutzt den **eigenen** FlightAware-Key; ohne Key meldet er Start und Landung über ADS-B.
- Mitteilungen gehen über ein **Relay** des App-Herausgebers an Apple (Apple nimmt sie nur vom Herausgeber an).
  Das Relay sieht weder Keys noch Fluglisten.

Kurzfassung: Projekt forken → Cloudflare-Konto → vier Secrets im Fork
(`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SERVER_TOKEN`, `RELAY_URL`) → Workflow „Deploy push server“
starten → Adresse und Passwort in Skylog unter *Einstellungen → Echtzeit-Pushs* eintragen.

Schritt für Schritt: in der App unter *Einstellungen → Echtzeit-Pushs → So richtest du den Server ein*.
Technik und Docker: [`../server/README.md`](../server/README.md). Relay-Adresse: siehe [Haupt-README](../README.md#relay).

## Wie aktuell sind die Daten?

| Phase | Abfrage der Flugdaten |
|---|---|
| 3 Tage bis 24 h vor Abflug | alle 12 h |
| 24 h bis 4 h | alle 2 h |
| 4 h bis 75 Min. | alle 15 Min. |
| 75 Min. vor Abflug bis zum Start | alle 5 Min. (auch über die geplante Zeit hinaus, und während des Rollens) |
| in der Luft | alle 15 Min., in den letzten 40 Min. alle 5 Min. |
| nach der Landung | alle 10 Min., bis das Gepäckband bekannt ist (max. 1 h) |

Dazu kommt die Gratis-Live-Position jede Minute, sobald der Flug in der Luft ist. Fehlgeschlagene Abfragen werden
mit wachsendem Abstand wiederholt; ein aufgebrauchtes Kontingent pausiert nur die betroffene Quelle.
Mit eigenem Push-Server prüft dieser jede Minute.

## Datenschutz

- Flüge, Reisen, Buchungen, Dokumente und alle Keys liegen **nur auf dem iPhone** (Keys im Schlüsselbund bzw. in
  den App-Einstellungen). Es gibt kein Konto und keinen zentralen Server.
- Abfragen gehen direkt vom Gerät an die Dienste, deren Keys eingetragen sind.
- Für die KI-Erkennung werden die Texte der Reise-Mails an den gewählten KI-Anbieter geschickt.
- Der eigene Push-Server bekommt die anstehenden Flüge und – falls eingetragen – den FlightAware-Key.
- Mit „Geräte abgleichen“ liegen Flüge, Reisen und Buchungen zusätzlich auf dem eigenen Server.
- Ein Status-Link zeigt den betreffenden Flug jedem, der den Link hat; die Karte darauf lädt Kartenbilder von
  OpenStreetMap und die Kartenbibliothek von unpkg.com.
- Die Daten sind im normalen iPhone-Backup enthalten; zusätzlich gibt es den JSON-Export.

## Selbst bauen

Mit Mac und Xcode:

```
brew install xcodegen
cd skylog && xcodegen generate && open Skylog.xcodeproj
```

Unter *Signing & Capabilities* das eigene Team wählen. Wer eine eigene Bundle-ID nimmt, ändert sie in
`project.yml` (App, Widget, App Group) – dann braucht der Push-Server den **eigenen** Apple-Push-Schlüssel statt
des Relays (siehe `server/README.md`).

Ohne Mac: Das Projekt baut per GitHub Actions und lädt zu TestFlight hoch (siehe [Haupt-README](../README.md#build)).
Nötig ist ein Apple-Developer-Konto.

## Aufbau des Codes

| Ort | Inhalt |
|---|---|
| `Skylog/Models.swift` | Flug, Endpunkte, Status, Zubringer, Zeiten im Detail |
| `Skylog/FlightStore.swift` | Speicher, Aktualisierung nach Flugphase, Dubletten, Anschlüsse, Zubringer |
| `Skylog/FlightAware.swift`, `API.swift` | Datenquellen und die kombinierte Abfrage |
| `Skylog/LiveADSB.swift` | Gratis-Live-Daten (Start, Position, Landung) |
| `Skylog/MailAI.swift`, `OutlookMail.swift`, `MailWatcher.swift` | Mail-Import mit KI, Abgleich von Umbuchungen und Stornos |
| `Skylog/LiveFlight.swift`, `SkylogWidgets/` | Live-Aktivität und Widgets |
| `Skylog/PushClient.swift`, `../server/`, `../relay/` | eigener Push-Server und Relay |
| `Skylog/DeviceSync.swift` | Abgleich zwischen den eigenen Geräten über den eigenen Server |
| `l10n/` | Übersetzungen als JSON, Prüfwerkzeug und Generator für die `.lproj`-Dateien |
| `Skylog/Trips.swift`, `Bookings.swift`, `HotelRoute.swift`, `TripPlanner.swift` | Reisen, Buchungen, Weg zum Hotel, KI-Reiseplan |
| `Skylog/Views/` | alle Ansichten; `KeyGuides.swift` enthält die Anleitungen in der App |
| `Skylog/*.lproj/` | Übersetzungen (Schlüssel = deutscher Text) |

Flughafen-Datenbank: [mwgg/Airports](https://github.com/mwgg/Airports) (MIT, siehe `Skylog/Resources/airports-LICENSE.txt`).

## Grenzen

- **Boarding-Status** gibt es in offenen Daten nicht; „Boarding (ca.)“ ist eine Schätzung aus der Abflugzeit.
- **Gates** stammen von den Datenquellen und können falsch oder veraltet sein – es gilt die Anzeige am Flughafen.
- **Vorhersagen** (wie bei kommerziellen Apps) und Pünktlichkeits-Statistiken einzelner Flüge sind nicht enthalten;
  dafür bräuchte es teure Datenverträge.
- **Hintergrund ohne Server:** iOS entscheidet, wie oft die App laufen darf. Zuverlässig sofort geht es nur mit
  dem eigenen Push-Server.
- Die Gratis-Live-Daten sind für private, nicht-kommerzielle Nutzung gedacht.
- **Verspätungen am Flughafen** liefert FlightAware nicht für alle Flughäfen; ausserhalb der USA bleibt die
  Anzeige oft bei „keine Verspätungen“.
- **Übersetzungen** sind maschinell erstellt und automatisch auf Vollständigkeit und Platzhalter geprüft, aber
  nicht von Muttersprachlern gelesen. Korrekturen: `l10n/tr_<sprache>.json` ändern, `python3 l10n/validate.py <sprache>`
  und `python3 l10n/write_strings.py . en fr it es` ausführen.
- **Gratis-Live-Daten** stammen von freiwilligen Empfängern und decken manche Regionen dünn ab (z.B. Teile
  Asiens); ohne FlightAware-Key gibt es dort nur die geschätzte Position.
- **Airline-Namen** kommen von den Datenquellen und können veraltet sein, wenn ein Airline-Code neu vergeben
  wurde; bekannte Fälle stehen in einer kleinen Korrekturliste (`Models.swift`, `airlineNameFixes`).
- **Einheitliche Verspätungs-Skala:** unter 5 Min. pünktlich (grün), ab 5 Min. orange, ab 15 Min. rot.

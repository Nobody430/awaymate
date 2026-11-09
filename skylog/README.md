# Skylog ✈️ – eigener Flug-Tracker fürs iPhone

Native SwiftUI-App (iOS 17+), komplett ohne Abo.

## Funktionen
- Flug per Flugnummer + Datum hinzufügen (auch vergangene Flüge → Flughistorie)
- Status, Verspätung, geplante vs. erwartete/tatsächliche Zeiten (in Ortszeit des Flughafens)
- Terminal, Gate, Check-in-Schalter, Gepäckband
- Live-Position auf der Karte (OpenSky, gratis) inkl. Höhe, Speed, Kurs – sonst geschätzt entlang der Großkreisroute
- Mitteilungen bei Gate-Wechsel, neuer Abflug-/Ankunftszeit, Boarding, Start, Landung, Annullierung, Gepäckband
- Erinnerungen 3h vor Abflug, 45 Min vor Abflug, 20 Min vor Landung
- Hintergrund-Aktualisierung
- Weltkarte mit allen Flügen
- Statistik: Flüge, km, Flugzeit, Flughäfen, Länder, Airlines, Strecken, Flugzeugtypen, Diagramm pro Monat, Jahresfilter
- Sitzplatz & Notizen, Teilen, JSON-Export/-Import

## 1. API-Key holen (gratis)
1. Auf https://rapidapi.com registrieren
2. API „AeroDataBox“ suchen → Plan **Basic (0 $)** abonnieren
3. `X-RapidAPI-Key` kopieren → in der App unter *Einstellungen* einfügen

Das Gratis-Kontingent ist begrenzt, darum aktualisiert die App automatisch nur Flüge der nächsten 36 h.

## 2. App bauen
GitHub baut die App automatisch bei jedem Push (Actions → „Build Skylog iOS“).
Unter dem Run bei *Artifacts* `Skylog-ipa` herunterladen und entpacken → `Skylog.ipa`.

## 3. Aufs iPhone installieren (Windows, ohne Mac)
1. **iTunes** (Apple-Version, nicht Store) und **Sideloadly** (sideloadly.io) installieren
2. iPhone per USB anschließen, „Diesem Computer vertrauen“
3. `Skylog.ipa` in Sideloadly ziehen, Apple-ID eingeben → Start
4. iPhone: *Einstellungen → Allgemein → VPN & Geräteverwaltung* → Entwickler-App vertrauen
5. *Einstellungen → Datenschutz & Sicherheit → Entwicklermodus* einschalten (Neustart)

Mit einer kostenlosen Apple-ID läuft die App **7 Tage**, danach in Sideloadly einfach erneut installieren
(Daten bleiben erhalten; Sideloadly kann das auch automatisch per WLAN erneuern).
Mit einem bezahlten Developer-Account (99 $/Jahr) hält sie 1 Jahr.

## Mit Mac/Xcode
```
brew install xcodegen
cd skylog && xcodegen generate && open Skylog.xcodeproj
```
In Xcode unter *Signing & Capabilities* das eigene Team wählen und aufs iPhone spielen.

## E-Mail-Import
In der Flugliste auf **+ → Aus E-Mails importieren**:

- **Outlook/Hotmail/MSN durchsuchen** – einmalig einrichten (gratis, ~5 Min):
  1. https://entra.microsoft.com → *App-Registrierungen* → *Neue Registrierung*
  2. Name: `Skylog`, Kontotyp: **Konten in einem beliebigen Organisationsverzeichnis und persönliche Microsoft-Konten**
  3. Nach dem Anlegen: *Authentifizierung* → *Plattform hinzufügen* → **iOS/macOS** → Bundle-ID `com.nobody430.skylog`
     (ergibt Umleitungs-URI `msauth.com.nobody430.skylog://auth`)
  4. *API-Berechtigungen*: `Mail.Read` und `User.Read` (delegiert) – sind ohne Admin-Zustimmung nutzbar
  5. *Anwendungs-ID (Client-ID)* kopieren → in Skylog unter *Einstellungen → E-Mail-Import* einfügen
- **Mail-Text einfügen** – funktioniert mit jedem Mail-Programm (Gmail, iCloud, …)
- **PDF/Mail-Datei** – Ticket-PDF oder Bordkarte in Outlook/Mail teilen → *Skylog*

Erkannt werden Flugnummern (z. B. `LX 1612`, `U2 5147`) mit Datum in vielen Formaten
(`12.11.2026`, `12. November 2026`, `12NOV26`, `Nov 12, 2026`). Vor dem Import kannst du jeden Treffer abhaken.

## Teilen
- **Einzelner Flug:** Flugdetails → Teilen-Symbol → *Als PDF teilen* (mit Karte, Zeiten, Terminal/Gate, Sitzplatz) oder *Als Text*
- **Ganzer Reiseplan:** In der Flugliste oben links das Teilen-Symbol → alle angezeigten Flüge als ein PDF
- Booking.com, eDreams & Co.: Die Bestätigungsmails werden beim Outlook-Scan mit erkannt.

## Reisen (neu)
- **Entschädigung (EU 261/2004):** Bei ≥ 3 h Verspätung, Annullierung oder Umleitung zeigt Skylog den möglichen Betrag (250/400/600 €) und erstellt den Antrag (DE/EN) mit Name, IBAN und Buchungscode. Mitteilung direkt nach der Landung.
- **Zug & Bus:** Für Abflüge/Ankünfte in Zürich und Genf zeigt Skylog Verbindungen von/zu deiner Heimat-Haltestelle (transport.opendata.ch), inkl. Puffer vor Abflug.
- **Dokumente pro Flug:** Boardingpass, Buchung, Fotos ablegen – offline verfügbar, mit Vorschau.
- **Reisen-Tab:** Reisen werden aus deinen Flügen vorgeschlagen, inkl. Packliste und Notizen.
- **Live-Aktivität** (Sperrbildschirm + Dynamic Island): Countdown bis Abflug/Landung, Gate, Fortschritt – startet automatisch 4 h vor Abflug.
- **Widget** „Nächster Flug“ für Homescreen und Sperrbildschirm.
- **Zielinfo:** Ortszeit, Zeitverschiebung, Wetter bei Ankunft (Open-Meteo), Wechselkurs, Steckdosentyp/Spannung.
- **Reisetag-Plan:** Flughafen → Gepäck → Boarding → Abflug → Landung → Gepäckband.

Für TestFlight braucht Skylog zusätzlich die App Group `group.com.nobody430.skylog` und die Bundle-ID `com.nobody430.skylog.widgets`.
- **Flugzeug & Sitz:** Alter, Typ, Sitze, Triebwerke (auf Knopfdruck), Sitzposition (Fenster/Mitte/Gang), Sonnenseite während des Flugs.
- **Familie:** Live-Links (Flightradar24/FlightAware) zum Weitergeben, Status per WhatsApp mit einem Tipp.
- **Flughafen:** Innenpläne in Apple Karten, Lounges/Essen/Apotheke/Geld aus Apple Maps, offizielle Seiten mit Wartezeiten (ZRH, GVA, BSL).

Flughafen-Datenbank: [mwgg/Airports](https://github.com/mwgg/Airports) (MIT-Lizenz, siehe `Skylog/Resources/airports-LICENSE.txt`).

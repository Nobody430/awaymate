# iOS-Apps

Drei eigene iPhone-Apps (SwiftUI, iOS 17+), automatisch gebaut und über TestFlight verteilt.
Keine Abos, kein zentraler Dienst: Alle Keys werden in den Apps auf dem Gerät eingegeben, nichts davon steht im Code.

| App | Ordner | Inhalt |
|---|---|---|
| ✈️ **Skylog** | [`skylog/`](skylog/README.md) | Flug- und Reise-App: Live-Status, Zubringer, Mail-Import mit KI, Reisen und Hotels, Live-Aktivität, optionaler eigener Push-Server mit Status-Link (Live-Karte) für Familie & Freunde und Abgleich zwischen den eigenen Geräten. Deutsch, Englisch, Französisch, Italienisch, Spanisch. |
| 💪 **Vital** | `vital/` | Training mit KI-Coach, Ernährung, Gewicht, Medikamenten-Erinnerung |
| 💰 **Saldo** | `saldo/` | Finanzen: Apple-Pay-Erfassung, Bankimport, Budgets, Krypto |

Die ausführliche Beschreibung von Skylog – Funktionen, Keys, Push-Server, Aufbau – steht in
[`skylog/README.md`](skylog/README.md).

## Was liegt wo

| Ort | Inhalt |
|---|---|
| `skylog/`, `vital/`, `saldo/` | die Apps (je ein XcodeGen-Projekt, `project.yml`) |
| `server/` | Skylog-Push-Server (Cloudflare Workers oder Docker), siehe [`server/README.md`](server/README.md) |
| `relay/` | Relay, das Mitteilungen an Apple weiterreicht (nur für den Herausgeber der App) |
| `.github/workflows/testflight.yml` | baut alle Apps und lädt sie zu TestFlight hoch |
| `.github/workflows/server.yml` | richtet Push-Server und Relay ein |
| `.github/workflows/l10n.yml` | sammelt die übersetzbaren Texte von Skylog ein |
| `.github/scripts/` | Einrichtung von Bundle-IDs, Zertifikat und Profilen über die App-Store-Connect-API |

## Build

- Jeder Push, der eine App betrifft, baut alle Apps und lädt sie zu TestFlight hoch.
- Benötigte Repository-Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`
  (App-Store-Connect-API-Key mit Rolle Admin).
- Bundle-IDs, Capabilities, Zertifikat und Profile werden über die API automatisch eingerichtet.
- Die Build-Nummer ist `100 + Laufnummer` des Workflows.
- Wer das Projekt forkt und selbst verteilen will, braucht ein eigenes Apple-Developer-Konto, eigene Bundle-IDs
  (in den `project.yml`) und eigene App-Einträge in App Store Connect.

## Skylog: eigener Push-Server (optional)

Skylog funktioniert ohne Server. Wer sofortige Mitteilungen und eine sich selbst aktualisierende Live-Aktivität
will, betreibt einen eigenen kleinen Server mit den eigenen Flugdaten-Keys – gratis bei Cloudflare.

- Anleitung für Nutzer: in der App unter *Einstellungen → Echtzeit-Pushs → So richtest du den Server ein*
- Überblick: [`skylog/README.md`](skylog/README.md#eigener-push-server-optional)
- Technik, Secrets, Docker: [`server/README.md`](server/README.md)

### Relay

Apple nimmt Mitteilungen für eine App nur vom Herausgeber an. Darum gibt es ein kleines Relay (`relay/`), das
fertige Mitteilungen von den Servern der Nutzer an Apple weiterreicht. Es sieht weder Flugdaten-Keys noch Fluglisten
und sendet ausschliesslich an die Skylog-App.

**Adresse des Relays (`RELAY_URL`):** `https://skylog-relay.ranobody.workers.dev`

Secrets des Herausgebers für Relay und eigenen Server: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`APNS_KEY_ID`, `APNS_KEY_P8`, `APPLE_TEAM_ID`, `SERVER_TOKEN`.

## Sicherheit

- Keine Keys, Tokens oder Passwörter im Repository; alles liegt in GitHub-Secrets oder auf dem Gerät.
- Wer einen Fehler mit Sicherheitsbezug findet, meldet ihn bitte über ein privates GitHub-Advisory statt öffentlich.

# iOS-Apps

Drei eigene iPhone-Apps (SwiftUI, iOS 17+), automatisch gebaut und via TestFlight verteilt.

| App | Ordner | Inhalt |
|---|---|---|
| ✈️ **Skylog** | `skylog/` | Flug- und Reise-App: Live-Status, Mail-Import mit KI, Entschädigung, ÖV, Live-Aktivität |
| 💪 **Vital** | `vital/` | Training mit KI-Coach, Ernährung, Gewicht, PrEP |
| 💰 **Saldo** | `saldo/` | Finanzen: Apple-Pay-Erfassung, Bankimport, Budgets, Krypto |

## Build
- Jeder Push baut alle Apps und lädt sie zu TestFlight hoch (`.github/workflows/testflight.yml`).
- Benötigte Repository-Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID` (App Store Connect API, Rolle Admin).
- Bundle-IDs, Capabilities, Zertifikat und Profile werden über die API automatisch eingerichtet.

Keine API-Keys im Code – alle Keys werden in den Apps auf dem Gerät eingegeben.

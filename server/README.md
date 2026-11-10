# Skylog Push-Server

Kleiner Server ohne Abhängigkeiten. Er beobachtet die anstehenden Flüge, die die App ihm meldet, und schickt
Echtzeit-Mitteilungen (Gate, Verspätung, Boarding ca., Gate verlassen, gestartet, gelandet, Gepäckband) sowie
Updates für die Live-Aktivität.

- **Quellen:** FlightAware AeroAPI (der Key des Nutzers, kommt aus der App) und kostenlose ADS-B-Netze.
- **Mitteilungen:** über das Relay des App-Herausgebers (`RELAY_URL`) oder – wer die App selbst baut – direkt
  an Apple mit dem eigenen Schlüssel (`APNS_KEY_ID`, `APNS_KEY_P8`, `APPLE_TEAM_ID`, `APNS_TOPIC`).

## Aufbau

| Datei | Zweck |
|---|---|
| `core.mjs` | die ganze Logik, plattformunabhängig |
| `apns.mjs` | Mitteilungen signieren und senden (direkt oder via Relay) |
| `worker.mjs` + `wrangler.toml` | Cloudflare Workers (gratis; Cron jede Minute, Zustand in einem Durable Object) |
| `server.mjs` + `Dockerfile` | Node 20 / Docker (Fly.io, VPS, Raspberry Pi …), Zustand in `/data/state.json` |
| `../relay/` | das Relay des Herausgebers (Cloudflare Worker) |

## Deployment

`.github/workflows/server.yml` richtet ein, wofür Secrets vorhanden sind.

**Eigener Server bei Cloudflare (Bastler, im eigenen Fork):**

| Secret | Inhalt |
|---|---|
| `CLOUDFLARE_API_TOKEN` | Cloudflare → Profil → API Tokens → Vorlage „Edit Cloudflare Workers“ |
| `CLOUDFLARE_ACCOUNT_ID` | Cloudflare → Workers & Pages → Account ID |
| `SERVER_TOKEN` | frei gewähltes langes Passwort (auch in der App eintragen) |
| `RELAY_URL` | Adresse des Relays, siehe Haupt-README |
| `FLIGHTAWARE_KEY` | optional; sonst nimmt der Server den Key aus der App |

**Relay (nur der Herausgeber der App):** zusätzlich `APNS_KEY_ID`, `APNS_KEY_P8`, `APPLE_TEAM_ID`.
Sind diese gesetzt, sendet auch der eigene Server direkt an Apple.

**Docker statt Cloudflare:** `docker build -t skylog-push server && docker run -p 8080:8080 -v skylog:/data -e SERVER_TOKEN=… -e RELAY_URL=… skylog-push`
(oder Fly.io mit `FLY_API_TOKEN` und `FLY_APP_NAME`).

## Schnittstelle

`GET /health` · `POST /sync` · `POST /test` (jeweils mit `Authorization: Bearer <SERVER_TOKEN>`).
Relay: `GET /health` · `POST /push` mit `{deviceToken, payload, type}`; sendet ausschliesslich an die Skylog-App.

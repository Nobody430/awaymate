# Skylog Push-Server

Kleiner Node-Server ohne Abhängigkeiten. Beobachtet die anstehenden Flüge, die die App meldet, und schickt
Echtzeit-Pushs (Gate, Verspätung, Boarding ca., Gate verlassen, gestartet, gelandet, Gepäckband) sowie
Live-Aktivitäts-Updates via APNs.

Quellen: FlightAware AeroAPI (optional, sparsam) + kostenlose ADS-B-Netze (adsb.lol, airplanes.live).

Deployment: `.github/workflows/server.yml` (Fly.io). Benötigte GitHub-Secrets:

| Secret | Inhalt |
|---|---|
| `FLY_API_TOKEN` | Fly.io → Account → Access Tokens |
| `FLY_APP_NAME` | weltweit eindeutiger Name, z.B. `skylog-push-n430` |
| `SERVER_TOKEN` | frei gewähltes langes Passwort (auch in der App eintragen) |
| `APNS_KEY_ID` / `APNS_KEY_P8` | Apple Developer → Keys → Apple Push Notifications service |
| `APPLE_TEAM_ID` | bereits vorhanden |
| `FLIGHTAWARE_KEY` | optional, für Gate/Verspätung |

Endpunkte: `GET /health`, `POST /sync`, `POST /test` (mit `Authorization: Bearer <SERVER_TOKEN>`).

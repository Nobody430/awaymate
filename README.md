# Awaymate ✈️

A flight and travel companion for iPhone (SwiftUI, iOS 17+). No subscription and no central service: everyone uses
their own API keys and all data stays on the device. If you like, you can also run your own small push server.

The app is available in German, English, French, Italian and Spanish.

> **About the name:** the app used to be called *Skylog*. Folders, the Xcode target, the bundle ID
> (`com.nobody430.skylog`) and the server addresses (`skylog-push`, `skylog-relay`) keep the old name so that
> existing installations and data keep working.

- [Features](#features)
- [Getting started](#getting-started)
- [Keys and services](#keys-and-services)
- [Your own push server](#your-own-push-server-optional)
- [How fresh is the data?](#how-fresh-is-the-data)
- [Privacy](#privacy)
- [Building it yourself](#building-it-yourself)
- [Code layout](#code-layout)
- [Limits](#limits)
- [Build](#build)
- [Relay](#relay)
- [Security](#security)

## Features

**Flights**
- Add by flight number and date, by hand, from emails (Outlook mailbox, pasted text, PDF) or from the iPhone
  calendar (entries with a flight number). A flight number with several legs a day (e.g. ZRH→GRU and GRU→EZE)
  shows every leg to choose from.
- Status, delay, scheduled / expected / actual times, always in the airport's local time.
- Terminal, gate, check-in desk, baggage belt. Gates are checked against a second source shortly before
  departure; a note appears if the sources disagree.
- "Times in detail": left the gate, taxi, take-off, landing, at the gate, flight time.
- "Where is my plane?": the inbound flight and the flights before it, with an estimate of whether there is enough time.
- Connection card with transfer time and a warning when it gets tight.
- Live position on the map, estimated arrival from position and speed. Implausible positions (far off the route,
  or the 0°/0° placeholder) are not drawn; the plane is then shown at its estimated place while altitude and
  speed stay visible.
- A separate status **"Taxiing"** between leaving the gate and take-off; "Departed" only after lift-off.
- Change log per flight (gate, times, status).
- "Manage booking": copies the booking code and opens a search for the airline's booking page.

**Notifications and lock screen**
- Gate change, new departure time (including creeping delays), inbound aircraft departed / landed / late,
  take-off, landing, baggage belt, cancellation.
- Reminders: 3 h and 45 min before departure, 20 min before landing, "on to the hotel", "time to leave for the airport".
- Live Activity (lock screen and Dynamic Island) with countdown, gate, delay per airport and inbound aircraft.
- Widgets: home screen (small, medium) and lock screen (line above the clock, block below it).

**Trips**
- Trips are suggested from upcoming flights; hotels, rental cars and trains from emails are assigned to them.
- One timeline per trip: flight, stay, flight, stay … with the way from the last stop in between (airport → hotel,
  hotel → hotel, hotel → airport) including public transport, taxi and walking times. A tap offers the route in
  Apple Maps, an Uber request with pickup and destination filled in, and Bolt, Cabify and FREE NOW.
- Stays and other bookings can be added, edited and deleted by hand; each has a "manage booking" link.
- Trip length in days and nights (for counting medication and clothes).
- Travel-day plan (be at the airport, bag drop, boarding, departure, landing, baggage) with an automatic buffer.
- Conditions at the departure airport: weather at departure time; reported delays at the airport (minor / major, with reason).
- Destination info: local time, time difference, weather on arrival, exchange rate, power sockets.
- Train and bus from and to your home stop (Switzerland).
- AI trip plan day by day and a personal packing list (optionally with notes from an Obsidian vault). The packing
  list has its own page.
- Documents per flight (boarding pass, booking); on the travel day they appear on top as "Open boarding pass".
  PDFs, images and Wallet passes can be shared to Awaymate from other apps; a shared PDF can also be read as a booking.
- Calendar sync for flights and hotels (optional).
- Re-bookings from new emails: "replaces flight … – replace?".
- A button checks the mailbox right away for new flights and bookings; it can also re-read the last 30 days.

**Statistics and sharing**
- Statistics: flights, distance, flight time, airports, countries (tappable), airlines, routes, aircraft types, per year.
- Year in review as an image to share, punctuality per airline, aircraft collection, "my flights on this route".
- Compensation under EU 261/2004: assessment and claim text (German / English).
- Tell family & friends: status message and live links; flight or trip plan as a PDF.
- **Status link** (with your own push server): a page in the browser, no app needed, in the recipient's language:
  times with delay, gate, terminal, baggage belt, live map with the plane's position, and altitude, speed and
  remaining distance during the flight. The link cannot be guessed and can be revoked.
- **Trip link** (with your own push server): one page for a whole trip with all flights and stays in order, where
  the traveller is right now, and the live page for every flight the server is watching.
- **Sync between your own devices** (with your own push server): flights, trips and bookings stay the same on
  iPhone and iPad. Documents and keys are not transferred.
- Export and import of all flights as JSON.
- **Diagnostic log** (Settings → Data): what the app asked last and what the sources answered, to share when
  something goes wrong. Contains no keys, passwords or email content.

**Languages:** German, English, French, Italian, Spanish (follows the iPhone's language).

## Getting started

1. Install the app (TestFlight invitation, or [build it yourself](#building-it-yourself)).
2. **Settings → Flight data:** choose the data source and enter your key. Recommended: "Both combined".
   Below each field, "How to get the key" walks you through the sign-up step by step.
3. **Settings → Home:** home airport and home stop.
4. **Settings → Traveller:** your name as on the ticket (so that only your own flights are taken from emails).
5. Add a flight: tap **+** in the flight list.
6. Optional: AI key for the email import, connect Outlook, switch on the calendar, your own push server.

All guides are also in the app, right next to the field they belong to.

## Keys and services

| What for | Service | Cost | Needed? |
|---|---|---|---|
| Flight status, times, inbound aircraft | [FlightAware AeroAPI](https://www.flightaware.com/aeroapi/portal/) ("Personal") | free monthly credit, then per query | one of the two sources |
| Flight status, gates, flights far in the future | [AeroDataBox](https://rapidapi.com/aedbx-aedbx/api/aerodatabox) via RapidAPI | free plan with few queries | one of the two sources |
| Live position, take-off, landing | adsb.lol, airplanes.live, OpenSky | free, no key | automatic |
| Email recognition, trip plan, packing list | Claude (Anthropic) or OpenAI | per use, usually cents | optional |
| Searching the mailbox | Microsoft account (your own app registration) | free | optional |
| Weather, exchange rate, public transport | Open-Meteo, Coinbase, transport.opendata.ch | free, no key | automatic |

**"Both combined"** uses FlightAware for the next two days and the live status, AeroDataBox for flights further
ahead and for gate, terminal, check-in and baggage belt. If one source fails, the other steps in.

**AI credit:** the AI is used for reading new travel emails (flights, hotels, rental cars, trains), recognising
shared PDFs, the trip plan and the personal packing list. The background mail check only reads new emails that look
like travel; without such emails it costs nothing. Without an AI key only flights are recognised, for free.

**Setting up Outlook** (once, about 5 min): [entra.microsoft.com](https://entra.microsoft.com) →
App registrations → New registration → account type "personal Microsoft accounts" → platform "iOS/macOS" with
bundle ID `com.nobody430.skylog` → permissions `Mail.Read`, `User.Read` → enter the client ID in Awaymate.
The detailed version is in the app.

## Your own push server (optional)

Without a server, Awaymate updates while the app is open or when iOS lets it run in the background
("travel mode"). With your own server, notifications arrive at once, even on a locked iPhone, and the Live
Activity updates itself.

- Runs **for free on Cloudflare Workers** (or as a Docker container anywhere).
- Writes notifications in the iPhone's language (German, English, French, Italian, Spanish).
- Live data for the status page: first the free networks (by callsign, transponder code and registration), plus
  the position the app itself currently sees; if nothing is found, the server asks FlightAware for the position
  of shared flights at most every 5 min (each query costs a little of your own credit).
- Also serves the **status page** (`/s/<random code>`) and the **trip page** (`/t/<random code>`) for family &
  friends, and stores the document for the **sync between your own devices** (`/data`, only with the server password).
- Uses **your own** FlightAware key; without a key it reports take-off and landing via ADS-B.
- Notifications go to Apple through a **relay** run by the app's publisher (Apple only accepts them from the
  publisher). The relay sees neither keys nor flight lists.

In short: fork the project → Cloudflare account → four secrets in your fork
(`CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `SERVER_TOKEN`, `RELAY_URL`) → run the workflow
"Deploy push server" → enter address and password in Awaymate under *Settings → Real-time pushes*.

Step by step: in the app under *Settings → Real-time pushes → How to set up the server*.
Technical details and Docker: [`server/README.md`](server/README.md). Relay address: see [Relay](#relay).

## How fresh is the data?

| Phase | Flight data is queried |
|---|---|
| more than 24 h before departure | every 12 h |
| 24 h to 4 h | every 2 h |
| 4 h to 75 min | every 15 min |
| 75 min before departure until take-off | every 5 min (also past the scheduled time, and while taxiing) |
| in the air | every 15 min, every 5 min in the last 40 min |
| after landing | every 10 min until the baggage belt is known (max. 1 h) |

On top of that comes the free live position every minute once the flight is airborne. Failed queries are retried
with growing intervals; a used-up quota only pauses the source concerned. A typical flight needs about 15–40 paid
queries. With your own push server, the server checks every minute.

## Privacy

- Flights, trips, bookings, documents and all keys are stored **only on the iPhone** (keys in the keychain or in
  the app settings). There is no account and no central server.
- Queries go directly from the device to the services whose keys you entered.
- For AI recognition, the text of travel emails is sent to the AI provider you chose.
- Your own push server receives the upcoming flights and, if entered, your FlightAware key.
- With "sync devices", flights, trips and bookings are also stored on your own server.
- A status link shows the flight to anyone who has the link; a trip link shows all flights and the names of the
  stays of that trip. The map loads map tiles from OpenStreetMap and the map library from unpkg.com.
- The data is part of the normal iPhone backup; there is also the JSON export.

## Building it yourself

With a Mac and Xcode:

```
brew install xcodegen
cd skylog && xcodegen generate && open Skylog.xcodeproj
```

Choose your own team under *Signing & Capabilities*. If you use your own bundle ID, change it in `project.yml`
(app, widget, app group); the push server then needs **your own** Apple push key instead of the relay
(see `server/README.md`).

Without a Mac: the project builds with GitHub Actions and uploads to TestFlight (see [Build](#build)).
You need an Apple Developer account.

## Code layout

Paths are relative to the folder `skylog/` (the app) unless stated otherwise. The source texts in the code are
German; the other languages are generated from `l10n/`.

| Where | What |
|---|---|
| `Skylog/Models.swift` | flight, endpoints, status, inbound aircraft, times in detail |
| `Skylog/FlightStore.swift` | storage, refresh by flight phase, duplicates, connections, inbound aircraft |
| `Skylog/FlightAware.swift`, `API.swift` | data sources and the combined query |
| `Skylog/LiveADSB.swift` | free live data (take-off, position, landing) |
| `Skylog/MailAI.swift`, `OutlookMail.swift`, `MailWatcher.swift` | email import with AI, re-bookings and cancellations |
| `Skylog/LiveFlight.swift`, `SkylogWidgets/` | Live Activity and widgets |
| `Skylog/PushClient.swift`, `/server/`, `/relay/` | your own push server and the relay |
| `Skylog/DeviceSync.swift` | sync between your own devices through your own server |
| `Skylog/CalendarSync.swift` | write flights and hotels to the calendar; import flights from the calendar |
| `Skylog/DiagLog.swift` | diagnostic log on the device |
| `Skylog/Trips.swift`, `Bookings.swift`, `HotelRoute.swift`, `TripPlanner.swift` | trips, bookings, way to the hotel, AI trip plan |
| `Skylog/Views/` | all views; `TripTimeline.swift` (trip timeline, legs, trip link), `BookingManage.swift` (booking editor, manage links), `KeyGuides.swift` (the guides in the app) |
| `Skylog/*.lproj/` | translations (key = German text) |
| `l10n/` | translations as JSON, a checker and the generator for the `.lproj` files |
| `design/icon.svg` | vector source of the app icon |

Airport database: [mwgg/Airports](https://github.com/mwgg/Airports) (MIT, see `Skylog/Resources/airports-LICENSE.txt`).

## Limits

- **Boarding status** does not exist in open data; "Boarding (est.)" is an estimate from the departure time.
- **Gates** come from the data sources and can be wrong or outdated; the display at the airport is what counts.
- **Predictions** (as in commercial apps) and punctuality statistics of individual flights are not included; they
  would need expensive data contracts.
- **Background without a server:** iOS decides how often the app may run. Instant updates are only reliable with
  your own push server.
- The free live data is meant for private, non-commercial use and comes from volunteer receivers; some regions
  are thinly covered (e.g. parts of Asia). Without a FlightAware key there is only the estimated position there.
- **Airport delays** are not provided by FlightAware for all airports; outside the USA the display often stays at
  "no delays".
- **Ride apps:** only Uber gets pickup and destination filled in. Bolt, Cabify and FREE NOW are opened with the
  destination address on the clipboard.
- **Manage booking:** airlines have no common link format, so the app opens a web search for the airline's page.
- **Translations** are machine-made and checked automatically for completeness and placeholders, but not read by
  native speakers. To correct one: edit `l10n/tr_<language>.json`, then run `python3 l10n/validate.py <language>`
  and `python3 l10n/write_strings.py . en fr it es`.
- **Airline names** come from the data sources and can be outdated when an airline code was reassigned; known
  cases are in a small correction list (`Models.swift`, `airlineNameFixes`).
- **One delay scale:** under 5 min on time (green), from 5 min orange, from 15 min red.

## Build

- Every push that touches the folder `skylog/` builds the app and uploads it to TestFlight
  (`.github/workflows/testflight.yml`). Changes to `server/` or `relay/` only redeploy the server.
- Required repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `APPLE_TEAM_ID`
  (App Store Connect API key with the Admin role).
- Bundle IDs, capabilities, certificate and profiles are set up through the API (`.github/scripts/`).
- The build number is `100 + run number` of the workflow.
- If you fork the project and want to distribute it yourself, you need your own Apple Developer account, your own
  bundle IDs (in `skylog/project.yml` and `.github/scripts/`) and your own app record in App Store Connect.

| Where | What |
|---|---|
| `skylog/` | the app (XcodeGen project, `project.yml`), widgets, translations |
| `server/` | push server (Cloudflare Workers or Docker), see [`server/README.md`](server/README.md) |
| `relay/` | relay that passes notifications on to Apple (only for the app's publisher) |
| `.github/workflows/` | `testflight.yml` (app), `server.yml` (server and relay), `l10n.yml` (collect texts), `ios.yml` (unsigned test build) |

## Relay

Apple only accepts notifications for an app from its publisher. That is why there is a small relay (`relay/`) that
passes finished notifications from users' servers on to Apple. It sees neither flight-data keys nor flight lists
and only sends to the Awaymate app.

**Relay address (`RELAY_URL`):** `https://skylog-relay.ranobody.workers.dev`

Publisher's secrets for the relay and the publisher's own server: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`,
`APNS_KEY_ID`, `APNS_KEY_P8`, `APPLE_TEAM_ID`, `SERVER_TOKEN`.

## Security

- No keys, tokens or passwords in the repository; everything is in GitHub secrets or on the device.
- If you find a security-related bug, please report it through a private GitHub advisory instead of publicly.

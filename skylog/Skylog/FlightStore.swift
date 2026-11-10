import Foundation
import Observation

@MainActor
@Observable
final class FlightStore {
    static let shared = FlightStore()

    private(set) var flights: [Flight] = []
    var isRefreshing = false
    var lastError: String?

    private let fileURL = URL.documentsDirectory.appending(path: "flights.json")
    private let pendingURL = URL.documentsDirectory.appending(path: "pending.json")

    /// Flights found in new mails, waiting for the user's confirmation.
    private(set) var pending: [Flight] = []

    /// Keys ("LX92|2026-11-13") of suggestions the user ignored.
    private var ignoredKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "ignoredMailFlights") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "ignoredMailFlights") }
    }

    private static func key(_ f: Flight) -> String { normalizedNumber(f.number) + "|" + f.date }

    /// Adds a suggestion; returns false if it was ignored before or already exists.
    @discardableResult
    func suggest(_ f: Flight) -> Bool {
        let k = Self.key(f)
        guard !ignoredKeys.contains(k), !pending.contains(where: { Self.key($0) == k }),
              !flights.contains(where: { Self.key($0) == k }) else { return false }
        pending.append(f)
        savePending()
        return true
    }

    func acceptPending(_ id: UUID) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        var f = pending.remove(at: i)
        savePending()
        // a re-booking replaces the old flight
        if let old = f.replacesID { delete([old]) }
        f.replacesID = nil
        add(f)
    }

    /// Stored upcoming flight that a new flight from a re-booking mail replaces:
    /// same booking code, not the same flight, same route or same origin/destination within 2 days.
    func rebookedFlight(for new: Flight, stillBooked: Set<String>) -> Flight? {
        guard let ref = new.bookingReference, !ref.isEmpty else { return nil }
        return flights.first { old in
            guard !old.isPast, old.bookingReference == ref || old.notes.uppercased().contains(ref.uppercased()), !Self.isSameFlight(old, new),
                  !stillBooked.contains(Self.normalizedNumber(old.number) + "|" + old.date) else { return false }
            let days = abs(old.sortDate.timeIntervalSince(new.sortDate)) / 86400
            let sameFrom = old.departure.code == new.departure.code, sameTo = old.arrival.code == new.arrival.code
            return (sameFrom && sameTo && days <= 3) || ((sameFrom || sameTo) && days <= 2)
        }
    }

    // MARK: Connections

    /// The next own flight leaving from this flight's arrival airport within 24 h.
    func connection(after f: Flight) -> Flight? {
        guard let arr = f.arrival.best ?? f.arrival.scheduled else { return nil }
        return flights.filter { o in
            guard o.id != f.id, o.departure.code == f.arrival.code, o.normalizedStatus != .canceled,
                  let dep = o.departure.best ?? o.departure.scheduled else { return false }
            return dep > arr.addingTimeInterval(-3 * 3600) && dep < arr.addingTimeInterval(24 * 3600)
                && (o.departure.scheduled ?? dep) > (f.departure.scheduled ?? arr)
        }
        .min { ($0.departure.best ?? $0.sortDate) < ($1.departure.best ?? $1.sortDate) }
    }

    /// Minutes between landing and the connecting departure (can be negative).
    static func layoverMinutes(_ f: Flight, _ next: Flight) -> Int? {
        guard let arr = f.arrival.best, let dep = next.departure.best else { return nil }
        return Int(dep.timeIntervalSince(arr) / 60)
    }

    /// Warns when a delay eats up the connection time (once per 15-minute step).
    private func checkConnection(_ id: UUID, notify: Bool) {
        guard var f = flight(id), !f.normalizedStatus.isFinal, let next = connection(after: f),
              let layover = Self.layoverMinutes(f, next), let planned = f.arrival.scheduled.flatMap({ s in
                  next.departure.scheduled.map { Int($0.timeIntervalSince(s) / 60) } }) else { return }
        guard layover < 75, layover <= planned - 15, layover <= (f.warnedLayover ?? Int.max) - 15 else { return }
        f.warnedLayover = layover
        let text = layover < 0 ? "Anschluss \(next.number) wird voraussichtlich verpasst"
            : "Nur noch \(layover) Min. zum Umsteigen auf \(next.number) in \(f.arrival.code)"
        f.log(text)
        update(f)
        if notify && Settings.notifyChanges {
            Notifier.post(id: "\(id)-connection", title: "\(f.number): Anschluss wird knapp",
                          body: text + " (geplant waren \(planned) Min.). Sprich früh mit der Crew oder dem Transfer-Schalter.")
        }
    }

    func ignorePending(_ id: UUID) {
        guard let i = pending.firstIndex(where: { $0.id == id }) else { return }
        let f = pending.remove(at: i)
        ignoredKeys.insert(Self.key(f))
        savePending()
    }

    private func savePending() {
        try? Self.encoder.encode(pending).write(to: pendingURL, options: .atomic)
    }

    init() {
        load()
        if let data = try? Data(contentsOf: pendingURL), let p = try? Self.decoder.decode([Flight].self, from: data) { pending = p }
    }

    // MARK: Queries

    var upcoming: [Flight] { flights.filter { !$0.isPast }.sorted { $0.sortDate < $1.sortDate } }
    var past: [Flight] { flights.filter { $0.isPast }.sorted { $0.sortDate > $1.sortDate } }

    func flight(_ id: UUID) -> Flight? { flights.first { $0.id == id } }

    /// Duplicates among the stored flights (keeps the best entry of each group).
    var duplicates: [Flight] {
        var keep: [Flight] = []
        var dupes: [Flight] = []
        for f in flights.sorted(by: { Self.quality($0) > Self.quality($1) }) {
            if keep.contains(where: { Self.isSameFlight($0, f) }) { dupes.append(f) } else { keep.append(f) }
        }
        return dupes
    }

    @discardableResult
    func removeDuplicates() -> Int {
        let ids = duplicates.map(\.id)
        delete(ids)
        return ids.count
    }

    func contains(number: String, date: Date) -> Bool {
        let d = Fmt.apiDate.string(from: date)
        let n = Self.normalizedNumber(number)
        return flights.contains { $0.date == d && Self.normalizedNumber($0.number) == n }
    }

    // MARK: Mutations

    /// "lx 092" → "LX92"
    nonisolated static func normalizedNumber(_ n: String) -> String {
        let t = n.replacingOccurrences(of: " ", with: "").uppercased()
        guard t.count > 2 else { return t }
        let digits = t.dropFirst(2).drop { $0 == "0" }
        return String(t.prefix(2)) + (digits.isEmpty ? "0" : String(digits))
    }

    /// Same flight: same number + date, or a codeshare (same route, departure within 60 min / same day without times).
    static func isSameFlight(_ a: Flight, _ b: Flight) -> Bool {
        if normalizedNumber(a.number) == normalizedNumber(b.number) && a.date == b.date { return true }
        guard a.departure.code == b.departure.code, a.arrival.code == b.arrival.code,
              a.departure.code != "???", a.arrival.code != "???" else { return false }
        if let da = a.departure.scheduled, let db = b.departure.scheduled { return abs(da.timeIntervalSince(db)) < 3600 }
        return a.date == b.date
    }

    /// Prefer the entry with live data, then with times.
    private static func quality(_ f: Flight) -> Int {
        (f.lastUpdated != nil ? 2 : 0) + (f.departure.scheduled != nil ? 1 : 0)
    }

    func add(_ flight: Flight) {
        var f = flight
        if let i = flights.firstIndex(where: { Self.isSameFlight($0, f) }) {
            guard Self.quality(f) >= Self.quality(flights[i]) else { return }   // keep the better existing entry
            f.id = flights[i].id
            f.notes = flights[i].notes.isEmpty ? f.notes : flights[i].notes
            f.seat = flights[i].seat
            flights[i] = f
        } else {
            flights.append(f)
        }
        save()
        Notifier.scheduleReminders(for: f)
    }

    func update(_ flight: Flight) {
        guard let i = flights.firstIndex(where: { $0.id == flight.id }) else { return }
        flights[i] = flight
        save()
        Task { await LiveFlight.update(flight) }
    }

    func delete(_ ids: [UUID]) {
        for id in ids { if let f = flight(id) { Notifier.cancelReminders(for: f) } }
        flights.removeAll { ids.contains($0.id) }
        for id in ids { attempts[id] = nil; inboundAttempts[id] = nil; positionQueries[id] = nil }
        save()
    }

    /// Flights without times and without resolvable airports (typically false matches from mail import).
    var incomplete: [Flight] {
        flights.filter { f in
            f.departure.scheduled == nil && f.departure.best == nil &&
            (f.departure.coordinate == nil || f.arrival.coordinate == nil)
        }
    }

    @discardableResult
    func removeIncomplete() -> Int {
        let ids = incomplete.map(\.id)
        delete(ids)
        return ids.count
    }

    func deleteAll() {
        flights.forEach { Notifier.cancelReminders(for: $0) }
        flights = []
        save()
    }

    // MARK: Refresh

    /// Failed refreshes back off (5, 10, 20 … 60 min) instead of being retried every minute.
    @ObservationIgnored private var attempts: [UUID: (last: Date, fails: Int)] = [:]
    @ObservationIgnored private var inFlight: Set<UUID> = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var inboundAttempts: [UUID: Date] = [:]
    @ObservationIgnored private var positionQueries: [UUID: Date] = [:]
    @ObservationIgnored private var ratePausedUntil = Date.distantPast

    /// Picks the right record: same route, not cancelled if possible, closest to the known departure time.
    private static func pick(_ results: [Flight], for cur: Flight) -> Flight? {
        var c = results.filter { $0.departure.code == cur.departure.code }
        if c.isEmpty { c = results }
        let sameArr = c.filter { $0.arrival.code == cur.arrival.code }
        if !sameArr.isEmpty { c = sameArr }
        let alive = c.filter { $0.normalizedStatus != .canceled }
        if !alive.isEmpty { c = alive }
        guard let ref = cur.departure.scheduled else { return c.first }
        return c.min { abs(($0.departure.scheduled ?? .distantFuture).timeIntervalSince(ref)) < abs(($1.departure.scheduled ?? .distantFuture).timeIntervalSince(ref)) }
    }

    func refresh(_ id: UUID, notify: Bool = true) async throws {
        guard let before = flight(id), !inFlight.contains(id) else { return }
        inFlight.insert(id)
        defer { inFlight.remove(id) }
        let date = Fmt.apiDate.date(from: before.date) ?? before.sortDate
        let results: [Flight]
        do {
            results = try await FlightData.search(number: before.number, date: date, stored: before)
        } catch {
            attempts[id] = (Date(), (attempts[id]?.fails ?? 0) + 1)
            throw error
        }
        attempts[id] = nil
        // The flight may have changed (ADS-B, notes, seat) or been deleted while we were waiting
        guard let cur = flight(id), let picked = Self.pick(results, for: cur) else { return }
        var new = FlightData.merge(picked, with: cur)
        new.id = cur.id
        new.number = cur.number          // keep the booked (codeshare) number
        new.notes = cur.notes
        new.seat = cur.seat
        new.date = cur.date
        new.inbound = cur.inbound
        new.lastUpdated = Date()
        // No fresh airport data this time: keep the airport's gate instead of flipping back to the other source's
        if picked.adbGate == nil, let g = cur.adbGate, new.departure.runway == nil {
            new.gateConflict = (picked.departure.gate != nil && picked.departure.gate != g) ? picked.departure.gate : nil
            new.departure.gate = g
        }

        // Never fall back behind what live data already detected (takeoff / landing)
        let curStatus = cur.normalizedStatus, newStatus = new.normalizedStatus
        if (curStatus == .arrived || cur.arrival.runway != nil) && !newStatus.isFinal {
            new.status = "Arrived"
            new.arrival.runway = new.arrival.runway ?? cur.arrival.runway
            new.departure.runway = new.departure.runway ?? cur.departure.runway
        } else if (curStatus.isAirborne || cur.departure.runway != nil) && !newStatus.isAirborne && !newStatus.isFinal {
            new.status = cur.status
            new.departure.runway = new.departure.runway ?? cur.departure.runway
        }

        // Delay notifications compare against the last time we told the user (catches creeping delays)
        let reference = cur.lastNotifiedDeparture ?? cur.departure.best
        new.lastNotifiedDeparture = reference
        if let r = reference, let n = new.departure.best, abs(n.timeIntervalSince(r)) >= 5 * 60 {
            new.lastNotifiedDeparture = n
        }

        let changes = Notifier.changes(old: cur, new: new)
        for change in changes {
            let title = change.title.replacingOccurrences(of: "\(new.number): ", with: "").replacingOccurrences(of: "\(new.number) ", with: "")
            new.log(title.prefix(1).uppercased() + String(title.dropFirst()) + " – " + change.body)
        }
        // with an own push server, the server sends these – don't notify twice
        if notify && Settings.notifyChanges && !PushClient.isConfigured {
            for change in changes {
                Notifier.post(id: "\(new.id)-\(change.title)", title: change.title, body: change.body)
            }
        }
        update(new)
        Notifier.scheduleReminders(for: new)
        HotelRoute.scheduleReminders(for: new, flights: flights)
        checkConnection(id, notify: notify)
    }

    /// Refresh interval depending on the flight phase:
    /// >24 h: 12 h · 24–4 h: 2 h · 4 h–75 min: 15 min · from 75 min before departure until takeoff: 5 min
    /// (also past the planned time, so delays show up right away) · in the air: 15 min, last 40 min 5 min
    /// · after landing every 10 min until the baggage belt is known (max. 1 h).
    static func refreshInterval(departure dep: Date, arrival arr: Date, now: Date, flight f: Flight) -> TimeInterval {
        let status = f.normalizedStatus
        if status == .canceled || status == .diverted { return 2 * 3600 }
        if status == .arrived || f.arrival.runway != nil {
            if now.timeIntervalSince(arr) > 3600 { return .infinity }
            if f.arrival.baggageBelt != nil, let last = f.lastUpdated, last > arr { return .infinity }
            return 10 * 60
        }
        if f.isInAir || f.departure.runway != nil {
            return arr.timeIntervalSince(now) < 40 * 60 ? 5 * 60 : 15 * 60
        }
        let toDep = dep.timeIntervalSince(now)
        if toDep > 24 * 3600 { return 12 * 3600 }
        if toDep > 4 * 3600 { return 2 * 3600 }
        if toDep > 75 * 60 { return 15 * 60 }
        if toDep < -3 * 3600 { return 30 * 60 }
        return 5 * 60
    }

    /// Is this flight due for a refresh (phase interval, backoff after failures)?
    func isDue(_ f: Flight, force: Bool = false, now: Date = Date()) -> Bool {
        guard !f.isPast else { return false }
        let dep = f.departure.best ?? f.sortDate
        let arr = f.arrival.best ?? dep.addingTimeInterval(4 * 3600)
        // FlightAware alone only knows flights about 2 days ahead – don't pay for "not found"
        let horizon: TimeInterval = FlightProvider.current == .flightaware ? 46 * 3600 : 72 * 3600
        guard dep < now.addingTimeInterval(horizon), arr > now.addingTimeInterval(-90 * 60) else { return false }
        if let a = attempts[f.id] {
            let backoff = force ? 60 : min(3600, 300 * pow(2, Double(a.fails - 1)))
            if now.timeIntervalSince(a.last) < backoff { return false }
        }
        let minAge: TimeInterval = force ? 60 : Self.refreshInterval(departure: dep, arrival: arr, now: now, flight: f)
        return f.lastUpdated.map { now.timeIntervalSince($0) > minAge } ?? true
    }

    private var quotaPaused: Bool {
        Date() < (UserDefaults.standard.object(forKey: "quotaPausedUntil") as? Date ?? .distantPast) || Date() < ratePausedUntil
    }

    /// Refreshes flights departing within the next 3 days or currently in the air. Only one run at a time.
    func refreshActive(force: Bool = false, notify: Bool = true) async {
        guard force || Settings.autoRefresh else { return }
        if let running = refreshTask {
            await running.value
            return
        }
        let task = Task { await runRefresh(force: force, notify: notify) }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    private func runRefresh(force: Bool, notify: Bool) async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        if FlightData.isConfigured && (force || !quotaPaused) {
            let now = Date()
            for f in flights.filter({ isDue($0, force: force, now: now) }) {
                do { try await refresh(f.id, notify: notify) } catch {
                    lastError = error.localizedDescription
                    if case APIError.rateLimited = error {
                        ratePausedUntil = Date().addingTimeInterval(120)   // per-minute limit: short pause
                        break
                    }
                    if case APIError.quota = error {
                        // Stop hammering the API when the monthly quota is used up
                        UserDefaults.standard.set(Date().addingTimeInterval(6 * 3600), forKey: "quotaPausedUntil")
                        lastError = "API-Kontingent aufgebraucht – automatische Aktualisierung pausiert 6 h. Tipp: in den Einstellungen „Beide kombiniert“ oder FlightAware wählen."
                        break
                    }
                }
            }
        }
        if force || !quotaPaused { await updateInbounds(force: force, notify: notify) }
        await updateLivePositions()
        await LiveFlight.syncAll(flights)
        LiveFlight.autoStartIfNeeded(upcoming)
        await CalendarSync.sync(flights, bookings: BookingStore.shared.bookings)
    }

    // MARK: Inbound aircraft

    /// Tracks the plane's previous leg: hourly from 8 h before departure, every 15 min in the last 3 h,
    /// and on past the planned time until we actually leave (that's when a late inbound matters most).
    func updateInbounds(force: Bool = false, notify: Bool = true) async {
        let now = Date()
        for f in flights {
            guard let dep = f.departure.best, dep > now.addingTimeInterval(-3 * 3600), dep < now.addingTimeInterval(8 * 3600),
                  f.departure.runway == nil, !f.normalizedStatus.isAirborne, !f.normalizedStatus.isFinal else { continue }
            if f.inbound?.landed == true { continue }
            let interval: TimeInterval = force ? 60 : dep.timeIntervalSince(now) > 3 * 3600 ? 3600 : 15 * 60
            let last = max(f.inbound?.updated ?? .distantPast, inboundAttempts[f.id] ?? .distantPast)
            if now.timeIntervalSince(last) < interval { continue }
            inboundAttempts[f.id] = now      // also counts when nothing is found
            await updateInbound(f.id, notify: notify)
        }
    }

    func updateInbound(_ id: UUID, notify: Bool = true) async {
        guard let f = flight(id), let new = try? await FlightData.inbound(for: f) else { return }
        guard var current = flight(id) else { return }
        let old = current.inbound
        current.inbound = new
        if let legs = FlightData.lastLegs[id] { current.planeLegs = legs }
        if new.departed && old?.departed != true { current.log("Dein Flugzeug ist in \(new.fromCode) gestartet (\(new.number))") }
        if new.landed && old?.landed != true { current.log("Dein Flugzeug ist aus \(new.fromCode) gelandet") }
        update(current)
        guard notify, Settings.notifyChanges else { return }
        let ourDep = current.departure.best
        let delay = new.expectedDelay(ourDeparture: ourDep)
        let oldDelay = old?.expectedDelay(ourDeparture: ourDep) ?? 0
        let tag = "\(id)-inbound"
        if new.isCanceled && old?.isCanceled != true {
            Notifier.post(id: "\(tag)-cancel", title: "\(current.number): Zubringer annulliert",
                          body: "Der Flug \(new.number), der dein Flugzeug bringen sollte, ist annulliert. Mögliche Verspätung oder Flugzeugwechsel.")
        } else if delay >= 15 && delay >= oldDelay + 15 {
            Notifier.post(id: "\(tag)-delay-\(delay)", title: "\(current.number): Flugzeug kommt spät",
                          body: "Dein Flugzeug (\(new.number) aus \(new.fromCode)) landet erst \(Fmt.time(new.arrival, current.departure.tz)). Abflug wohl ca. \(delay) Min. später.")
        } else if new.departed && old?.departed == false {
            Notifier.post(id: "\(tag)-dep", title: "\(current.number): Flugzeug ist unterwegs",
                          body: "Dein Flugzeug ist als \(new.number) in \(new.fromCode) gestartet. Landung ca. \(Fmt.time(new.arrival, current.departure.tz)).")
        } else if new.landed && old?.landed == false {
            Notifier.post(id: "\(tag)-land", title: "\(current.number): Flugzeug ist da",
                          body: "Dein Flugzeug ist aus \(new.fromCode) gelandet.")
        }
    }

    /// Live data: free ADS-B first (departure/landing detection, position, ETA), then OpenSky / FlightAware as fallback.
    func updateLive(_ id: UUID) async {
        guard let f = flight(id), isLiveWindow(f) else { return }
        if let cs = LiveADSB.callsign(for: f) {
            let fix = await LiveADSB.lookup(callsign: cs)
            guard var current = flight(id) else { return }
            let notes = LiveADSB.apply(fix, to: &current)
            if fix != nil || !notes.isEmpty {
                for n in notes { current.log(n.title.contains("gestartet") ? "Gestartet (Live-Position)" : "Gelandet (Live-Position)") }
                update(current)
                if Settings.notifyChanges && !PushClient.isConfigured {
                    for n in notes { Notifier.post(id: "\(id)-\(n.title)", title: n.title, body: n.body) }
                }
                if fix != nil { return }
            }
        }
        // re-read: ADS-B may just have marked the flight as landed
        guard let now = flight(id), now.isInAir else { return }
        var pos: LivePosition?
        if let hex = now.icao24, !hex.isEmpty {
            pos = try? await OpenSky.position(icao24: hex)
        }
        // paid fallback: at most every 15 min
        if pos == nil, let faID = now.faFlightID, FlightAware.hasKey, !quotaPaused,
           Date().timeIntervalSince(positionQueries[id] ?? .distantPast) > 15 * 60 {
            positionQueries[id] = Date()
            pos = try? await FlightAware.position(faID)
        }
        guard let pos, var current = flight(id) else { return }
        if let old = current.lastPosition, old.timestamp >= pos.timestamp { return }
        current.lastPosition = pos
        update(current)
    }

    /// From 45 min before departure until 3 h after the expected arrival (unless landed/cancelled).
    private func isLiveWindow(_ f: Flight, now: Date = Date()) -> Bool {
        guard !f.normalizedStatus.isFinal || (f.normalizedStatus == .arrived && f.arrival.runway == nil),
              let dep = f.departure.best else { return f.isInAir }
        let arr = f.arrival.best ?? dep.addingTimeInterval(12 * 3600)
        return now > dep.addingTimeInterval(-45 * 60) && now < arr.addingTimeInterval(3 * 3600)
    }

    func updateLivePositions() async {
        for f in flights where isLiveWindow(f) { await updateLive(f.id) }
    }

    // MARK: Persistence

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    @ObservationIgnored private var writable = true

    private func load() {
        let loaded = SafeFile.load([Flight].self, from: fileURL, decoder: Self.decoder)
        writable = loaded.writable
        flights = loaded.value ?? []
    }

    private func save() {
        guard writable, let data = try? Self.encoder.encode(flights) else { return }
        try? data.write(to: fileURL, options: .atomic)
        LiveFlight.publish(upcoming)
        PushClient.scheduleSync()
    }

    func exportURL() -> URL? {
        let url = FileManager.default.temporaryDirectory.appending(path: "Skylog-Fluege.json")
        guard let data = try? Self.encoder.encode(flights), (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    @discardableResult
    func importFlights(from url: URL) throws -> Int {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let imported = try Self.decoder.decode([Flight].self, from: data)
        var added = 0
        for f in imported where !flights.contains(where: { $0.id == f.id || Self.isSameFlight($0, f) }) {
            flights.append(f)
            added += 1
        }
        save()
        return added
    }
}

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

    private static func key(_ f: Flight) -> String { f.number.replacingOccurrences(of: " ", with: "").uppercased() + "|" + f.date }

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
        let f = pending.remove(at: i)
        savePending()
        add(f)
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
        let n = number.replacingOccurrences(of: " ", with: "").uppercased()
        return flights.contains { $0.date == d && $0.number.replacingOccurrences(of: " ", with: "").uppercased() == n }
    }

    // MARK: Mutations

    static func normalizedNumber(_ n: String) -> String { n.replacingOccurrences(of: " ", with: "").uppercased() }

    /// Same flight: same number + date, or a codeshare (same route, departure within 60 min / same day without times).
    static func isSameFlight(_ a: Flight, _ b: Flight) -> Bool {
        if normalizedNumber(a.number) == normalizedNumber(b.number) && a.date == b.date { return true }
        guard a.departure.code == b.departure.code, a.arrival.code == b.arrival.code else { return false }
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
        save()
    }

    /// Flights without times and without resolvable airports (typically false matches from mail import).
    var incomplete: [Flight] {
        flights.filter { f in
            f.departure.scheduled == nil && f.departure.best == nil &&
            (f.departure.coordinate == nil || f.arrival.coordinate == nil ||
             !FlightTextParser.airlines.contains(String(f.number.prefix(2))))
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

    func refresh(_ id: UUID, notify: Bool = true) async throws {
        guard let old = flight(id) else { return }
        let date = Fmt.apiDate.date(from: old.date) ?? old.sortDate
        let results = try await FlightData.search(number: old.number, date: date)
        guard var new = results.first(where: { $0.departure.code == old.departure.code }) ?? results.first else { return }
        new.id = old.id
        new.notes = old.notes
        new.seat = old.seat
        new.date = old.date
        new.lastUpdated = Date()
        if new.lastPosition == nil { new.lastPosition = old.lastPosition }
        if new.icao24 == nil { new.icao24 = old.icao24 }
        if new.inbound == nil { new.inbound = old.inbound }
        if new.inboundFAID == nil { new.inboundFAID = old.inboundFAID }

        if notify && Settings.notifyChanges {
            for change in Notifier.changes(old: old, new: new) {
                Notifier.post(id: "\(new.id)-\(change.title)-\(Date().timeIntervalSince1970)", title: change.title, body: change.body)
            }
        }
        update(new)
        Notifier.scheduleReminders(for: new)
        HotelRoute.scheduleReminders(for: new)
    }

    /// Smart refresh interval to save API queries:
    /// 24–4 h before departure every 4 h, then every 20 min until landing, after landing once (baggage belt).
    static func refreshInterval(departure dep: Date, arrival arr: Date, now: Date, flight f: Flight) -> TimeInterval {
        if f.normalizedStatus == .arrived {
            // one more update after landing, then stop
            if let last = f.lastUpdated, last > arr { return .infinity }
            return 0
        }
        if dep.timeIntervalSince(now) > 4 * 3600 { return 4 * 3600 }
        return 20 * 60
    }

    /// Refreshes flights departing within the next 24 h or currently in the air.
    func refreshActive(force: Bool = false, notify: Bool = true) async {
        guard force || Settings.autoRefresh else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        let pausedUntil = UserDefaults.standard.object(forKey: "quotaPausedUntil") as? Date ?? .distantPast
        if FlightData.isConfigured && (force || Date() > pausedUntil) {
            let now = Date()
            let candidates = flights.filter { f in
                guard !f.isPast, f.normalizedStatus != .canceled else { return false }
                let dep = f.departure.best ?? f.sortDate
                let arr = f.arrival.best ?? dep.addingTimeInterval(4 * 3600)
                let inWindow = dep < now.addingTimeInterval(24 * 3600) && arr > now.addingTimeInterval(-90 * 60)
                let minAge: TimeInterval = force ? 60 : Self.refreshInterval(departure: dep, arrival: arr, now: now, flight: f)
                let stale = f.lastUpdated.map { now.timeIntervalSince($0) > minAge } ?? true
                return inWindow && stale
            }
            for f in candidates {
                do { try await refresh(f.id, notify: notify) } catch {
                    lastError = error.localizedDescription
                    if case APIError.quota = error {
                        // Stop hammering the API when the monthly quota is used up
                        UserDefaults.standard.set(Date().addingTimeInterval(6 * 3600), forKey: "quotaPausedUntil")
                        lastError = "API-Kontingent aufgebraucht – automatische Aktualisierung pausiert 6 h. Tipp: in den Einstellungen auf FlightAware wechseln."
                        break
                    }
                }
            }
        }
        await updateInbounds(force: force, notify: notify)
        await updateLivePositions()
        LiveFlight.autoStartIfNeeded(upcoming)
    }

    // MARK: Inbound aircraft

    /// Tracks the plane's previous leg from 8 h before departure until we board (every 15 min).
    func updateInbounds(force: Bool = false, notify: Bool = true) async {
        let now = Date()
        for f in flights {
            guard let dep = f.departure.best, dep > now, dep < now.addingTimeInterval(8 * 3600),
                  !f.normalizedStatus.isAirborne, !f.normalizedStatus.isFinal else { continue }
            if f.inbound?.landed == true { continue }
            if !force, let u = f.inbound?.updated, now.timeIntervalSince(u) < 15 * 60 { continue }
            await updateInbound(f.id, notify: notify)
        }
    }

    func updateInbound(_ id: UUID, notify: Bool = true) async {
        guard let f = flight(id), let new = try? await FlightData.inbound(for: f) else { return }
        guard var current = flight(id) else { return }
        let old = current.inbound
        current.inbound = new
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
        if let cs = LiveADSB.callsign(for: f.number) {
            let fix = await LiveADSB.lookup(callsign: cs)
            guard var current = flight(id) else { return }
            let notes = LiveADSB.apply(fix, to: &current)
            if fix != nil || !notes.isEmpty {
                update(current)
                if UserDefaults.standard.object(forKey: "notifyChanges") as? Bool ?? true {
                    for n in notes { Notifier.post(id: "adsb-\(id)-\(n.title)", title: n.title, body: n.body) }
                }
                if fix != nil { return }
            }
        }
        guard f.isInAir else { return }
        var pos: LivePosition?
        if let hex = f.icao24, !hex.isEmpty {
            pos = try? await OpenSky.position(icao24: hex)
        }
        if pos == nil, let faID = f.faFlightID, FlightAware.hasKey,
           f.lastPosition.map({ Date().timeIntervalSince($0.timestamp) > 5 * 60 }) ?? true {
            pos = try? await FlightAware.position(faID)
        }
        guard let pos, var current = flight(id) else { return }
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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode([Flight].self, from: data) else { return }
        flights = decoded
    }

    private func save() {
        guard let data = try? Self.encoder.encode(flights) else { return }
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
        let existing = Set(flights.map(\.id))
        let new = imported.filter { !existing.contains($0.id) }
        flights.append(contentsOf: new)
        save()
        return new.count
    }
}

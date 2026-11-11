import Foundation

/// Keeps flights, trips and bookings in step between the user's own devices – through the user's own push server.
/// The server only stores one document; merging happens here: per entry the newest change wins,
/// deletions are remembered so a deleted entry doesn't come back from another device.
@MainActor
enum DeviceSync {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "deviceSync") && PushClient.isConfigured }

    static var lastStatus: String? {
        get { UserDefaults.standard.string(forKey: "deviceSyncStatus") }
        set { UserDefaults.standard.set(newValue, forKey: "deviceSyncStatus") }
    }

    // MARK: Deletions (tombstones)

    private static let deletedKey = "syncDeleted"
    static var deleted: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: deletedKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: deletedKey) }
    }

    /// Called by the stores whenever entries are deleted.
    static func noteDeleted(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var d = deleted
        let now = Date().timeIntervalSince1970
        for id in ids { d[id.uuidString] = now }
        // forget deletions after half a year
        d = d.filter { now - $0.value < 180 * 86400 }
        deleted = d
        scheduleSync()
    }

    // MARK: Document

    struct Document: Codable {
        var flights: [Flight] = []
        var trips: [Trip] = []
        var bookings: [TravelBooking] = []
        var deleted: [String: Double] = [:]
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static func stamp(_ d: Date?) -> Double { d?.timeIntervalSince1970 ?? 0 }

    /// Newest version of each entry wins; an entry deleted after its last change stays deleted.
    static func merge(local: Document, remote: Document) -> Document {
        var out = Document()
        let gone = local.deleted.merging(remote.deleted) { max($0, $1) }
        out.deleted = gone
        func alive(_ id: UUID, _ modified: Date?) -> Bool {
            guard let gone = gone[id.uuidString] else { return true }
            return stamp(modified) > gone
        }
        func combine<T: Identifiable>(_ a: [T], _ b: [T], modified: (T) -> Date?) -> [T] where T.ID == UUID {
            var byID: [UUID: T] = [:]
            var order: [UUID] = []
            for item in a + b {
                if let existing = byID[item.id] {
                    if stamp(modified(item)) > stamp(modified(existing)) { byID[item.id] = item }
                } else {
                    byID[item.id] = item
                    order.append(item.id)
                }
            }
            return order.compactMap { byID[$0] }.filter { alive($0.id, modified($0)) }
        }
        out.flights = combine(local.flights, remote.flights) { $0.modified ?? $0.lastUpdated }
        out.trips = combine(local.trips, remote.trips) { $0.modified }
        out.bookings = combine(local.bookings, remote.bookings) { $0.modified }
        // the same flight entered on two devices independently: keep the better one
        var kept: [Flight] = []
        for f in out.flights.sorted(by: { stamp($0.modified ?? $0.lastUpdated) > stamp($1.modified ?? $1.lastUpdated) }) {
            if !kept.contains(where: { FlightStore.isSameFlight($0, f) }) { kept.append(f) }
        }
        out.flights = kept
        return out
    }

    // MARK: Sync

    private static var pending: Task<Void, Never>?
    private static var running = false

    /// Debounced sync after local changes.
    static func scheduleSync() {
        guard enabled else { return }
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await sync()
        }
    }

    private struct Envelope: Decodable { let rev: Int; let data: String? }

    @discardableResult
    static func sync() async -> Bool {
        guard enabled, !running else { return false }
        running = true
        defer { running = false }
        do {
            var remote = try await fetch()
            for _ in 0..<3 {
                let remoteDoc = try remote.data.flatMap { try decoder.decode(Document.self, from: Data($0.utf8)) } ?? Document()
                let local = Document(flights: FlightStore.shared.flights, trips: TripStore.shared.trips,
                                     bookings: BookingStore.shared.bookings, deleted: deleted)
                let merged = merge(local: local, remote: remoteDoc)
                // Safety net: a merge can only drop entries that were deleted on purpose
                let explained = merged.deleted.count
                guard merged.flights.count + explained >= local.flights.count / 2 else {
                    throw AIClient.Failure(message: String(localized: "Abgleich abgebrochen: das Ergebnis hätte zu viele Flüge entfernt."))
                }
                let text = String(decoding: try encoder.encode(merged), as: UTF8.self)
                if let next = try await put(rev: remote.rev, data: text) {
                    remote = next          // someone else was faster – merge again with their version
                    continue
                }
                FlightStore.shared.replaceAll(merged.flights)
                TripStore.shared.replaceAll(merged.trips)
                BookingStore.shared.replaceAll(merged.bookings)
                deleted = merged.deleted
                DiagLog.add("sync", "ok: \(merged.flights.count) Flüge (lokal vorher \(local.flights.count), Server \(remoteDoc.flights.count)), \(merged.trips.count) Reisen, \(merged.bookings.count) Buchungen, rev \(remote.rev)")
                lastStatus = String(localized: "Abgeglichen \(Date().formatted(date: .abbreviated, time: .shortened)): \(merged.flights.count) Flüge, \(merged.trips.count) Reisen, \(merged.bookings.count) Buchungen")
                return true
            }
            throw AIClient.Failure(message: String(localized: "Abgleich im Moment nicht möglich – bitte später nochmal."))
        } catch {
            lastStatus = String(localized: "Abgleich fehlgeschlagen: \(error.localizedDescription)")
            DiagLog.add("sync", "FEHLER \(error.localizedDescription)")
            return false
        }
    }

    private static func request(_ method: String, body: Data? = nil) throws -> URLRequest {
        guard let url = PushClient.endpoint("/data") else { throw APIError.notFound }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 30
        r.setValue("Bearer \(PushClient.serverToken)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        return r
    }

    private static func fetch() async throws -> Envelope {
        let (data, response) = try await URLSession.shared.data(for: try request("GET"))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw APIError.http(code) }
        return try JSONDecoder().decode(Envelope.self, from: data)
    }

    /// Returns nil when stored; the newer server version when someone else wrote in between.
    private static func put(rev: Int, data text: String) async throws -> Envelope? {
        let body = try JSONSerialization.data(withJSONObject: ["rev": rev, "data": text])
        let (data, response) = try await URLSession.shared.data(for: try request("PUT", body: body))
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 409 { return try JSONDecoder().decode(Envelope.self, from: data) }
        guard code == 200 else { throw APIError.http(code) }
        return nil
    }
}

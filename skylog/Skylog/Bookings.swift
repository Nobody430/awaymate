import Foundation
import Observation

/// Hotel, rental car, train … found in mails (or added by hand).
struct TravelBooking: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case hotel, car, train, bus, ferry, activity, other
        var label: String {
            switch self {
            case .hotel: String(localized: "Unterkunft")
            case .car: String(localized: "Mietwagen")
            case .train: String(localized: "Zug")
            case .bus: String(localized: "Bus")
            case .ferry: String(localized: "Fähre")
            case .activity: String(localized: "Aktivität")
            case .other: String(localized: "Buchung")
            }
        }
        var icon: String {
            switch self {
            case .hotel: "bed.double"
            case .car: "car"
            case .train: "tram"
            case .bus: "bus"
            case .ferry: "ferry"
            case .activity: "ticket"
            case .other: "doc.text"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var name: String
    var city: String
    var address: String = ""
    var start: Date
    var end: Date
    var bookingReference: String = ""
    var provider: String = ""
    var cancelled = false
    /// Last change on any device (for the sync between devices)
    var modified: Date? = nil
    /// Link to manage the booking (entered by hand; otherwise derived from the provider)
    var manageURL: String? = nil

    var key: String { kind.rawValue + "|" + (bookingReference.isEmpty ? name.lowercased() : bookingReference.uppercased()) + "|" + Fmt.apiDate.string(from: start) }
    var nights: Int { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: end)).day ?? 0) }
}

@MainActor
@Observable
final class BookingStore {
    static let shared = BookingStore()
    private(set) var bookings: [TravelBooking] = []
    private let file = URL.documentsDirectory.appending(path: "bookings.json")

    init() {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        let loaded = SafeFile.load([TravelBooking].self, from: file, decoder: d)
        writable = loaded.writable
        bookings = loaded.value ?? []
    }

    @ObservationIgnored private var writable = true

    private func save() {
        guard writable else { return }
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        try? e.encode(bookings).write(to: file, options: .atomic)
    }

    /// Adds or updates (same booking reference/name + start date). Cancelled bookings remove an existing entry.
    @discardableResult
    func upsert(_ b: TravelBooking) -> Bool {
        if b.cancelled {
            let before = bookings.count
            let gone = bookings.filter { $0.kind == b.kind && ((!b.bookingReference.isEmpty && $0.bookingReference.uppercased() == b.bookingReference.uppercased()) || $0.key == b.key) }
            DeviceSync.noteDeleted(gone.map(\.id))
            bookings.removeAll { $0.kind == b.kind && ((!b.bookingReference.isEmpty && $0.bookingReference.uppercased() == b.bookingReference.uppercased()) || $0.key == b.key) }
            save()
            return bookings.count != before
        }
        if let i = bookings.firstIndex(where: { $0.key == b.key || (!b.bookingReference.isEmpty && $0.kind == b.kind && $0.bookingReference.uppercased() == b.bookingReference.uppercased()) }) {
            var updated = b
            updated.id = bookings[i].id
            if updated.manageURL == nil { updated.manageURL = bookings[i].manageURL }   // keep what was entered by hand
            updated.modified = bookings[i].modified
            if updated == bookings[i] { return false }     // nothing new – no second notification
            updated.modified = Date()
            bookings[i] = updated
        } else {
            var new = b
            new.modified = Date()
            bookings.append(new)
        }
        bookings.sort { $0.start < $1.start }
        save()
        DeviceSync.scheduleSync()
        return true
    }

    /// Saves a booking that was entered or edited by hand (matched by its id, not by name or code).
    func store(_ booking: TravelBooking) {
        var b = booking
        b.modified = Date()
        if let i = bookings.firstIndex(where: { $0.id == b.id }) { bookings[i] = b } else { bookings.append(b) }
        bookings.sort { $0.start < $1.start }
        save()
        DeviceSync.scheduleSync()
    }

    func delete(_ ids: [UUID]) {
        bookings.removeAll { ids.contains($0.id) }
        save()
        DeviceSync.noteDeleted(ids)
    }

    func deleteAll() {
        DeviceSync.noteDeleted(bookings.map(\.id))
        bookings = []
        save()
    }

    /// Result of a sync with the other devices.
    func replaceAll(_ merged: [TravelBooking]) {
        let sorted = merged.sorted { $0.start < $1.start }
        guard sorted != bookings else { return }
        bookings = sorted
        save()
    }

    func bookings(for trip: Trip) -> [TravelBooking] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.start)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.end)) ?? trip.end
        return bookings.filter { $0.start < end && $0.end >= start }
    }
}

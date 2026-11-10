import Foundation
import Observation

/// Hotel, rental car, train … found in mails (or added by hand).
struct TravelBooking: Identifiable, Codable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case hotel, car, train, bus, ferry, activity, other
        var label: String {
            switch self {
            case .hotel: "Unterkunft"
            case .car: "Mietwagen"
            case .train: "Zug"
            case .bus: "Bus"
            case .ferry: "Fähre"
            case .activity: "Aktivität"
            case .other: "Buchung"
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
            bookings.removeAll { $0.kind == b.kind && ((!b.bookingReference.isEmpty && $0.bookingReference.uppercased() == b.bookingReference.uppercased()) || $0.key == b.key) }
            save()
            return bookings.count != before
        }
        if let i = bookings.firstIndex(where: { $0.key == b.key || (!b.bookingReference.isEmpty && $0.kind == b.kind && $0.bookingReference.uppercased() == b.bookingReference.uppercased()) }) {
            var updated = b
            updated.id = bookings[i].id
            if updated == bookings[i] { return false }     // nothing new – no second notification
            bookings[i] = updated
        } else {
            bookings.append(b)
        }
        bookings.sort { $0.start < $1.start }
        save()
        return true
    }

    func delete(_ ids: [UUID]) {
        bookings.removeAll { ids.contains($0.id) }
        save()
    }

    func deleteAll() {
        bookings = []
        save()
    }

    func bookings(for trip: Trip) -> [TravelBooking] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: trip.start)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: trip.end)) ?? trip.end
        return bookings.filter { $0.start < end && $0.end >= start }
    }
}

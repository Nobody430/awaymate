import SwiftUI

/// Where a booking can be managed: the provider's "my bookings" page, a link entered by hand, or a web search.
enum ManageLinks {
    private static let providers: [(match: String, url: String)] = [
        ("booking.com", "https://secure.booking.com/myreservations.html"),
        ("airbnb", "https://www.airbnb.com/trips"),
        ("expedia", "https://www.expedia.com/trips"),
        ("hotels.com", "https://www.hotels.com/trips"),
        ("agoda", "https://www.agoda.com/account/bookings.html"),
    ]

    private static func search(_ text: String) -> URL? {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: text)]
        return c.url
    }

    /// Link for a hotel or other booking and whether it leads straight to the provider (false = web search).
    static func booking(_ b: TravelBooking) -> (url: URL, direct: Bool)? {
        if let own = b.manageURL?.trimmingCharacters(in: .whitespaces), !own.isEmpty,
           let url = URL(string: own.contains("://") ? own : "https://" + own) {
            return (url, true)
        }
        let provider = b.provider.lowercased()
        if let hit = providers.first(where: { provider.contains($0.match) }), let url = URL(string: hit.url) { return (url, true) }
        guard let url = search([b.name, b.city].filter { !$0.isEmpty }.joined(separator: " ")) else { return nil }
        return (url, false)
    }

    /// Airlines have no common link format: search for the airline's "manage booking" page.
    static func flight(_ f: Flight) -> URL? {
        search((f.airlineName ?? String(f.number.prefix(2))) + " " + String(localized: "Buchung verwalten"))
    }
}

/// Booking code of a flight with a way to the airline's booking page.
struct FlightBookingCard: View {
    let flight: Flight
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            if !flight.isPast, let url = ManageLinks.flight(flight) {
                Button {
                    if let code = flight.bookingReference, !code.isEmpty {
                        UIPasteboard.general.string = code
                        copied = true
                    }
                    openURL(url)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "ticket").font(.title3).foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Buchung verwalten").font(.headline)
                            if let code = flight.bookingReference, !code.isEmpty {
                                Text(copied ? String(localized: "Code \(code) kopiert") : String(localized: "Code \(code)"))
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("Check-in, Sitzplatz, Umbuchung bei der Airline").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Add a booking by hand or correct one that was imported.
struct BookingEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var booking: TravelBooking
    private let isNew: Bool

    init(booking: TravelBooking? = nil, start: Date = Date(), end: Date? = nil) {
        isNew = booking == nil
        let begin = Calendar.current.startOfDay(for: start)
        _booking = State(initialValue: booking ?? TravelBooking(
            kind: .hotel, name: "", city: "", start: begin,
            end: end ?? Calendar.current.date(byAdding: .day, value: 1, to: begin) ?? begin))
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isNew, let link = ManageLinks.booking(booking) {
                    Section {
                        Button {
                            if !booking.bookingReference.isEmpty { UIPasteboard.general.string = booking.bookingReference }
                            openURL(link.url)
                        } label: {
                            Label(link.direct ? String(localized: "Buchung verwalten") : String(localized: "Im Web suchen"),
                                  systemImage: link.direct ? "arrow.up.right.square" : "magnifyingglass")
                        }
                    } footer: {
                        if !booking.bookingReference.isEmpty { Text("Der Buchungscode wird dabei kopiert.") }
                    }
                }
                Section {
                    Picker("Art", selection: $booking.kind) {
                        ForEach(TravelBooking.Kind.allCases, id: \.self) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    TextField("Name", text: $booking.name)
                    TextField("Ort", text: $booking.city)
                    TextField("Adresse", text: $booking.address, axis: .vertical)
                }
                Section {
                    DatePicker("Von", selection: $booking.start, displayedComponents: .date)
                    DatePicker("Bis", selection: $booking.end, in: booking.start..., displayedComponents: .date)
                }
                Section {
                    TextField("Buchungscode", text: $booking.bookingReference)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    TextField("Gebucht über (z.B. Booking.com)", text: $booking.provider)
                    TextField("Link zur Buchung", text: Binding(get: { booking.manageURL ?? "" },
                                                              set: { booking.manageURL = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("Den Link findest du in der Bestätigungsmail („Buchung verwalten“). Ohne Link öffnet die App die Buchungsseite des Anbieters.")
                }
                if !isNew {
                    Section {
                        Button("Buchung löschen", role: .destructive) {
                            BookingStore.shared.delete([booking.id])
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? String(localized: "Buchung hinzufügen") : booking.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if booking.end < booking.start { booking.end = booking.start }
                        BookingStore.shared.store(booking)
                        dismiss()
                    }
                    .disabled(booking.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

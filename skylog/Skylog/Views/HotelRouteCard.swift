import SwiftUI
import MapKit

/// Shows how to get from the airport to the booked hotel (after landing) and from the hotel to the airport (departure day).
struct HotelRouteCard: View {
    let flight: Flight
    @Environment(\.openURL) private var openURL
    @State private var toHotel: Leg?
    @State private var fromHotel: Leg?
    @State private var loaded = false

    struct Leg {
        let hotel: TravelBooking
        let item: MKMapItem?
        let times: HotelRoute.Times
    }

    var body: some View {
        VStack(spacing: 0) {
            if toHotel != nil || fromHotel != nil {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Unterkunft", systemImage: "bed.double.fill").font(.headline)
                    if let fromHotel { legView(fromHotel, outbound: true) }
                    if let toHotel { legView(toHotel, outbound: false) }
                    Text("Reisezeiten von Apple Karten, ohne Gewähr.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .task(id: flight.id.uuidString + "\(flight.departure.best?.timeIntervalSince1970 ?? 0)") { await load() }
    }

    @ViewBuilder
    private func legView(_ leg: Leg, outbound: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(outbound ? "Vom Hotel zum Flughafen \(flight.departure.code)" : "Vom Flughafen \(flight.arrival.code) zum Hotel")
                .font(.caption).foregroundStyle(.secondary)
            Text(leg.hotel.name).font(.subheadline.bold())
            if !leg.hotel.address.isEmpty {
                Text(leg.hotel.address).font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                if let t = leg.times.transit { chip("tram.fill", "ÖV \(Fmt.duration(Int(t / 60)))") }
                if let t = leg.times.car { chip("car.fill", "Taxi \(Fmt.duration(Int(t / 60)))") }
                if let t = leg.times.walk { chip("figure.walk", Fmt.duration(Int(t / 60))) }
                if let d = leg.times.distanceKm { chip("ruler", Fmt.km(d)) }
            }
            .font(.caption)
            if outbound, let dep = flight.departure.best, let travel = leg.times.transit ?? leg.times.car {
                let leave = dep.addingTimeInterval(-Double(AirportBuffer.minutes(for: flight)) * 60 - travel - 10 * 60)
                Text("Losgehen spätestens \(Fmt.time(leave, flight.departure.tz)) (\(AirportBuffer.label(AirportBuffer.minutes(for: flight))) vor Abflug am Flughafen)")
                    .font(.subheadline).foregroundStyle(Theme.accent)
            }
            if outbound, let dep = flight.departure.best, Calendar.current.isDate(leg.hotel.end, inSameDayAs: dep) {
                Text("Check-out am Abflugtag – Gepäckaufbewahrung im Hotel fragen, falls der Flug spät ist.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack {
                Button { openAppleMaps(leg, outbound: outbound) } label: {
                    Label("Apple Karten", systemImage: "map")
                }
                Button { openGoogle(leg, outbound: outbound) } label: {
                    Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
            }
            .buttonStyle(.bordered).font(.caption)
        }
    }

    private func chip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon).labelStyle(.titleAndIcon)
    }

    private func load() async {
        let arrHotel = HotelRoute.hotel(after: flight)
        let depHotel = HotelRoute.hotel(before: flight)
        if let h = arrHotel, flight.arrival.best.map({ $0 > Date().addingTimeInterval(-12 * 3600) }) ?? true {
            let item = await HotelRoute.locate(h, near: flight.arrival.coordinate)
            var times = HotelRoute.Times()
            if let item, let ap = HotelRoute.airportItem(flight.arrival) {
                times = await HotelRoute.times(from: ap, to: item, departAt: flight.arrival.best?.addingTimeInterval(30 * 60))
            }
            toHotel = Leg(hotel: h, item: item, times: times)
        } else { toHotel = nil }
        if let h = depHotel, !flight.isInAir, !flight.normalizedStatus.isFinal {
            let item = await HotelRoute.locate(h, near: flight.departure.coordinate)
            var times = HotelRoute.Times()
            if let item, let ap = HotelRoute.airportItem(flight.departure), let dep = flight.departure.best {
                times = await HotelRoute.times(from: item, to: ap,
                                               arriveBy: dep.addingTimeInterval(-Double(AirportBuffer.minutes(for: flight)) * 60))
            }
            fromHotel = Leg(hotel: h, item: item, times: times)
        } else { fromHotel = nil }
        HotelRoute.scheduleReminders(for: flight)
    }

    private func openAppleMaps(_ leg: Leg, outbound: Bool) {
        let airport = HotelRoute.airportItem(outbound ? flight.departure : flight.arrival)
        guard let hotel = leg.item, let airport else {
            openGoogle(leg, outbound: outbound)
            return
        }
        let items = outbound ? [hotel, airport] : [airport, hotel]
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit])
    }

    private func openGoogle(_ leg: Leg, outbound: Bool) {
        let query = [leg.hotel.name, leg.hotel.address.isEmpty ? leg.hotel.city : leg.hotel.address].joined(separator: ", ")
        let url: URL?
        if outbound, let ap = flight.departure.coordinate {
            url = HotelRoute.googleURL(fromQuery: query, to: ap)
        } else if let ap = flight.arrival.coordinate {
            url = HotelRoute.googleURL(from: ap, to: query)
        } else { url = nil }
        if let url { openURL(url) }
    }
}

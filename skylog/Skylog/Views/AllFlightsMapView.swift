import SwiftUI
import MapKit
import CoreLocation

struct AirportPoint: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
}

struct AllFlightsMapView: View {
    @Environment(FlightStore.self) private var store
    @State private var showPast = true

    private var visible: [Flight] {
        store.flights.filter { showPast || !$0.isPast }
    }

    private var airports: [AirportPoint] {
        var seen: [String: CLLocationCoordinate2D] = [:]
        for f in visible {
            for e in [f.departure, f.arrival] {
                if let c = e.coordinate { seen[e.code] = c }
            }
        }
        return seen.map { AirportPoint(id: $0.key, coordinate: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Map {
                ForEach(visible) { f in
                    if let a = f.departure.coordinate, let b = f.arrival.coordinate {
                        MapPolyline(MKGeodesicPolyline(coordinates: [a, b], count: 2))
                            .stroke(f.isPast ? Color.white.opacity(0.35) : Theme.accent, lineWidth: f.isPast ? 1.5 : 3)
                    }
                }
                ForEach(airports) { ap in
                    Annotation(ap.id, coordinate: ap.coordinate) { AirportDot() }
                }
                ForEach(visible.filter(\.isInAir)) { f in
                    if let p = f.planePosition() {
                        Annotation(f.number, coordinate: p.coordinate) { PlaneMarker(heading: p.heading) }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
            .navigationTitle("Karte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: $showPast) { Image(systemName: "clock.arrow.circlepath") }
                        .toggleStyle(.button)
                }
            }
        }
    }
}

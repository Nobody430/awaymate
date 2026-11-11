import SwiftUI
import MapKit

struct StatusPill: View {
    let flight: Flight

    var body: some View {
        let status = flight.displayStatus
        // same threshold as the times below: a flight that leaves 5+ min late is not "on schedule"
        let delayed = (flight.departure.delayMinutes ?? 0) >= 5 && !status.isAirborne && !status.isFinal
        let text = delayed ? String(localized: "Verspätet") : status.label
        let color = delayed ? Fmt.delayColor(flight.departure.delayMinutes) : status.color
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

struct TimeLabel: View {
    let endpoint: FlightEndpoint
    var font: Font = .headline
    /// Arrival on another calendar day than the departure (shown as +1 / −1)
    var dayOffset: Int = 0

    var body: some View {
        let changed = (endpoint.delayMinutes.map { abs($0) >= 5 }) ?? false
        HStack(spacing: 4) {
            if changed {
                Text(Fmt.time(endpoint.scheduled, endpoint.tz))
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            Text(Fmt.time(endpoint.best, endpoint.tz))
                .font(font.monospacedDigit())
                .foregroundStyle(changed ? Fmt.delayColor(endpoint.delayMinutes) : .primary)
            if dayOffset != 0 {
                Text(dayOffset > 0 ? "+\(dayOffset)" : "\(dayOffset)")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    .baselineOffset(6)
            }
        }
    }
}

struct EndpointColumn: View {
    let endpoint: FlightEndpoint
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(endpoint.code)
                .font(.system(size: 32, weight: .bold, design: .rounded))
            Text(endpoint.displayCity)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            TimeLabel(endpoint: endpoint)
        }
    }
}

struct FlightProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.25)).frame(height: 4)
                Capsule().fill(Theme.accent).frame(width: max(0, w * progress), height: 4)
                Image(systemName: "airplane")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .offset(x: min(max(0, w * progress - 8), w - 16))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 18)
    }
}

struct FlightCard: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(flight.number).font(.subheadline.weight(.semibold))
                if let airline = flight.airlineName {
                    Text(airline).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                StatusPill(flight: flight)
            }
            HStack(alignment: .center) {
                EndpointColumn(endpoint: flight.departure, alignment: .leading)
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "airplane").foregroundStyle(.secondary)
                    if let m = flight.durationMinutes {
                        Text(Fmt.duration(m)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                EndpointColumn(endpoint: flight.arrival, alignment: .trailing)
            }
            if flight.isInAir {
                FlightProgressBar(progress: flight.progress())
            }
            if flight.isPast, Compensation.check(flight).status == .eligible {
                Label("Entschädigung möglich: \(Compensation.check(flight).amountEUR) €", systemImage: "eurosign.circle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
            HStack {
                Text(Fmt.summary(flight)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !flight.isPast {
                    if let t = flight.departure.terminal {
                        Text("T\(t)").font(.caption.weight(.medium))
                    }
                    if let g = flight.departure.gate {
                        Label("Gate \(g)", systemImage: "door.left.hand.open").font(.caption.weight(.medium))
                    }
                }
            }
        }
        .padding()
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct InfoTile: View {
    let title: String
    let value: String?
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let icon { Image(systemName: icon) }
                Text(title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(value ?? "–")
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct AirportDot: View {
    var color: Color = .white
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 2))
    }
}

struct PlaneMarker: View {
    let heading: Double
    var body: some View {
        Image(systemName: "airplane")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.yellow)
            .shadow(color: .black.opacity(0.6), radius: 3)
            .rotationEffect(.degrees(heading - 90))
    }
}

struct FlightRouteMap: View {
    let flight: Flight

    var body: some View {
        Map {
            if let a = flight.departure.coordinate, let b = flight.arrival.coordinate {
                MapPolyline(MKGeodesicPolyline(coordinates: [a, b], count: 2))
                    .stroke(Theme.accent.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
            if let a = flight.departure.coordinate {
                Annotation(flight.departure.code, coordinate: a) { AirportDot() }
            }
            if let b = flight.arrival.coordinate {
                Annotation(flight.arrival.code, coordinate: b) { AirportDot() }
            }
            if let p = flight.planePosition() {
                Annotation("", coordinate: p.coordinate) { PlaneMarker(heading: p.heading) }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }
}

/// Toolbar button: check the mailbox now for new flights, hotels and other bookings.
struct MailSyncButton: View {
    @Environment(FlightStore.self) private var store
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        Button {
            Task {
                busy = true
                result = await MailWatcher.checkNow(store: store)
                busy = false
            }
        } label: {
            if busy { ProgressView() } else { Image(systemName: "envelope.arrow.triangle.branch") }
        }
        .disabled(busy)
        .accessibilityLabel(Text("Mails jetzt prüfen"))
        .alert("Mails geprüft", isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(result ?? "")
        }
    }
}

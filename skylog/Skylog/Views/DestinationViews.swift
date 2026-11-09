import SwiftUI

struct DestinationCard: View {
    let flight: Flight
    @State private var weather: Weather.Forecast?
    @State private var rate: Double?

    private var info: CountryInfo.Info? { CountryInfo.info(flight.arrival.countryCode) }
    private var home: CountryInfo.Info? { CountryInfo.info("CH") }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("In \(flight.arrival.displayCity)", systemImage: "mappin.and.ellipse").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                InfoTile(title: "Ortszeit", value: localTime, icon: "clock")
                InfoTile(title: "Zeitverschiebung", value: offset, icon: "globe")
                if let w = weather {
                    InfoTile(title: "Wetter bei Ankunft",
                             value: "\(Int(w.temperature.rounded()))°" + (w.precipitationChance.map { " · \($0)% 💧" } ?? ""),
                             icon: w.symbol)
                }
                if let info, info.currency != "CHF" {
                    InfoTile(title: "1 CHF =", value: rate.map { "\($0.formatted(.number.precision(.significantDigits(3...5)))) \(info.currency)" } ?? info.currency,
                             icon: "banknote")
                }
                if let info, info.plugs != home?.plugs {
                    InfoTile(title: "Steckdose", value: "Typ \(info.plugs) · \(info.voltage) V", icon: "powerplug")
                }
            }
            if let info, info.voltage < 200 {
                Text("Achtung: \(info.voltage) V – Ladegeräte sind meist ok, Föhn/Glätteisen aus der Schweiz oft nicht.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: flight.id) {
            if let lat = flight.arrival.lat, let lon = flight.arrival.lon, let arr = flight.arrival.best {
                weather = try? await Weather.forecast(lat: lat, lon: lon, at: arr)
            }
            if let c = info?.currency, c != "CHF" { rate = try? await FX.perCHF(c) }
        }
    }

    private var localTime: String {
        let f = DateFormatter()
        f.timeZone = flight.arrival.tz
        f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private var offset: String {
        let diff = (flight.arrival.tz.secondsFromGMT() - TimeZone.current.secondsFromGMT()) / 60
        if diff == 0 { return "keine" }
        let h = Double(diff) / 60
        return (diff > 0 ? "+" : "−") + abs(h).formatted(.number.precision(.fractionLength(0...1))) + " h"
    }
}

/// Step-by-step plan for the travel day.
struct TravelDayCard: View {
    let flight: Flight
    @AppStorage("airportBufferMinutes") private var buffer = 120
    @AppStorage("homeStation") private var home = ""

    struct Step: Identifiable {
        let id = UUID()
        let time: Date
        let title: String
        let icon: String
        let tz: TimeZone
    }

    private var steps: [Step] {
        guard let dep = flight.departure.best else { return [] }
        let longHaul = (flight.computedDistanceKm ?? 0) > 3500
        let dtz = flight.departure.tz, atz = flight.arrival.tz
        var s: [Step] = [
            Step(time: dep.addingTimeInterval(-Double(buffer) * 60), title: "Am Flughafen sein", icon: "building.2", tz: dtz),
            Step(time: dep.addingTimeInterval(longHaul ? -60 * 60 : -40 * 60), title: "Gepäckaufgabe schliesst (ca.)", icon: "suitcase", tz: dtz),
            Step(time: dep.addingTimeInterval(longHaul ? -50 * 60 : -30 * 60), title: "Boarding" + (flight.departure.gate.map { " · Gate \($0)" } ?? ""), icon: "person.wave.2", tz: dtz),
            Step(time: dep, title: "Abflug \(flight.departure.code)", icon: "airplane.departure", tz: dtz),
        ]
        if let arr = flight.arrival.best {
            s.append(Step(time: arr, title: "Landung \(flight.arrival.code)", icon: "airplane.arrival", tz: atz))
            s.append(Step(time: arr.addingTimeInterval(30 * 60), title: "Gepäck" + (flight.arrival.baggageBelt.map { " · Band \($0)" } ?? ""), icon: "suitcase.rolling", tz: atz))
        }
        return s
    }

    var body: some View {
        if !flight.isPast, let dep = flight.departure.best, dep.timeIntervalSinceNow < 3 * 86400 {
            VStack(alignment: .leading, spacing: 10) {
                Label("Reisetag", systemImage: "list.bullet.clipboard").font(.headline)
                ForEach(steps) { step in
                    HStack(spacing: 12) {
                        Image(systemName: step.icon)
                            .frame(width: 30, height: 30)
                            .background((step.time < Date() ? Color.gray : Theme.accent).opacity(0.2), in: Circle())
                        Text(step.title).strikethrough(step.time < Date())
                        Spacer()
                        Text(Fmt.time(step.time, step.tz)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
                Text("Zeiten in Ortszeit. Gepäck- und Boardingzeiten sind Richtwerte – Angaben der Airline beachten.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

struct LiveActivityButton: View {
    let flight: Flight
    @State private var running = false

    var body: some View {
        if !flight.isPast && !flight.normalizedStatus.isFinal {
            Button {
                Task {
                    if running { await LiveFlight.stop(flight) } else { LiveFlight.start(flight) }
                    running = LiveFlight.isRunning(flight)
                }
            } label: {
                Label(running ? "Live-Aktivität beenden" : "Auf Sperrbildschirm verfolgen",
                      systemImage: running ? "stop.circle" : "livephoto")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .onAppear { running = LiveFlight.isRunning(flight) }
        }
    }
}

import SwiftUI

/// Enter a flight completely by hand (no API calls). Airports come from the bundled database.
struct ManualFlightView: View {
    @Environment(FlightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onSaved: (() -> Void)? = nil

    @State private var number = ""
    @State private var date = Date()
    @State private var from = ""
    @State private var to = ""
    @State private var withTimes = false
    @State private var departure = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var arrival = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var arrivalNextDay = false
    @State private var airline = ""
    @State private var seat = ""

    private var fromInfo: AirportLookup.Info? { from.count == 3 ? AirportLookup.bundledInfo(from) : nil }
    private var toInfo: AirportLookup.Info? { to.count == 3 ? AirportLookup.bundledInfo(to) : nil }
    private var valid: Bool { number.count >= 3 && fromInfo != nil && toInfo != nil && from != to }

    var body: some View {
        Form {
            Section {
                TextField("Flugnummer, z.B. LX1612", text: $number)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                TextField("Airline (optional)", text: $airline)
            }
            Section {
                airportField("Von (Code, z.B. ZRH)", text: $from, info: fromInfo)
                airportField("Nach (Code, z.B. BKK)", text: $to, info: toInfo)
            } footer: {
                Text("3-Buchstaben-Code des Flughafens. Den findest du auf Ticket oder Bordkarte.")
            }
            Section {
                Toggle("Uhrzeiten eintragen", isOn: $withTimes)
                if withTimes {
                    DatePicker("Abflug (Ortszeit)", selection: $departure, displayedComponents: .hourAndMinute)
                    DatePicker("Ankunft (Ortszeit)", selection: $arrival, displayedComponents: .hourAndMinute)
                    Toggle("Ankunft am nächsten Tag", isOn: $arrivalNextDay)
                }
                TextField("Sitzplatz (optional)", text: $seat).textInputAutocapitalization(.characters)
            }
        }
        .navigationTitle("Flug manuell eintragen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Sichern") { save() }.disabled(!valid)
            }
        }
    }

    private func airportField(_ title: String, text: Binding<String>, info: AirportLookup.Info?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(title, text: Binding(get: { text.wrappedValue },
                                           set: { text.wrappedValue = String($0.uppercased().filter(\.isLetter).prefix(3)) }))
                .textInputAutocapitalization(.characters).autocorrectionDisabled()
                .font(.headline.monospaced())
            if let info {
                Text("\(info.name ?? "") · \(info.city ?? "") \(info.countryCode ?? "")").font(.caption).foregroundStyle(.secondary)
            } else if text.wrappedValue.count == 3 {
                Text("Unbekannter Flughafen-Code").font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func endpoint(_ code: String, _ info: AirportLookup.Info?, time: Date?, dayOffset: Int) -> FlightEndpoint {
        var e = FlightEndpoint(iata: code, name: info?.name, city: info?.city, countryCode: info?.countryCode,
                               lat: info?.lat, lon: info?.lon, timeZone: info?.timeZone)
        if let time {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = e.tz
            let d = Calendar.current.dateComponents([.year, .month, .day], from: date)
            let t = Calendar.current.dateComponents([.hour, .minute], from: time)
            if let base = cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: t.hour, minute: t.minute)) {
                e.scheduled = cal.date(byAdding: .day, value: dayOffset, to: base)
            }
        }
        return e
    }

    private func save() {
        let dep = endpoint(from, fromInfo, time: withTimes ? departure : nil, dayOffset: 0)
        let arr = endpoint(to, toInfo, time: withTimes ? arrival : nil, dayOffset: arrivalNextDay ? 1 : 0)
        let isFuture = (dep.scheduled ?? date) > Date()
        var f = Flight(number: FlightStore.normalizedNumber(number), date: Fmt.apiDate.string(from: date),
                       status: isFuture ? "Expected" : "Arrived", departure: dep, arrival: arr)
        f.airlineName = airline.isEmpty ? nil : airline
        f.seat = seat
        store.add(f)
        onSaved?()
        dismiss()
    }
}

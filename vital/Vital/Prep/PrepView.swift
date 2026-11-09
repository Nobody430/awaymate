import SwiftUI

struct PrepView: View {
    @Environment(PrepStore.self) private var store
    @State private var month = Date()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    doseButton
                    HStack(spacing: 10) {
                        StatTile(title: "Serie", value: "\(store.streak) Tage", icon: "flame")
                        StatTile(title: "30 Tage", value: "\(Int(store.adherence30 * 100)) %", icon: "checkmark.seal")
                        StatTile(title: "Vorrat", value: "\(store.stock)", icon: "pills")
                    }
                    if store.stock <= 7 {
                        Label("Vorrat reicht nur noch für ca. \(store.daysOfStockLeft) Tage", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    calendar
                    if let test = store.nextTest {
                        Card {
                            Label("Nächster Kontrolltermin", systemImage: "cross.case")
                                .font(.caption).foregroundStyle(.secondary)
                            Text(test.formatted(date: .complete, time: .omitted)).font(.headline)
                            Text("in \(max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: test)).day ?? 0)) Tagen")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    history
                }
                .padding()
            }
            .navigationTitle("PrEP")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3") }
            }
            .sheet(isPresented: $showSettings) { PrepSettingsView() }
        }
    }

    private var doseButton: some View {
        Group {
            if store.mode == .daily {
                Button {
                    if !store.takenToday { store.logDose() }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: store.takenToday ? "checkmark.circle.fill" : "pills.circle")
                            .font(.system(size: 64))
                        Text(store.takenToday ? "Heute genommen" : "Jetzt genommen")
                            .font(.title3.weight(.semibold))
                        if let last = store.doses.first, store.takenToday {
                            Text("um \(last.date.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .foregroundStyle(store.takenToday ? Theme.accent : .white)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: store.takenToday)
            } else {
                Card {
                    Text("Bei Bedarf (2-1-1)").font(.headline)
                    Text("2 Tabletten 2–24 h vorher, dann je 1 Tablette nach 24 h und 48 h. Erinnerungen werden automatisch gesetzt.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("2-1-1 starten") { store.startOnDemand() }.buttonStyle(.borderedProminent)
                        Button("1 Tablette genommen") { store.logDose() }.buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private var calendar: some View {
        let cal = Calendar.current
        let interval = cal.dateInterval(of: .month, for: month)!
        let firstWeekday = (cal.component(.weekday, from: interval.start) - cal.firstWeekday + 7) % 7
        let days = cal.range(of: .day, in: .month, for: month)!.count
        let cells: [Date?] = Array(repeating: nil, count: firstWeekday) +
            (0..<days).map { cal.date(byAdding: .day, value: $0, to: interval.start) }
        let symbols = Array(cal.veryShortStandaloneWeekdaySymbols[(cal.firstWeekday - 1)...] + cal.veryShortStandaloneWeekdaySymbols[..<(cal.firstWeekday - 1)])

        return Card {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: { Image(systemName: "chevron.right") }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 8) {
                ForEach(symbols.indices, id: \.self) { Text(symbols[$0]).font(.caption2).foregroundStyle(.secondary) }
                ForEach(cells.indices, id: \.self) { i in
                    if let day = cells[i] {
                        let taken = store.taken(on: day)
                        let isToday = cal.isDateInToday(day)
                        Text("\(cal.component(.day, from: day))")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(taken ? Theme.accent.opacity(0.85) : Color.clear))
                            .overlay(Circle().stroke(isToday ? Color.white : .clear, lineWidth: 1.5))
                            .foregroundStyle(taken ? Color.black : (day > Date() ? Color.secondary : Color.primary))
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }
        }
    }

    private var history: some View {
        Card {
            Text("Verlauf").font(.caption).foregroundStyle(.secondary)
            if store.doses.isEmpty {
                Text("Noch keine Einnahmen.").foregroundStyle(.secondary)
            }
            ForEach(store.doses.prefix(20)) { d in
                HStack {
                    Text(d.date.formatted(date: .abbreviated, time: .shortened))
                    Spacer()
                    Text("\(d.pills) Tbl.").foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .contextMenu {
                    Button("Löschen", role: .destructive) { store.delete([d.id]) }
                }
                Divider()
            }
        }
    }
}

struct PrepSettingsView: View {
    @Environment(PrepStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()
    @State private var hasTest = false
    @State private var testDate = Date()
    @State private var refill = 30
    @State private var backfill = Date()

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Einnahme") {
                    Picker("Modus", selection: $store.mode) {
                        ForEach(PrepMode.allCases) { Text($0.label).tag($0) }
                    }
                    if store.mode == .daily {
                        DatePicker("Erinnerung", selection: $time, displayedComponents: .hourAndMinute)
                            .onChange(of: time) { _, t in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: t)
                                store.reminderHour = c.hour ?? 9
                                store.reminderMinute = c.minute ?? 0
                            }
                    }
                    Toggle("Diskrete Mitteilungen", isOn: $store.discreet)
                }

                Section {
                    Stepper("Vorrat: \(store.stock) Tabletten", value: $store.stock, in: 0...500)
                    Stepper("Packung: \(refill)", value: $refill, in: 1...200)
                    Button("Neue Packung hinzufügen (+\(refill))") { store.stock += refill }
                } header: {
                    Text("Vorrat")
                } footer: {
                    Text("Bei 7 oder weniger Tabletten bekommst du eine Erinnerung.")
                }

                Section("Kontrolltermin") {
                    Toggle("Termin geplant", isOn: $hasTest)
                    if hasTest {
                        DatePicker("Datum", selection: $testDate, displayedComponents: .date)
                        Button("In 3 Monaten") {
                            testDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
                        }
                    }
                }

                Section("Vergessene Einnahme nachtragen") {
                    DatePicker("Zeitpunkt", selection: $backfill, in: ...Date())
                    Button("Nachtragen") { store.logDose(at: backfill) }
                }
            }
            .navigationTitle("PrEP-Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        store.nextTest = hasTest ? testDate : nil
                        dismiss()
                    }
                }
            }
            .onAppear {
                time = Calendar.current.date(bySettingHour: store.reminderHour, minute: store.reminderMinute, second: 0, of: Date()) ?? Date()
                hasTest = store.nextTest != nil
                testDate = store.nextTest ?? (Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date())
            }
        }
    }
}

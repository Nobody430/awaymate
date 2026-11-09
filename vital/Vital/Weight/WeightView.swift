import SwiftUI
import Charts

struct WeightView: View {
    @Environment(WeightStore.self) private var store
    @State private var range = 1
    @State private var adding = false
    @State private var editingGoal = false
    @State private var message: String?

    private let ranges: [(String, Int?)] = [("1M", 30), ("3M", 90), ("6M", 180), ("1J", 365), ("Alle", nil)]

    private var visible: [WeightStore.TrendPoint] {
        guard let days = ranges[range].1 else { return store.trendPoints }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return store.trendPoints.filter { $0.date >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    chartCard
                    stats
                    entriesCard
                }
                .padding()
            }
            .navigationTitle("Gewicht")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { editingGoal = true } label: { Label("Ziel & Größe", systemImage: "target") }
                        Button {
                            Task {
                                do {
                                    let n = try await store.importFromHealth()
                                    message = "\(n) Einträge aus Apple Health übernommen."
                                } catch {
                                    message = error.localizedDescription
                                }
                            }
                        } label: { Label("Aus Apple Health laden", systemImage: "heart") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                }
            }
            .sheet(isPresented: $adding) { AddWeightView() }
            .sheet(isPresented: $editingGoal) { GoalView() }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    private var header: some View {
        Card {
            Text("Trend").font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(store.currentTrend.map { "\($0.formatted(.number.precision(.fractionLength(1)))) kg" } ?? "–")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Spacer()
                if let rate = store.weeklyRate {
                    Label("\(rate > 0 ? "+" : "")\(rate.formatted(.number.precision(.fractionLength(2)))) kg/Woche",
                          systemImage: rate < 0 ? "arrow.down.right" : "arrow.up.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(rateColor(rate))
                }
            }
            if let goal = store.goal, let trend = store.currentTrend {
                let remaining = trend - goal
                Text("Noch \(abs(remaining).formatted(.number.precision(.fractionLength(1)))) kg bis zum Ziel (\(goal.clean) kg)")
                    .font(.subheadline)
                if let date = store.projectedGoalDate {
                    Text("Bei aktuellem Tempo erreicht am \(date.formatted(date: .long, time: .omitted))")
                        .font(.caption).foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func rateColor(_ rate: Double) -> Color {
        guard let goal = store.goal, let t = store.currentTrend else { return .secondary }
        return (goal - t) * rate > 0 ? Theme.accent : .orange
    }

    private var chartCard: some View {
        Card {
            Picker("Zeitraum", selection: $range) {
                ForEach(ranges.indices, id: \.self) { Text(ranges[$0].0).tag($0) }
            }
            .pickerStyle(.segmented)
            if visible.count >= 2 {
                Chart {
                    ForEach(visible) { p in
                        PointMark(x: .value("Datum", p.date), y: .value("Gewicht", p.kg))
                            .foregroundStyle(.gray.opacity(0.6))
                            .symbolSize(20)
                        LineMark(x: .value("Datum", p.date), y: .value("Trend", p.trend))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 3))
                            .interpolationMethod(.catmullRom)
                    }
                    if let goal = store.goal {
                        RuleMark(y: .value("Ziel", goal))
                            .foregroundStyle(.orange.opacity(0.7))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 220)
            } else {
                Text("Mindestens zwei Einträge für die Grafik.").font(.subheadline).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }

    private var stats: some View {
        let pts = store.trendPoints
        let first = pts.first?.trend
        return HStack(spacing: 10) {
            StatTile(title: "Gesamt", value: first.flatMap { f in store.currentTrend.map { "\(($0 - f) > 0 ? "+" : "")\(($0 - f).formatted(.number.precision(.fractionLength(1)))) kg" } } ?? "–")
            StatTile(title: "BMI", value: store.bmi.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–")
            StatTile(title: "Einträge", value: "\(pts.count)")
        }
    }

    private var entriesCard: some View {
        Card {
            Text("Einträge").font(.caption).foregroundStyle(.secondary)
            ForEach(Array(store.trendPoints.suffix(30).reversed())) { p in
                HStack {
                    Text(p.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    Text("\(p.kg.formatted(.number.precision(.fractionLength(1)))) kg").monospacedDigit()
                    Text("Trend \(p.trend.formatted(.number.precision(.fractionLength(1))))")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                }
                .font(.subheadline)
                .contextMenu {
                    Button("Löschen", role: .destructive) {
                        if let e = store.entries.first(where: { $0.date == p.date }) { store.delete([e.id]) }
                    }
                }
                Divider()
            }
        }
    }
}

struct AddWeightView: View {
    @Environment(WeightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kg: Double = 75
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Gewicht", value: $kg, format: .number.precision(.fractionLength(1)))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text("kg").font(.title2).foregroundStyle(.secondary)
                }
                Stepper("± 0.1 kg", value: $kg, step: 0.1)
                DatePicker("Datum", selection: $date)
            }
            .navigationTitle("Gewicht eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.add(kg, at: date)
                        dismiss()
                    }
                    .disabled(kg <= 20 || kg > 400)
                }
            }
            .onAppear { if let last = store.entries.last { kg = last.kg } }
        }
    }
}

struct GoalView: View {
    @Environment(WeightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var goal: Double = 70
    @State private var height: Double = 175
    @State private var hasGoal = true

    var body: some View {
        NavigationStack {
            Form {
                Toggle("Zielgewicht", isOn: $hasGoal)
                if hasGoal {
                    Stepper("\(goal.clean) kg", value: $goal, in: 30...250, step: 0.5)
                }
                Stepper("Größe: \(Int(height)) cm", value: $height, in: 120...230)
            }
            .navigationTitle("Ziel & Größe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.goal = hasGoal ? goal : nil
                        store.heightCm = height
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let g = store.goal { goal = g } else { hasGoal = store.entries.isEmpty }
                if let h = store.heightCm { height = h }
            }
        }
    }
}

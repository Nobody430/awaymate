import Foundation
import Observation

struct WeightEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var kg: Double
}

@MainActor
@Observable
final class WeightStore {
    static let shared = WeightStore()

    private struct Snapshot: Codable {
        var entries: [WeightEntry]
        var goal: Double?
        var heightCm: Double?
    }

    private(set) var entries: [WeightEntry] = []
    var goal: Double? { didSet { save() } }
    var heightCm: Double? { didSet { save() } }
    private let file = "weight.json"

    init() {
        if let s = Disk.load(Snapshot.self, file) {
            entries = s.entries.sorted { $0.date < $1.date }
            goal = s.goal
            heightCm = s.heightCm
        }
    }

    private func save() {
        Disk.save(Snapshot(entries: entries, goal: goal, heightCm: heightCm), file)
    }

    func add(_ kg: Double, at date: Date = Date(), syncToHealth: Bool = true) {
        entries.append(WeightEntry(date: date, kg: kg))
        entries.sort { $0.date < $1.date }
        save()
        if syncToHealth, UserDefaults.standard.object(forKey: "healthSync") as? Bool ?? true {
            Task { try? await Health.shared.saveWeight(kg, at: date) }
        }
    }

    func delete(_ ids: [UUID]) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    /// Imports body mass samples from Apple Health that aren't stored yet.
    func importFromHealth() async throws -> Int {
        try await Health.shared.requestAuthorization()
        let since = Calendar.current.date(byAdding: .year, value: -5, to: Date()) ?? .distantPast
        let samples = try await Health.shared.weights(since: since)
        var added = 0
        for s in samples where !entries.contains(where: { abs($0.date.timeIntervalSince(s.date)) < 60 }) {
            entries.append(WeightEntry(date: s.date, kg: s.kg))
            added += 1
        }
        entries.sort { $0.date < $1.date }
        save()
        return added
    }

    // MARK: Trend (time-weighted exponential moving average)

    struct TrendPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let kg: Double
        let trend: Double
    }

    var trendPoints: [TrendPoint] {
        var result: [TrendPoint] = []
        var trend: Double?
        var lastDate: Date?
        for e in entries {
            if let t = trend, let last = lastDate {
                let days = max(e.date.timeIntervalSince(last) / 86400, 0.1)
                let alpha = 1 - pow(0.9, days)
                trend = t + alpha * (e.kg - t)
            } else {
                trend = e.kg
            }
            lastDate = e.date
            result.append(TrendPoint(date: e.date, kg: e.kg, trend: trend ?? e.kg))
        }
        return result
    }

    var currentTrend: Double? { trendPoints.last?.trend }

    /// kg per week, linear regression of the trend over the last 28 days
    var weeklyRate: Double? {
        let cutoff = Date().addingTimeInterval(-28 * 86400)
        let pts = trendPoints.filter { $0.date >= cutoff }
        guard pts.count >= 3, let first = pts.first?.date else { return nil }
        let xs = pts.map { $0.date.timeIntervalSince(first) / 86400 }
        let ys = pts.map(\.trend)
        let n = Double(pts.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    var projectedGoalDate: Date? {
        guard let goal, let trend = currentTrend, let rate = weeklyRate, abs(rate) > 0.01 else { return nil }
        let diff = goal - trend
        guard diff * rate > 0 else { return nil }
        let weeks = diff / rate
        guard weeks < 260 else { return nil }
        return Date().addingTimeInterval(weeks * 7 * 86400)
    }

    var bmi: Double? {
        guard let h = heightCm, h > 0, let t = currentTrend else { return nil }
        return t / pow(h / 100, 2)
    }
}

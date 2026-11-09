import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class TrainingStore {
    static let shared = TrainingStore()

    private struct Snapshot: Codable {
        var exercises: [Exercise]
        var templates: [WorkoutTemplate]
        var workouts: [Workout]
        var active: Workout?
    }

    private(set) var exercises: [Exercise] = []
    private(set) var templates: [WorkoutTemplate] = []
    private(set) var workouts: [Workout] = []
    private(set) var active: Workout?

    var restEnd: Date?
    private let file = "training.json"

    init() {
        if let s = Disk.load(Snapshot.self, file) {
            exercises = s.exercises
            templates = s.templates
            workouts = s.workouts
            active = s.active
            // Link built-in exercises to the exercise database (images + instructions)
            let defaults = Dictionary(ExerciseLibrary.defaults().map { ($0.name, $0.dbID) }, uniquingKeysWith: { a, _ in a })
            for i in exercises.indices where exercises[i].dbID == nil {
                exercises[i].dbID = defaults[exercises[i].name] ?? nil
            }
        } else {
            exercises = ExerciseLibrary.defaults()
            templates = Self.starterTemplates(exercises)
            save()
        }
    }

    private func save() {
        Disk.save(Snapshot(exercises: exercises, templates: templates, workouts: workouts, active: active), file)
    }

    func exercise(_ id: UUID) -> Exercise? { exercises.first { $0.id == id } }

    /// Returns the library exercise for a database entry, creating it if needed.
    func exercise(forDB db: DBExercise, germanName: String? = nil) -> Exercise {
        if let e = exercises.first(where: { $0.dbID == db.id }) { return e }
        var e = Exercise(name: germanName ?? db.name, muscle: db.muscleGroup)
        e.dbID = db.id
        e.bodyweight = db.equipment == "body only"
        e.increment = e.bodyweight ? 0 : ([.beine, .ruecken, .po].contains(e.muscle) ? 5 : 2.5)
        if e.bodyweight { e.repMin = 8; e.repMax = 15 }
        exercises.append(e)
        save()
        return e
    }

    /// Imports finished workouts (e.g. from another app's CSV export).
    func importWorkouts(_ new: [Workout]) -> Int {
        let existing = Set(workouts.map { $0.start })
        let fresh = new.filter { !existing.contains($0.start) }
        workouts.append(contentsOf: fresh)
        workouts.sort { $0.start > $1.start }
        save()
        return fresh.count
    }

    /// Finds an exercise by (case-insensitive) name or creates it.
    func exercise(named name: String) -> Exercise {
        let key = name.trimmingCharacters(in: .whitespaces)
        if let e = exercises.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame }) { return e }
        let e = Exercise(name: key, muscle: .ganzkoerper)
        exercises.append(e)
        save()
        return e
    }

    // MARK: Exercises & templates

    func upsert(_ e: Exercise) {
        if let i = exercises.firstIndex(where: { $0.id == e.id }) { exercises[i] = e } else { exercises.append(e) }
        save()
    }

    func deleteExercises(_ ids: [UUID]) {
        exercises.removeAll { ids.contains($0.id) }
        save()
    }

    func upsert(_ t: WorkoutTemplate) {
        if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i] = t } else { templates.append(t) }
        save()
    }

    func deleteTemplates(_ ids: [UUID]) {
        templates.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: Workout lifecycle

    func start(template: WorkoutTemplate?) {
        var w = Workout(name: template?.name ?? "Freies Training", start: Date())
        for item in template?.items ?? [] {
            var entry = makeEntry(item.exerciseID, sets: item.sets)
            entry.restSeconds = item.restSeconds
            entry.note = item.note
            w.entries.append(entry)
        }
        active = w
        save()
    }

    func makeEntry(_ exerciseID: UUID, sets: Int? = nil) -> WorkoutEntry {
        let s = suggestion(for: exerciseID)
        let count = sets ?? s.sets
        return WorkoutEntry(exerciseID: exerciseID,
                            sets: (0..<max(count, 1)).map { _ in SetEntry(weight: s.weight, reps: s.reps) })
    }

    func updateActive(_ w: Workout) {
        active = w
        save()
    }

    func finish() {
        guard var w = active else { return }
        w.end = Date()
        w.entries = w.entries.compactMap { e in
            var e = e
            e.sets = e.sets.filter(\.done)
            return e.sets.isEmpty ? nil : e
        }
        active = nil
        restEnd = nil
        if !w.entries.isEmpty { workouts.insert(w, at: 0) }
        save()
        if UserDefaults.standard.object(forKey: "healthSync") as? Bool ?? true, let end = w.end {
            Task { try? await Health.shared.saveStrengthWorkout(start: w.start, end: end) }
        }
    }

    func discard() {
        active = nil
        restEnd = nil
        save()
    }

    func deleteWorkouts(_ ids: [UUID]) {
        workouts.removeAll { ids.contains($0.id) }
        save()
    }

    // MARK: Rest timer

    var restSeconds: Int {
        get { UserDefaults.standard.object(forKey: "restSeconds") as? Int ?? 120 }
        set { UserDefaults.standard.set(newValue, forKey: "restSeconds") }
    }

    func restSeconds(for entry: WorkoutEntry) -> Int {
        entry.restSeconds ?? exercise(entry.exerciseID)?.restSeconds ?? restSeconds
    }

    func startRest(_ seconds: Int? = nil) {
        let s = seconds ?? restSeconds
        restEnd = Date().addingTimeInterval(TimeInterval(s))
        let content = UNMutableNotificationContent()
        content.title = "Pause vorbei"
        content.body = "Weiter geht's mit dem nächsten Satz 💪"
        content.sound = .default
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["rest"])
        center.add(UNNotificationRequest(identifier: "rest", content: content,
                                         trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(s, 1)), repeats: false)))
    }

    func adjustRest(_ delta: TimeInterval) {
        guard let end = restEnd else { return }
        let remaining = end.addingTimeInterval(delta).timeIntervalSinceNow
        if remaining <= 0 { stopRest() } else { startRest(Int(remaining)) }
    }

    func stopRest() {
        restEnd = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["rest"])
    }

    // MARK: Progression

    struct Suggestion { var weight: Double; var reps: Int; var sets: Int; var note: String }

    func lastEntry(for exerciseID: UUID) -> (Workout, WorkoutEntry)? {
        for w in workouts {
            if let e = w.entries.first(where: { $0.exerciseID == exerciseID }) { return (w, e) }
        }
        return nil
    }

    /// Double progression: hit the top of the rep range in all sets → add weight, otherwise add reps.
    func suggestion(for exerciseID: UUID) -> Suggestion {
        let ex = exercise(exerciseID)
        let repMin = ex?.repMin ?? 8, repMax = ex?.repMax ?? 12
        guard let last = lastEntry(for: exerciseID)?.1, !last.sets.isEmpty else {
            return Suggestion(weight: ex?.bodyweight == true ? 0 : 20, reps: repMin, sets: 3, note: "Erstes Mal – Startgewicht wählen")
        }
        let topWeight = last.sets.map(\.weight).max() ?? 0
        let working = last.sets.filter { $0.weight == topWeight }
        let minReps = working.map(\.reps).min() ?? repMin
        if minReps >= repMax, let ex, ex.increment > 0 {
            return Suggestion(weight: topWeight + ex.increment, reps: repMin, sets: last.sets.count,
                              note: "Alle Sätze geschafft → +\(ex.increment.clean) kg")
        }
        let target = min(max(minReps + 1, repMin), repMax)
        return Suggestion(weight: topWeight, reps: target, sets: last.sets.count,
                          note: "Ziel: \(target) Wdh. in allen Sätzen")
    }

    func lastSummary(for exerciseID: UUID) -> String? {
        guard let found = lastEntry(for: exerciseID) else { return nil }
        let (w, e) = found
        let sets = e.sets.map { "\($0.weight.clean)×\($0.reps)" }.joined(separator: ", ")
        return "Letztes Mal (\(w.start.formatted(.dateTime.day().month()))): \(sets)"
    }

    struct HistoryPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let e1rm: Double
        let topWeight: Double
        let volume: Double
    }

    func history(for exerciseID: UUID) -> [HistoryPoint] {
        workouts.compactMap { w in
            guard let e = w.entries.first(where: { $0.exerciseID == exerciseID }), !e.sets.isEmpty else { return nil }
            return HistoryPoint(
                date: w.start,
                e1rm: e.sets.map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }.max() ?? 0,
                topWeight: e.sets.map(\.weight).max() ?? 0,
                volume: e.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
            )
        }
        .sorted { $0.date < $1.date }
    }

    func isRecord(_ set: SetEntry, exerciseID: UUID) -> Bool {
        let best = history(for: exerciseID).map(\.e1rm).max() ?? 0
        return set.done && set.weight > 0 && estimatedOneRepMax(weight: set.weight, reps: set.reps) > best && best > 0
    }

    var workoutsThisWeek: Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return workouts.filter { $0.start >= start }.count
    }

    var streakWeeks: Int {
        let cal = Calendar.current
        var week = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        var count = 0
        if !workouts.contains(where: { $0.start >= week }) {
            week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        while workouts.contains(where: { $0.start >= week && $0.start < (cal.date(byAdding: .weekOfYear, value: 1, to: week) ?? week) }) {
            count += 1
            week = cal.date(byAdding: .weekOfYear, value: -1, to: week) ?? week
        }
        return count
    }

    private static func starterTemplates(_ ex: [Exercise]) -> [WorkoutTemplate] {
        func id(_ name: String) -> UUID? { ex.first { $0.name == name }?.id }
        func t(_ name: String, _ names: [String]) -> WorkoutTemplate {
            WorkoutTemplate(name: name, items: names.compactMap(id).map { TemplateItem(exerciseID: $0) })
        }
        return [
            t("Push", ["Bankdrücken (Langhantel)", "Schrägbankdrücken (Kurzhantel)", "Schulterdrücken (Kurzhantel)", "Seitheben", "Trizepsdrücken (Kabel)"]),
            t("Pull", ["Klimmzüge", "Rudern (Langhantel)", "Latzug", "Face Pulls", "Bizepscurls (Kurzhantel)"]),
            t("Beine", ["Kniebeugen", "Rumänisches Kreuzheben", "Beinpresse", "Beinbeuger", "Wadenheben stehend"]),
        ]
    }
}

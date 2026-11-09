import Foundation

enum MuscleGroup: String, Codable, CaseIterable, Identifiable {
    case brust, ruecken, schultern, bizeps, trizeps, beine, po, waden, bauch, ganzkoerper
    var id: String { rawValue }
    var label: String {
        switch self {
        case .brust: "Brust"
        case .ruecken: "Rücken"
        case .schultern: "Schultern"
        case .bizeps: "Bizeps"
        case .trizeps: "Trizeps"
        case .beine: "Beine"
        case .po: "Po"
        case .waden: "Waden"
        case .bauch: "Bauch"
        case .ganzkoerper: "Ganzkörper"
        }
    }
}

struct Exercise: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var muscle: MuscleGroup
    var increment: Double = 2.5
    var repMin: Int = 8
    var repMax: Int = 12
    var bodyweight: Bool = false
    /// ID in the free exercise database (images + instructions)
    var dbID: String? = nil
    var restSeconds: Int? = nil
}

struct SetEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var weight: Double
    var reps: Int
    var done: Bool = false
}

struct WorkoutEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var exerciseID: UUID
    var sets: [SetEntry]
    var restSeconds: Int? = nil
    var note: String? = nil
}

struct Workout: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var start: Date
    var end: Date?
    var entries: [WorkoutEntry] = []

    var doneSets: Int { entries.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    var volume: Double {
        entries.reduce(0) { total, e in total + e.sets.filter(\.done).reduce(0) { $0 + $1.weight * Double($1.reps) } }
    }
    var duration: TimeInterval { (end ?? Date()).timeIntervalSince(start) }
}

struct TemplateItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var exerciseID: UUID
    var sets: Int = 3
    var repMin: Int? = nil
    var repMax: Int? = nil
    var rir: Int? = nil
    var restSeconds: Int? = nil
    var note: String? = nil
}

struct WorkoutTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var items: [TemplateItem] = []
    var aiGenerated: Bool? = nil
}

/// Epley estimated one-rep max
func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
    guard reps > 0 else { return 0 }
    return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
}

enum ExerciseLibrary {
    static func defaults() -> [Exercise] {
        let list: [(String, MuscleGroup, Bool)] = [
            ("Bankdrücken (Langhantel)", .brust, false), ("Schrägbankdrücken (Kurzhantel)", .brust, false),
            ("Brustpresse (Maschine)", .brust, false), ("Butterfly (Kabel)", .brust, false), ("Dips", .brust, true),
            ("Liegestütze", .brust, true),
            ("Klimmzüge", .ruecken, true), ("Latzug", .ruecken, false), ("Rudern (Langhantel)", .ruecken, false),
            ("Rudern (Kabel, sitzend)", .ruecken, false), ("Einarmiges Kurzhantelrudern", .ruecken, false),
            ("Kreuzheben", .ruecken, false), ("Hyperextensions", .ruecken, true),
            ("Schulterdrücken (Kurzhantel)", .schultern, false), ("Military Press", .schultern, false),
            ("Seitheben", .schultern, false), ("Face Pulls", .schultern, false), ("Reverse Butterfly", .schultern, false),
            ("Bizepscurls (Kurzhantel)", .bizeps, false), ("SZ-Curls", .bizeps, false), ("Hammercurls", .bizeps, false),
            ("Kabelcurls", .bizeps, false),
            ("Trizepsdrücken (Kabel)", .trizeps, false), ("French Press", .trizeps, false),
            ("Überkopf-Trizeps (Kabel)", .trizeps, false), ("Enges Bankdrücken", .trizeps, false),
            ("Kniebeugen", .beine, false), ("Beinpresse", .beine, false), ("Ausfallschritte", .beine, false),
            ("Beinstrecker", .beine, false), ("Beinbeuger", .beine, false), ("Rumänisches Kreuzheben", .beine, false),
            ("Bulgarian Split Squats", .beine, false),
            ("Hip Thrust", .po, false), ("Abduktoren (Maschine)", .po, false),
            ("Wadenheben stehend", .waden, false), ("Wadenheben sitzend", .waden, false),
            ("Crunches", .bauch, true), ("Beinheben hängend", .bauch, true), ("Plank (Sekunden)", .bauch, true),
            ("Kabel-Crunch", .bauch, false),
        ]
        let dbIDs = [
            "Barbell_Bench_Press_-_Medium_Grip",
            "Incline_Dumbbell_Press",
            "Leverage_Chest_Press",
            "Cable_Crossover",
            "Dips_-_Chest_Version",
            "Pushups",
            "Pullups",
            "Wide-Grip_Lat_Pulldown",
            "Bent_Over_Barbell_Row",
            "Seated_Cable_Rows",
            "One-Arm_Dumbbell_Row",
            "Barbell_Deadlift",
            "Hyperextensions_Back_Extensions",
            "Dumbbell_Shoulder_Press",
            "Standing_Military_Press",
            "Side_Lateral_Raise",
            "Face_Pull",
            "Reverse_Machine_Flyes",
            "Dumbbell_Bicep_Curl",
            "EZ-Bar_Curl",
            "Hammer_Curls",
            "Standing_Biceps_Cable_Curl",
            "Triceps_Pushdown",
            "EZ-Bar_Skullcrusher",
            "Cable_Rope_Overhead_Triceps_Extension",
            "Close-Grip_Barbell_Bench_Press",
            "Barbell_Squat",
            "Leg_Press",
            "Dumbbell_Lunges",
            "Leg_Extensions",
            "Lying_Leg_Curls",
            "Romanian_Deadlift",
            "Split_Squat_with_Dumbbells",
            "Barbell_Hip_Thrust",
            "Thigh_Abductor",
            "Standing_Calf_Raises",
            "Seated_Calf_Raise",
            "Crunches",
            "Hanging_Leg_Raise",
            "Plank",
            "Cable_Crunch",
        ]
        return list.enumerated().map { index, item in
            let (name, muscle, bw) = item
            var e = Exercise(name: name, muscle: muscle, bodyweight: bw)
            if index < dbIDs.count { e.dbID = dbIDs[index] }
            if [.beine, .ruecken].contains(muscle) && !bw { e.increment = 5 }
            if [.bizeps, .trizeps, .schultern].contains(muscle) { e.increment = 1 }
            if bw { e.repMin = 8; e.repMax = 15; e.increment = 0 }
            return e
        }
    }
}

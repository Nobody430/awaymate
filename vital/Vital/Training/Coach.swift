import Foundation

struct CoachProfile: Codable, Equatable {
    var goal = "Muskelaufbau"
    var level = "Fortgeschritten"
    var daysPerWeek = 4
    var minutes = 60
    var equipment = "Fitnessstudio"
    var focus: [MuscleGroup] = []
    var limitations = ""
    var wishes = ""

    static let goals = ["Muskelaufbau", "Kraft", "Muskelaufbau + Kraft", "Fett verlieren, Muskeln halten", "Allgemeine Fitness"]
    static let levels = ["Anfänger (< 1 Jahr)", "Fortgeschritten (1–3 Jahre)", "Erfahren (> 3 Jahre)"]
    static let equipments = ["Fitnessstudio", "Zuhause: Kurzhanteln + Bank", "Nur Körpergewicht / Bänder"]

    static var saved: CoachProfile {
        get {
            guard let data = UserDefaults.standard.data(forKey: "coachProfile"),
                  let p = try? JSONDecoder().decode(CoachProfile.self, from: data) else { return CoachProfile() }
            return p
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "coachProfile") }
    }
}

struct CoachPlan: Codable {
    struct PlannedExercise: Codable, Hashable {
        let catalogId: String
        let germanName: String
        let sets: Int
        let repMin: Int
        let repMax: Int
        let rir: Int
        let restSeconds: Int
        let cue: String
    }
    struct Day: Codable, Hashable {
        let name: String
        let exercises: [PlannedExercise]
    }
    let planName: String
    let summary: String
    let days: [Day]
    let progression: String
    let deload: String

    static var saved: CoachPlan? {
        get { UserDefaults.standard.data(forKey: "coachPlan").flatMap { try? JSONDecoder().decode(CoachPlan.self, from: $0) } }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "coachPlan") }
    }

    static let schema: [String: Any] = {
        let exercise: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["catalogId", "germanName", "sets", "repMin", "repMax", "rir", "restSeconds", "cue"],
            "properties": [
                "catalogId": ["type": "string", "description": "ID exactly as listed in the catalog"],
                "germanName": ["type": "string"],
                "sets": ["type": "integer"],
                "repMin": ["type": "integer"],
                "repMax": ["type": "integer"],
                "rir": ["type": "integer", "description": "Target reps in reserve on the last set"],
                "restSeconds": ["type": "integer"],
                "cue": ["type": "string", "description": "One short German technique cue"],
            ],
        ]
        let day: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["name", "exercises"],
            "properties": ["name": ["type": "string"], "exercises": ["type": "array", "items": exercise]],
        ]
        return [
            "type": "object", "additionalProperties": false,
            "required": ["planName", "summary", "days", "progression", "deload"],
            "properties": [
                "planName": ["type": "string"],
                "summary": ["type": "string"],
                "days": ["type": "array", "items": day],
                "progression": ["type": "string"],
                "deload": ["type": "string"],
            ],
        ]
    }()
}

@MainActor
enum Coach {
    static let system = """
    Du bist ein evidenzbasierter Krafttrainings-Coach. Erstelle einen Trainingsplan auf Deutsch (Schweizer Schreibweise, kein ß), \
    der dem aktuellen Stand der Trainingswissenschaft entspricht und zu Ziel, Erfahrung, Zeit und Ausrüstung der Person passt.

    Leitlinien, an denen du dich orientierst (und begründest, wo du abweichst):
    - Muskelaufbau: pro Muskelgruppe etwa 10–20 harte Sätze pro Woche (Anfänger eher am unteren Ende), jede Muskelgruppe mindestens 2× pro Woche.
    - Sätze nah ans Muskelversagen: meist 0–3 Wiederholungen in Reserve (RIR); Grundübungen eher 1–3 RIR, Isolationsübungen 0–2 RIR.
    - Wiederholungsbereiche von ca. 5–30 sind für Hypertrophie wirksam; praktisch: Grundübungen 5–10, Maschinen/Kabel 8–15, Isolation 10–20.
    - Kraft: Hauptübungen häufiger und schwerer (ca. 3–6 Wdh.), ergänzt durch Hypertrophie-Volumen.
    - Übungen bevorzugen, die den Muskel in gedehnter Position stark belasten (z.B. Rumänisches Kreuzheben, Schrägbank-Curls, Überkopf-Trizeps, tiefe Kniebeugen/Beinpresse), und stabile Varianten (Maschinen, Kabel), die sich gut progressiv steigern lassen.
    - Pausen: Grundübungen 2–3 Minuten, Isolation 1–2 Minuten.
    - Progression per Doppelprogression: erst Wiederholungen bis zum oberen Ende des Bereichs, dann Gewicht erhöhen.
    - Deload etwa alle 4–8 Wochen oder bei Leistungsabfall/Erschöpfung (Volumen ca. halbieren).
    - Mehrgelenkige Übungen zuerst; Einheit muss realistisch in die angegebene Zeit passen (inkl. Pausen).
    - Rücksicht auf genannte Beschwerden: belastende Übungen ersetzen, keine medizinischen Diagnosen stellen.
    - Bei Fettabbau: Volumen und Intensität weitgehend beibehalten, um Muskeln zu erhalten.

    Verwende ausschliesslich Übungen aus dem mitgelieferten Katalog und gib deren catalogId exakt so an, wie sie im Katalog steht. \
    Bevorzuge Übungen, die die Person bereits trainiert (mit "lib:" gekennzeichnet), wenn sie gut passen. \
    "germanName" ist ein kurzer, gebräuchlicher deutscher Name. "summary" erklärt in 3–5 Sätzen den Aufbau und warum er passt. \
    "progression" und "deload" sind kurze, konkrete Anleitungen.
    """

    static func catalog(store: TrainingStore, db: ExerciseDatabase, equipment: String) -> String {
        let allowed: Set<String>? = switch equipment {
        case "Zuhause: Kurzhanteln + Bank": ["dumbbell", "body only", "bands", "kettlebells", "other"]
        case "Nur Körpergewicht / Bänder": ["body only", "bands", "other"]
        default: nil
        }
        var lines = store.exercises.map { e in
            "lib:\(e.id.uuidString)\t\(e.name)\t\(e.muscle.label)\t\(e.dbID.flatMap { db.entry($0)?.equipment } ?? "")"
        }
        let linked = Set(store.exercises.compactMap(\.dbID))
        for e in db.strength where !linked.contains(e.id) && (allowed == nil || allowed!.contains(e.equipment ?? "other")) {
            lines.append("\(e.id)\t\(e.name)\t\(e.primaryMuscles.joined(separator: ","))\t\(e.equipment ?? "")\t\(e.mechanic ?? "")")
        }
        return lines.joined(separator: "\n")
    }

    static func historySummary(store: TrainingStore) -> String {
        let cutoff = Date().addingTimeInterval(-56 * 86400)
        let recent = store.workouts.filter { $0.start >= cutoff }
        guard !recent.isEmpty else { return "Keine Trainingsdaten der letzten 8 Wochen." }
        var lines = ["Trainings in den letzten 8 Wochen: \(recent.count) (ca. \(String(format: "%.1f", Double(recent.count) / 8)) pro Woche)."]
        let ids = Set(recent.flatMap { $0.entries.map(\.exerciseID) })
        for id in ids {
            guard let e = store.exercise(id) else { continue }
            let h = store.history(for: id).filter { $0.date >= cutoff }
            if let best = h.map(\.e1rm).max() {
                lines.append("- \(e.name): \(h.count)× trainiert, bestes geschätztes 1RM \(Int(best)) kg")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func generate(profile: CoachProfile, store: TrainingStore, db: ExerciseDatabase, previous: CoachPlan?) async throws -> CoachPlan {
        await db.loadIfNeeded()
        var user = """
        Profil:
        - Ziel: \(profile.goal)
        - Erfahrung: \(profile.level)
        - Trainingstage pro Woche: \(profile.daysPerWeek)
        - Zeit pro Einheit: \(profile.minutes) Minuten
        - Ausrüstung: \(profile.equipment)
        - Schwerpunkte: \(profile.focus.isEmpty ? "ausgewogen" : profile.focus.map(\.label).joined(separator: ", "))
        - Beschwerden/Einschränkungen: \(profile.limitations.isEmpty ? "keine" : profile.limitations)
        - Wünsche: \(profile.wishes.isEmpty ? "keine" : profile.wishes)

        Bisheriges Training:
        \(historySummary(store: store))
        """
        if let previous, let json = try? JSONEncoder().encode(previous), let s = String(data: json, encoding: .utf8) {
            user += "\n\nBisheriger Plan (überarbeiten, die Wünsche oben berücksichtigen):\n\(s)"
        }
        user += "\n\nKatalog (catalogId<TAB>Name<TAB>Muskeln<TAB>Gerät<TAB>Mechanik):\n" + catalog(store: store, db: db, equipment: profile.equipment)

        let text = try await AIClient.send(system: system, user: user, schema: CoachPlan.schema, effort: "high", maxTokens: 16000)
        return try JSONDecoder().decode(CoachPlan.self, from: Data(text.utf8))
    }

    /// Turns the plan into workout templates. Returns the number of days created.
    @discardableResult
    static func apply(_ plan: CoachPlan, store: TrainingStore, db: ExerciseDatabase, replaceOld: Bool) -> Int {
        if replaceOld {
            store.deleteTemplates(store.templates.filter { $0.aiGenerated == true }.map(\.id))
        }
        for day in plan.days {
            var template = WorkoutTemplate(name: day.name, aiGenerated: true)
            for p in day.exercises {
                var exercise: Exercise
                if p.catalogId.hasPrefix("lib:"), let id = UUID(uuidString: String(p.catalogId.dropFirst(4))), let e = store.exercise(id) {
                    exercise = e
                } else if let entry = db.entry(p.catalogId) {
                    exercise = store.exercise(forDB: entry, germanName: p.germanName)
                } else {
                    exercise = store.exercise(named: p.germanName)
                }
                exercise.repMin = max(1, p.repMin)
                exercise.repMax = max(exercise.repMin, p.repMax)
                exercise.restSeconds = p.restSeconds
                store.upsert(exercise)
                template.items.append(TemplateItem(
                    exerciseID: exercise.id, sets: max(1, p.sets), repMin: p.repMin, repMax: p.repMax,
                    rir: p.rir, restSeconds: p.restSeconds,
                    note: "\(p.repMin)–\(p.repMax) Wdh. · \(p.rir) RIR · \(p.cue)"))
            }
            store.upsert(template)
        }
        CoachPlan.saved = plan
        return plan.days.count
    }
}

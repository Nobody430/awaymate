import Foundation
import Observation

/// Entry of the free, public-domain exercise database (github.com/yuhonas/free-exercise-db).
struct DBExercise: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructions: [String]
    let category: String?
    let images: [String]

    static let imageBase = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

    var imageURLs: [URL] { images.compactMap { URL(string: Self.imageBase + $0) } }

    var youtubeURL: URL? {
        var c = URLComponents(string: "https://www.youtube.com/results")
        c?.queryItems = [URLQueryItem(name: "search_query", value: "\(name) exercise proper form")]
        return c?.url
    }

    var muscleGroup: MuscleGroup {
        switch primaryMuscles.first ?? "" {
        case "chest": .brust
        case "lats", "middle back", "lower back", "traps": .ruecken
        case "shoulders", "neck": .schultern
        case "biceps", "forearms": .bizeps
        case "triceps": .trizeps
        case "quadriceps", "hamstrings", "adductors": .beine
        case "glutes", "abductors": .po
        case "calves": .waden
        case "abdominals": .bauch
        default: .ganzkoerper
        }
    }

    static func germanMuscle(_ m: String) -> String {
        [
            "chest": "Brust", "lats": "Latissimus", "middle back": "Mittlerer Rücken", "lower back": "Unterer Rücken",
            "traps": "Trapez", "shoulders": "Schultern", "neck": "Nacken", "biceps": "Bizeps", "forearms": "Unterarme",
            "triceps": "Trizeps", "quadriceps": "Quadrizeps", "hamstrings": "Beinbeuger", "adductors": "Adduktoren",
            "glutes": "Po", "abductors": "Abduktoren", "calves": "Waden", "abdominals": "Bauch",
        ][m] ?? m.capitalized
    }

    static func germanEquipment(_ e: String?) -> String {
        guard let e else { return "–" }
        return [
            "barbell": "Langhantel", "dumbbell": "Kurzhantel", "cable": "Kabelzug", "machine": "Maschine",
            "body only": "Körpergewicht", "kettlebells": "Kettlebell", "bands": "Bänder", "e-z curl bar": "SZ-Stange",
            "medicine ball": "Medizinball", "exercise ball": "Gymnastikball", "foam roll": "Faszienrolle", "other": "Sonstiges",
        ][e] ?? e
    }
}

@MainActor
@Observable
final class ExerciseDatabase {
    static let shared = ExerciseDatabase()
    static let sourceURL = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json")!

    private(set) var all: [DBExercise] = []
    private(set) var loading = false
    var error: String?
    private let cacheFile = "exercise-db.json"

    init() {
        if let cached = Disk.load([DBExercise].self, cacheFile) { all = cached }
    }

    func entry(_ id: String?) -> DBExercise? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    var strength: [DBExercise] {
        all.filter { ["strength", "powerlifting", "olympic weightlifting", "strongman"].contains($0.category ?? "") }
    }

    func loadIfNeeded() async {
        guard all.isEmpty, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.sourceURL)
            let list = try JSONDecoder().decode([DBExercise].self, from: data)
            all = list.sorted { $0.name < $1.name }
            Disk.save(all, cacheFile)
            error = nil
        } catch {
            self.error = "Übungsdatenbank konnte nicht geladen werden: \(error.localizedDescription)"
        }
    }
}

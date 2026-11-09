import Foundation
import Observation

struct FoodEntry: Identifiable, Codable, Hashable {
    var id = UUID()
    var date: Date
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var grams: Double?
    var source: String
}

@MainActor
@Observable
final class NutritionStore {
    static let shared = NutritionStore()

    private struct Snapshot: Codable {
        var entries: [FoodEntry]
        var kcalTarget: Double
        var proteinTarget: Double
        var favorites: [FoodEntry]?
    }

    private(set) var entries: [FoodEntry] = []
    private(set) var favorites: [FoodEntry] = []
    var kcalTarget: Double = 2200 { didSet { save() } }
    var proteinTarget: Double = 140 { didSet { save() } }
    private let file = "nutrition.json"
    private var loading = true

    init() {
        if let s = Disk.load(Snapshot.self, file) {
            entries = s.entries
            kcalTarget = s.kcalTarget
            proteinTarget = s.proteinTarget
            favorites = s.favorites ?? []
        }
        loading = false
    }

    private func save() {
        guard !loading else { return }
        Disk.save(Snapshot(entries: entries, kcalTarget: kcalTarget, proteinTarget: proteinTarget, favorites: favorites), file)
    }

    func add(_ e: FoodEntry) {
        entries.append(e)
        entries.sort { $0.date > $1.date }
        // remember as favourite for quick re-adding
        if !favorites.contains(where: { $0.name.lowercased() == e.name.lowercased() }) {
            favorites.insert(e, at: 0)
            favorites = Array(favorites.prefix(30))
        }
        save()
        if UserDefaults.standard.object(forKey: "healthSync") as? Bool ?? true {
            Task { try? await Health.shared.saveNutrition(kcal: e.kcal, protein: e.protein, carbs: e.carbs, fat: e.fat, at: e.date) }
        }
    }

    func delete(_ ids: [UUID]) {
        entries.removeAll { ids.contains($0.id) }
        save()
    }

    func entries(on day: Date) -> [FoodEntry] {
        entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.sorted { $0.date < $1.date }
    }

    func totals(on day: Date) -> (kcal: Double, protein: Double, carbs: Double, fat: Double) {
        entries(on: day).reduce((0, 0, 0, 0)) { ($0.0 + $1.kcal, $0.1 + $1.protein, $0.2 + $1.carbs, $0.3 + $1.fat) }
    }
}

/// Open Food Facts (free, open database) – nutrition per 100 g by barcode.
enum OpenFoodFacts {
    struct Product {
        let name: String
        let kcal100: Double
        let protein100: Double
        let carbs100: Double
        let fat100: Double
    }

    static func product(_ barcode: String) async throws -> Product? {
        var request = URLRequest(url: URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,product_name_de,brands,nutriments")!)
        request.setValue("Vital/1.0 (iOS; personal use)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let p = json["product"] as? [String: Any] else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func v(_ k: String) -> Double { (n[k] as? NSNumber)?.doubleValue ?? Double("\(n[k] ?? "")") ?? 0 }
        var kcal = v("energy-kcal_100g")
        if kcal == 0 { kcal = v("energy_100g") / 4.184 }
        let name = [(p["product_name_de"] as? String) ?? (p["product_name"] as? String), p["brands"] as? String]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " – ")
        return Product(name: name.isEmpty ? "Produkt \(barcode)" : name, kcal100: kcal,
                       protein100: v("proteins_100g"), carbs100: v("carbohydrates_100g"), fat100: v("fat_100g"))
    }
}

/// Estimates nutrients of a meal photo with Claude.
enum FoodVision {
    struct Item: Codable, Hashable {
        let name: String
        let grams: Double
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }
    struct Result: Codable { let items: [Item]; let note: String }

    static let schema: [String: Any] = {
        let item: [String: Any] = [
            "type": "object", "additionalProperties": false,
            "required": ["name", "grams", "kcal", "protein", "carbs", "fat"],
            "properties": ["name": ["type": "string"], "grams": ["type": "number"], "kcal": ["type": "number"],
                           "protein": ["type": "number"], "carbs": ["type": "number"], "fat": ["type": "number"]],
        ]
        return ["type": "object", "additionalProperties": false, "required": ["items", "note"],
                "properties": ["items": ["type": "array", "items": item], "note": ["type": "string"]]]
    }()

    static func analyse(jpeg: Data, hint: String) async throws -> Result {
        let text = try await AIClient.send(
            system: "Du bist Ernährungsberater. Schätze für das Foto einer Mahlzeit jede erkennbare Komponente mit Portionsgrösse in Gramm und Nährwerten (kcal, Protein, Kohlenhydrate, Fett in g). Realistische Portionen, lieber leicht höher schätzen. Namen auf Deutsch (Schweizer Schreibweise, kein ß). 'note' = ein kurzer Satz zur Unsicherheit oder ein Tipp.",
            imageJPEG: jpeg,
            text: hint.isEmpty ? "Bitte schätze die Nährwerte dieser Mahlzeit." : "Bitte schätze die Nährwerte dieser Mahlzeit. Zusatzinfo: \(hint)",
            schema: schema, effort: "medium", maxTokens: 6000)
        return try JSONDecoder().decode(Result.self, from: Data(text.utf8))
    }
}

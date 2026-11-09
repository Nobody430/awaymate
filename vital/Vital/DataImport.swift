import Foundation

/// Imports CSV exports from other apps (Alpha Progression, Strong, Hevy, Happy Scale, …).
/// Columns are detected by their header names, so most formats work without configuration.
@MainActor
enum DataImport {
    struct Table {
        let header: [String]
        let rows: [[String]]

        func column(_ keywords: [String], excluding: [String] = []) -> Int? {
            header.firstIndex { h in
                let l = h.lowercased()
                return keywords.contains { l.contains($0) } && !excluding.contains { l.contains($0) }
            }
        }
    }

    static func readText(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func parseCSV(_ text: String) -> Table {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let first = lines.first else { return Table(header: [], rows: []) }
        let candidates: [Character] = [";", ",", "\t"]
        let sep = candidates.max { a, b in first.filter { $0 == a }.count < first.filter { $0 == b }.count } ?? ","

        func split(_ line: String) -> [String] {
            var out: [String] = []
            var cur = ""
            var quoted = false
            for ch in line {
                if ch == "\"" { quoted.toggle() }
                else if ch == sep && !quoted { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
                else { cur.append(ch) }
            }
            out.append(cur.trimmingCharacters(in: .whitespaces))
            return out
        }
        return Table(header: split(first), rows: lines.dropFirst().map(split))
    }

    private static let dateFormats = [
        "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd",
        "dd.MM.yyyy HH:mm:ss", "dd.MM.yyyy HH:mm", "dd.MM.yyyy", "d.M.yyyy", "dd.MM.yy",
        "MM/dd/yyyy HH:mm", "MM/dd/yyyy", "M/d/yyyy", "d MMM yyyy, HH:mm", "d MMM yyyy", "MMM d, yyyy",
        "dd MMM yyyy, HH:mm",
    ]
    private static let formatters: [DateFormatter] = dateFormats.flatMap { f in
        ["en_US_POSIX", "de_CH"].map { loc in
            let d = DateFormatter()
            d.locale = Locale(identifier: loc)
            d.dateFormat = f
            return d
        }
    }

    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        if let d = ISO8601DateFormatter().date(from: t) { return d }
        for f in formatters { if let d = f.date(from: t) { return d } }
        if let unix = Double(t), unix > 1_000_000_000 { return Date(timeIntervalSince1970: unix > 1e12 ? unix / 1000 : unix) }
        return nil
    }

    static func number(_ s: String) -> Double? {
        Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "\" kglbsKGLBS")).replacingOccurrences(of: ",", with: "."))
    }

    // MARK: Training

    static func importWorkouts(from url: URL, into store: TrainingStore) throws -> Int {
        let table = parseCSV(try readText(url))
        guard let dateCol = table.column(["date", "datum", "start", "time", "zeit"], excluding: ["end", "ende"]),
              let exCol = table.column(["exercise", "übung", "uebung", "exercise_title"], excluding: ["note", "notiz", "id"]) ?? table.column(["name"], excluding: ["workout", "routine"]),
              let repsCol = table.column(["reps", "wdh", "wiederholung", "repetitions"])
        else { throw ImportError.columns("Datum, Übung und Wiederholungen") }
        let weightCol = table.column(["weight", "gewicht", "kg", "lbs", "last"], excluding: ["body", "körper", "distance"])
        let nameCol = table.column(["workout", "routine", "title", "session", "einheit"], excluding: ["exercise", "übung", "note", "duration", "dauer"])
        let lbs = weightCol.map { table.header[$0].lowercased().contains("lb") } ?? false
        let typeCol = table.column(["set_type", "type", "satztyp"])

        var workouts: [Date: Workout] = [:]
        for row in table.rows {
            guard row.count > max(dateCol, exCol, repsCol), let d = date(row[dateCol]),
                  let reps = number(row[repsCol]).map({ Int($0) }), reps > 0 else { continue }
            if let typeCol, row.count > typeCol, row[typeCol].lowercased().contains("warm") { continue }
            let exName = row[exCol].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            guard !exName.isEmpty else { continue }
            var weight = weightCol.flatMap { row.count > $0 ? number(row[$0]) : nil } ?? 0
            if lbs { weight *= 0.4536 }
            // group sets of the same session: same day (and same workout name, if present)
            let day = Calendar.current.startOfDay(for: d)
            let key = workouts.keys.first { Calendar.current.isDate($0, inSameDayAs: day) } ?? d
            var w = workouts[key] ?? Workout(name: nameCol.flatMap { row.count > $0 ? row[$0] : nil }?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? "Importiert",
                                             start: key, end: key.addingTimeInterval(3600))
            let exercise = store.exercise(named: exName)
            let set = SetEntry(weight: (weight * 10).rounded() / 10, reps: reps, done: true)
            if let i = w.entries.firstIndex(where: { $0.exerciseID == exercise.id }) {
                w.entries[i].sets.append(set)
            } else {
                w.entries.append(WorkoutEntry(exerciseID: exercise.id, sets: [set]))
            }
            workouts[key] = w
        }
        guard !workouts.isEmpty else { throw ImportError.empty }
        return store.importWorkouts(Array(workouts.values))
    }

    // MARK: Weight

    static func importWeights(from url: URL, into store: WeightStore) throws -> Int {
        let table = parseCSV(try readText(url))
        guard let dateCol = table.column(["date", "datum", "time", "zeit"]),
              let wCol = table.column(["weight", "gewicht", "kg", "lbs", "mass"], excluding: ["trend", "goal", "ziel"])
        else { throw ImportError.columns("Datum und Gewicht") }
        let lbs = table.header[wCol].lowercased().contains("lb")
        var count = 0
        for row in table.rows where row.count > max(dateCol, wCol) {
            guard let d = date(row[dateCol]), var kg = number(row[wCol]), kg > 0 else { continue }
            if lbs { kg *= 0.4536 }
            if store.entries.contains(where: { abs($0.date.timeIntervalSince(d)) < 60 }) { continue }
            store.add((kg * 10).rounded() / 10, at: d, syncToHealth: false)
            count += 1
        }
        guard count > 0 || !table.rows.isEmpty else { throw ImportError.empty }
        return count
    }

    // MARK: PrEP

    /// Every date found in the file (one per line/row) becomes a logged dose.
    static func importDoses(from url: URL, into store: PrepStore) throws -> Int {
        let text = try readText(url)
        var count = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let cells = String(line).split(whereSeparator: { ",;\t".contains($0) }).map(String.init)
            guard let d = cells.lazy.compactMap(date).first, d <= Date() else { continue }
            if store.doses.contains(where: { abs($0.date.timeIntervalSince(d)) < 3600 }) { continue }
            store.importDose(at: d)
            count += 1
        }
        if count == 0 { throw ImportError.empty }
        return count
    }

    enum ImportError: LocalizedError {
        case columns(String), empty
        var errorDescription: String? {
            switch self {
            case .columns(let c): "Spalten nicht erkannt (benötigt: \(c)). Schick mir eine Beispieldatei, dann passe ich den Import an."
            case .empty: "Keine passenden Einträge gefunden."
            }
        }
    }
}

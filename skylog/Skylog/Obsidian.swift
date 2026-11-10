import Foundation

/// Access to the user's Obsidian vault (a folder in Files/iCloud) via a security-scoped bookmark.
enum ObsidianVault {
    private static let bookmarkKey = "obsidianBookmark"
    private static let notesKey = "obsidianNotes"

    static var isConnected: Bool { UserDefaults.standard.data(forKey: bookmarkKey) != nil }

    /// Relative paths of the notes the user allowed Skylog to use.
    static var selectedNotes: [String] {
        get { UserDefaults.standard.stringArray(forKey: notesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: notesKey) }
    }

    static func connect(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func disconnect() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        selectedNotes = []
    }

    /// Runs `body` with access to the vault folder.
    static func withVault<T>(_ body: (URL) throws -> T) throws -> T {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { throw VaultError.notConnected }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: bookmarkKey) }
        return try body(url)
    }

    enum VaultError: LocalizedError {
        case notConnected
        var errorDescription: String? { String(localized: "Kein Obsidian-Vault verbunden (Einstellungen → Persönliches Profil).") }
    }


    static var vaultName: String {
        (try? withVault { $0.lastPathComponent }) ?? "–"
    }

    /// All markdown notes (relative paths), without the .obsidian folder.
    static func allNotes(limit: Int = 3000) throws -> [String] {
        try withVault { root in
            var result: [String] = []
            let keys: [URLResourceKey] = [.isDirectoryKey]
            guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return [] }
            for case let url as URL in e {
                if url.pathExtension.lowercased() == "md" {
                    result.append(String(url.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")))
                    if result.count >= limit { break }
                }
            }
            return result.sorted()
        }
    }

    /// Text of the selected notes (for the AI), capped in length.
    static func selectedText(maxChars: Int = 15000) -> String {
        guard isConnected, !selectedNotes.isEmpty else { return "" }
        return (try? withVault { root in
            var out = ""
            for path in selectedNotes {
                guard let text = try? String(contentsOf: root.appending(path: path), encoding: .utf8) else { continue }
                out += "## Notiz: \(path)\n\(text)\n\n"
                if out.count > maxChars { break }
            }
            return String(out.prefix(maxChars))
        }) ?? ""
    }

    /// Writes a note into "<vault>/Skylog/<name>.md".
    static func write(name: String, markdown: String) throws -> String {
        try withVault { root in
            let folder = root.appending(path: "Skylog")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let url = folder.appending(path: "\(safe).md")
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return "Skylog/\(safe).md"
        }
    }
}

/// Personal context for the AI: "about me" text + selected Obsidian notes.
enum PersonalProfile {
    static var aboutMe: String { UserDefaults.standard.string(forKey: "aboutMe") ?? "" }

    static var text: String {
        var parts: [String] = []
        if !aboutMe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { parts.append("Über mich / KI-Erinnerungen:\n\(aboutMe)") }
        let vault = ObsidianVault.selectedText()
        if !vault.isEmpty { parts.append("Aus meinen Obsidian-Notizen:\n\(vault)") }
        return parts.joined(separator: "\n\n")
    }
}

/// Personal packing list with the AI.
@MainActor
enum PackingAI {
    struct Item: Codable, Hashable { let name: String; let category: String; let reason: String }
    private struct Response: Codable { let items: [Item] }

    static let schema: [String: Any] = {
        let item: [String: Any] = [
            "type": "object", "additionalProperties": false, "required": ["name", "category", "reason"],
            "properties": ["name": ["type": "string"], "category": ["type": "string"], "reason": ["type": "string"]],
        ]
        return ["type": "object", "additionalProperties": false, "required": ["items"],
                "properties": ["items": ["type": "array", "items": item]]]
    }()

    static func generate(trip: Trip, flights: [Flight], bookings: [TravelBooking]) async throws -> [Item] {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        var context = "Reise: \(trip.name), \(f.string(from: trip.start)) bis \(f.string(from: trip.end)) (\(max(1, Calendar.current.dateComponents([.day], from: trip.start, to: trip.end).day ?? 1)) Tage)\n"
        if !flights.isEmpty {
            context += "Flüge: " + flights.map { "\($0.departure.code)→\($0.arrival.code) (\($0.arrival.displayCity), \($0.arrival.countryCode ?? ""))" }.joined(separator: ", ") + "\n"
            let longHaul = flights.contains { ($0.computedDistanceKm ?? 0) > 4000 }
            if longHaul { context += "Mit Langstreckenflug.\n" }
        }
        if !bookings.isEmpty {
            context += "Buchungen: " + bookings.map { "\($0.kind.label) \($0.name) in \($0.city)" }.joined(separator: "; ") + "\n"
        }
        if let plan = trip.plan {
            context += "Geplante Aktivitäten: " + plan.days.flatMap { $0.items.map(\.title) }.prefix(40).joined(separator: ", ") + "\n"
        }
        context += "Bereits auf der Packliste: " + trip.packing.map(\.name).joined(separator: ", ") + "\n"
        let profile = PersonalProfile.text
        if !profile.isEmpty { context += "\n\(profile)\n" }

        let system = """
        Du erstellst eine persönliche Packliste auf Deutsch (Schweizer Schreibweise, kein ß).
        Nutze die persönlichen Infos (Gewohnheiten, Gesundheit, Hobbys, Geräte, frühere Learnings) und die Reise (Ziel, Klima zur Reisezeit, Dauer, Aktivitäten, Unterkunft).
        Liste 15–35 Dinge, die NICHT schon auf der Packliste stehen. Kategorie z.B. Dokumente, Kleidung, Hygiene, Gesundheit, Technik, Aktivitäten, Sonstiges.
        reason: kurz, warum (z.B. „du trägst Kontaktlinsen“, „Regenzeit in Salta“). Keine sensiblen Details wörtlich wiederholen.
        """
        let text = try await AIClient.send(system: system, user: context, schema: schema, effort: "low", maxTokens: 6000)
        return try JSONDecoder().decode(Response.self, from: Data(text.utf8)).items
    }

    static func markdown(trip: Trip) -> String {
        var md = "# " + String(localized: "Packliste – \(trip.name)") + "\n\n"
        md += "_\(trip.start.formatted(date: .long, time: .omitted)) – \(trip.end.formatted(date: .long, time: .omitted)) · " + String(localized: "erstellt mit Skylog") + "_\n\n"
        for item in trip.packing { md += "- [\(item.done ? "x" : " ")] \(item.name)\n" }
        return md
    }

    static func planMarkdown(trip: Trip, plan: TripPlan) -> String {
        var md = "# " + String(localized: "Reiseplan – \(trip.name)") + "\n\n\(plan.summary)\n"
        for d in plan.days {
            md += "\n## \(d.date) · \(d.title)\n"
            for i in d.items { md += "- **\(i.time)** \(i.title) – \(i.description)\n" }
        }
        md += "\n## " + String(localized: "Tipps") + "\n" + plan.tips.map { "- \($0)" }.joined(separator: "\n")
        md += "\n\n## " + String(localized: "Budget") + "\n\(plan.budget)\n"
        return md
    }
}

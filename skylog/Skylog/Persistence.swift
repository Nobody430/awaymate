import Foundation

/// Loads a JSON file without ever risking the data: if the file exists but can't be read,
/// a copy is kept and saving is blocked (otherwise the next save would overwrite everything with an empty list).
enum SafeFile {
    struct Loaded<T> {
        var value: T?
        /// false = file is damaged/unreadable; don't overwrite it
        var writable: Bool
    }

    static func load<T: Decodable>(_ type: T.Type, from url: URL, decoder: JSONDecoder) -> Loaded<T> {
        guard FileManager.default.fileExists(atPath: url.path) else { return Loaded(value: nil, writable: true) }
        guard let data = try? Data(contentsOf: url) else { return Loaded(value: nil, writable: false) }
        if let v = try? decoder.decode(T.self, from: data) { return Loaded(value: v, writable: true) }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingPathExtension().appendingPathExtension("defekt-\(stamp).json")
        let saved = (try? data.write(to: backup, options: .atomic)) != nil
        // with a safe copy on disk we may continue with an empty list
        return Loaded(value: nil, writable: saved)
    }
}

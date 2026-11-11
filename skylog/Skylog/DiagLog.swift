import Foundation

/// Small diagnostic log on the device (last ~800 lines) that the user can share when something looks wrong.
/// Never contains API keys, tokens or mail contents – only what the app did and what the data sources answered.
enum DiagLog {
    private static let url = URL.documentsDirectory.appending(path: "diagnose.log")
    private static let queue = DispatchQueue(label: "skylog.diaglog")
    private static let maxBytes = 160_000

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "MM-dd HH:mm:ss'Z'"
        return f
    }()

    static func add(_ area: String, _ text: String) {
        let line = "\(stamp.string(from: Date())) [\(area)] \(text)\n"
        queue.async {
            var data = (try? Data(contentsOf: url)) ?? Data()
            data.append(Data(line.utf8))
            if data.count > maxBytes {
                // keep the newer half, cut at a line break
                let tail = data.suffix(maxBytes / 2)
                if let nl = tail.firstIndex(of: 0x0A) { data = Data(tail[tail.index(after: nl)...]) } else { data = Data(tail) }
            }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// File to share: the log plus a header describing the setup (no secrets).
    static func exportURL(flights: [Flight]) -> URL? {
        let d = UserDefaults.standard
        let info = Bundle.main.infoDictionary
        var head = "Awaymate Diagnose\n"
        head += "Version \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?")), iOS \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        head += "Sprache \(Bundle.main.preferredLocalizations.first ?? "?"), Zeitzone \(TimeZone.current.identifier)\n"
        head += "Datenquelle \(d.string(forKey: "provider") ?? "aerodatabox"), FlightAware-Key \(FlightAware.hasKey ? "ja" : "nein"), AeroDataBox-Key \(Settings.hasKey ? "ja" : "nein")\n"
        head += "Push-Server \((d.string(forKey: "pushServerURL") ?? "").isEmpty ? "nein" : "ja"), Reisemodus \(d.object(forKey: "travelMode") as? Bool ?? true ? "an" : "aus"), Geräte-Abgleich \(d.bool(forKey: "deviceSync") ? "an" : "aus")\n"
        head += "Abfragen diesen Monat \(Usage.thisMonth)\n\nAktive Flüge:\n"
        let iso = ISO8601DateFormatter()
        for f in flights where !f.isPast {
            let p = f.lastPosition.map { "pos \(String(format: "%.3f/%.3f", $0.lat, $0.lon)) \($0.source) \(iso.string(from: $0.timestamp))" } ?? "pos –"
            head += "- \(f.number) \(f.departure.code)→\(f.arrival.code) status=\(f.status ?? "nil") dep=\(f.departure.best.map(iso.string(from:)) ?? "–") arr=\(f.arrival.best.map(iso.string(from:)) ?? "–") gate=\(f.departure.gate ?? "–") cs=\(f.callSign ?? "–") hex=\(f.icao24 ?? "–") reg=\(f.aircraftReg ?? "–") \(p)\n"
        }
        head += "\nProtokoll (UTC, neueste unten):\n"
        let body = queue.sync { (try? String(contentsOf: url, encoding: .utf8)) ?? "(leer)\n" }
        let out = FileManager.default.temporaryDirectory.appending(path: "Awaymate-Diagnose.txt")
        guard (try? Data((head + body).utf8).write(to: out, options: .atomic)) != nil else { return nil }
        return out
    }

    static func clear() { queue.async { try? FileManager.default.removeItem(at: url) } }
}
